#!/usr/bin/env python3
"""Vérification syntaxique des programmes CICS et DB2 avec GnuCOBOL.

GnuCOBOL ne connaît ni CICS ni DB2. Pour chaque programme, ce script prépare
une copie où :
  - EXEC SQL INCLUDE SQLCA est remplacé par une SQLCA minimale ;
  - EXEC SQL INCLUDE <copybook> est remplacé par le copybook (DCLGEN) dont
    les blocs EXEC SQL sont retirés ;
  - les autres blocs EXEC SQL / EXEC CICS sont retirés de la DATA DIVISION
    (DECLARE CURSOR) et remplacés par CONTINUE dans la PROCEDURE DIVISION ;
  - DFHRESP(xxx) est remplacé par la valeur numérique du code RESP ;
  - les zones EIB utilisées sont déclarées ;
  - la map symbolique de chaque mapset est générée à partir du source BMS
    (même structure que la DSECT : TIOAPFX, champs L/F/A/C/I/O). Un champ
    utilisé par le programme mais absent de l'écran fait donc échouer la
    compilation.

Tout le reste du COBOL est compilé et vérifié. Les vrais précompilateur DB2
et traducteur CICS restent ceux de z/OS.

Usage : python3 tests/zos_syntax_check.py
"""
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROGRAMS = ["BNKCON01", "BNKHIS01", "BNKDB201", "BNKEXT01"]
RESP = {"NORMAL": 0, "NOTFND": 13, "NOTOPEN": 19, "ENDFILE": 20, "MAPFAIL": 36,
        "DISABLED": 84}

DFHAID = """       01  DFHAID.
           02  DFHENTER PIC X VALUE QUOTE.
           02  DFHCLEAR PIC X VALUE '_'.
           02  DFHPF3   PIC X VALUE '3'.
           02  DFHPF7   PIC X VALUE '7'.
           02  DFHPF8   PIC X VALUE '8'.
"""
DFHBMSCA = """       01  DFHBMSCA.
           02  DFHNEUTR PIC X VALUE '7'.
           02  DFHRED   PIC X VALUE '2'.
           02  DFHGREEN PIC X VALUE '4'.
           02  DFHYELLO PIC X VALUE '6'.
"""
SQLCA = """       01  SQLCA.
           05  SQLCAID  PIC X(8).
           05  SQLCABC  PIC S9(9) COMP.
           05  SQLCODE  PIC S9(9) COMP.
           05  FILLER   PIC X(120).
"""


def bms_statements(text):
    """Regroupe les lignes continuées (colonne 72 non blanche)."""
    stmt = ""
    for line in text.splitlines():
        if line.startswith("*"):
            continue
        cont = len(line) >= 72 and line[71] != " "
        body = line[:71]
        stmt += body if not stmt else body[15:]
        if not cont:
            yield stmt.rstrip()
            stmt = ""


def symbolic_map(bms_text):
    """Génère la map symbolique COBOL équivalente à la DSECT BMS."""
    out, dsatts, fields, mapname = [], False, [], None

    def flush():
        if not mapname:
            return
        i = [f"       01  {mapname}I.", "           02  FILLER PIC X(12)."]
        o = [f"       01  {mapname}O REDEFINES {mapname}I.",
             "           02  FILLER PIC X(12)."]
        for name, length in fields:
            i += [f"           02  {name}L COMP PIC S9(4).",
                  f"           02  {name}F PIC X.",
                  f"           02  FILLER REDEFINES {name}F.",
                  f"             03 {name}A PIC X."]
            if dsatts:
                i.append("           02  FILLER PIC X(1).")
            i.append(f"           02  {name}I PIC X({length}).")
            o.append("           02  FILLER PIC X(3)." if dsatts
                     else "           02  FILLER PIC X(2).")
            if dsatts:
                o.append(f"           02  {name}C PIC X.")
            o.append(f"           02  {name}O PIC X({length}).")
        out.extend(i + o)

    for stmt in bms_statements(bms_text):
        parts = stmt.split(None, 2) if not stmt.startswith(" ") else \
            [""] + stmt.split(None, 1)
        label, op = parts[0], parts[1] if len(parts) > 1 else ""
        operands = parts[2] if len(parts) > 2 else ""
        if op == "DFHMSD" and "DSATTS" in operands:
            dsatts = True
        elif op == "DFHMDI":
            flush()
            mapname, fields = label, []
        elif op == "DFHMDF" and label:
            length = re.search(r"LENGTH=(\d+)", operands).group(1)
            fields.append((label, length))
    flush()
    return "\n".join(out) + "\n"


def strip_exec(text, replacement, keep_period=True):
    """Remplace chaque bloc EXEC ... END-EXEC. Dans la PROCEDURE DIVISION,
    le point final éventuel est gardé (il peut terminer un paragraphe)."""
    def repl(match):
        period = keep_period and match.group(0).endswith(".")
        return replacement + ("." if period else "")
    return re.sub(r"EXEC (SQL|CICS).*?END-EXEC\.?", repl, text, flags=re.S)


def prepare(src, copydir):
    """Transforme le source z/OS en source compilable par GnuCOBOL."""
    def include(match):
        name = match.group(1)
        if name == "SQLCA":
            return SQLCA
        cpy = (ROOT / "src/copybook" / f"{name}.cpy").read_text()
        return strip_exec(cpy, "", keep_period=False)

    src = re.sub(r"^ *EXEC SQL INCLUDE (\w+)\s+END-EXEC\.[ ]*$", include,
                 src, flags=re.M)
    data, sep, proc = src.partition("       PROCEDURE DIVISION.")
    data = strip_exec(data, "", keep_period=False)
    proc = strip_exec(proc, "CONTINUE")
    proc = re.sub(r"DFHRESP\((\w+)\)", lambda m: str(RESP[m.group(1)]), proc)
    if "EIBCALEN" in proc or "EIBAID" in proc:
        eib = ("       01  EIBCALEN PIC S9(4) COMP.\n"
               "       01  EIBAID   PIC X.\n")
        if "       LINKAGE SECTION." in data:
            data = data.replace("       LINKAGE SECTION.",
                                eib + "       LINKAGE SECTION.")
        else:
            data += eib
    return data + sep + proc


def main():
    status = 0
    with tempfile.TemporaryDirectory() as tmp:
        t = pathlib.Path(tmp)
        (t / "DFHAID.cpy").write_text(DFHAID)
        (t / "DFHBMSCA.cpy").write_text(DFHBMSCA)
        for bms in (ROOT / "src/bms").glob("*.bms"):
            (t / f"{bms.stem}.cpy").write_text(symbolic_map(bms.read_text()))
        for prog in PROGRAMS:
            src = (ROOT / "src/cobol" / f"{prog}.cbl").read_text()
            (t / f"{prog}.cbl").write_text(prepare(src, t))
            cmd = ["cobc", "-fsyntax-only", "-std=ibm",
                   "-I", str(t), "-I", str(ROOT / "src/copybook"),
                   str(t / f"{prog}.cbl")]
            res = subprocess.run(cmd, capture_output=True, text=True)
            msgs = [l for l in (res.stdout + res.stderr).splitlines()
                    if "FORTIFY" not in l and "previous definition" not in l]
            if msgs:
                print("\n".join(msgs))
            if res.returncode != 0:
                print(f"KO   syntaxe COBOL de {prog}")
                status = 1
            else:
                print(f"OK   syntaxe COBOL de {prog}")
    return status


if __name__ == "__main__":
    sys.exit(main())
