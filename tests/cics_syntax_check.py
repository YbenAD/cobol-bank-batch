#!/usr/bin/env python3
"""Vérification syntaxique du programme CICS BNKCON01 avec GnuCOBOL.

GnuCOBOL ne connaît pas CICS. Ce script prépare une copie du programme où :
  - chaque bloc EXEC CICS ... END-EXEC est remplacé par CONTINUE ;
  - DFHRESP(xxx) est remplacé par la valeur numérique du code RESP ;
  - les zones EIB utilisées (EIBCALEN, EIBAID) sont déclarées ;
  - les copybooks CICS (DFHAID, DFHBMSCA) et la map symbolique BNKMS01
    sont simulés avec la même structure que les vrais.

Tout le reste du COBOL (données, logique, copybook CPYCPT) est donc
compilé et vérifié. Le vrai traducteur CICS reste celui de z/OS (DFHZITCL).

Usage : python3 tests/cics_syntax_check.py
"""
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESP = {"NORMAL": 0, "NOTFND": 13, "NOTOPEN": 19, "MAPFAIL": 36, "DISABLED": 84}

# Champs nommés du mapset BNKMS01 (nom, longueur), dans l'ordre du source BMS
FIELDS = [("DATEJ", 10), ("NUMCPT", 11), ("TITU", 30), ("SOLDE", 18),
          ("DECOUV", 18), ("DISPO", 18), ("STAT", 10), ("DTMAJ", 10),
          ("MSG", 78)]


def symbolic_map() -> str:
    """Map symbolique équivalente à la DSECT BMS (TIOAPFX=YES, DSATTS=COLOR)."""
    i = ["       01  BNKMP01I.", "           02  FILLER PIC X(12)."]
    o = ["       01  BNKMP01O REDEFINES BNKMP01I.",
         "           02  FILLER PIC X(12)."]
    for name, length in FIELDS:
        i += [f"           02  {name}L COMP PIC S9(4).",
              f"           02  {name}F PIC X.",
              f"           02  FILLER REDEFINES {name}F.",
              f"             03 {name}A PIC X.",
              "           02  FILLER PIC X(1).",
              f"           02  {name}I PIC X({length})."]
        o += ["           02  FILLER PIC X(3).",
              f"           02  {name}C PIC X.",
              f"           02  {name}O PIC X({length})."]
    return "\n".join(i + o) + "\n"


def main() -> int:
    src = (ROOT / "src/cobol/BNKCON01.cbl").read_text()

    # Vérifie que chaque champ du programme existe bien dans le source BMS
    bms = (ROOT / "src/bms/BNKMS01.bms").read_text()
    for name, length in FIELDS:
        pattern = rf"^{name}\s+DFHMDF\s.*LENGTH={length}\b"
        if not re.search(pattern, bms, flags=re.M):
            print(f"KO   champ {name} (longueur {length}) absent du BMS")
            return 1

    src = re.sub(r"EXEC CICS.*?END-EXEC", "CONTINUE", src, flags=re.S)
    src = re.sub(r"DFHRESP\((\w+)\)", lambda m: str(RESP[m.group(1)]), src)
    src = src.replace(
        "       LINKAGE SECTION.",
        "       01  EIBCALEN PIC S9(4) COMP.\n"
        "       01  EIBAID   PIC X.\n"
        "       LINKAGE SECTION.")

    with tempfile.TemporaryDirectory() as tmp:
        t = pathlib.Path(tmp)
        (t / "BNKCON01.cbl").write_text(src)
        (t / "BNKMS01.cpy").write_text(symbolic_map())
        (t / "DFHAID.cpy").write_text(
            "       01  DFHAID.\n"
            "           02  DFHENTER PIC X VALUE QUOTE.\n"
            "           02  DFHCLEAR PIC X VALUE '_'.\n"
            "           02  DFHPF3   PIC X VALUE '3'.\n")
        (t / "DFHBMSCA.cpy").write_text(
            "       01  DFHBMSCA.\n"
            "           02  DFHRED   PIC X VALUE '2'.\n"
            "           02  DFHGREEN PIC X VALUE '4'.\n"
            "           02  DFHYELLO PIC X VALUE '6'.\n")
        cmd = ["cobc", "-fsyntax-only", "-std=ibm",
               "-I", str(t), "-I", str(ROOT / "src/copybook"),
               str(t / "BNKCON01.cbl")]
        result = subprocess.run(cmd, capture_output=True, text=True)
        output = "\n".join(
            line for line in (result.stdout + result.stderr).splitlines()
            if "FORTIFY" not in line and "previous definition" not in line)
        if output:
            print(output)
        if result.returncode != 0:
            print("KO   syntaxe COBOL du programme CICS BNKCON01")
            return 1
    print("OK   syntaxe COBOL du programme CICS BNKCON01")
    return 0


if __name__ == "__main__":
    sys.exit(main())
