#!/usr/bin/env bash
#-----------------------------------------------------------------------
# Exécution locale de la chaîne BNKCHAIN avec GnuCOBOL.
#
# Reproduit les steps du JCL jcl/BNKCHAIN.jcl :
#   STEP000  chargement initial du KSDS     (BNKINI01)
#   STEP010  validation des mouvements      (BNKVAL01)
#   STEP020  tri DFSORT                     (émulé avec sort)
#   STEP030  mise à jour des comptes        (BNKMAJ01)
#   STEP040  chargement DB2                 (non exécutable en local)
#
# Les fichiers sont convertis au format mainframe RECFM=FB (enregistrements
# de longueur fixe, sans fin de ligne). Les DD sont fournies au programme
# via les variables d'environnement DD_<nom>, comme une carte DD en JCL.
#
# Usage : tests/run_local.sh          -> exécute et compare aux attendus
#         tests/run_local.sh --update -> régénère les fichiers attendus
#-----------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
OUT="$BUILD/out"
EXPECTED="$ROOT/tests/expected"
DATE_TRT="20261101"

rm -rf "$BUILD"
mkdir -p "$OUT"

# Texte -> enregistrements fixes (FB) de longueur $2
to_fb()   { awk -v n="$2" '{ printf("%-" n "s", substr($0, 1, n)) }' "$1" > "$3"; }
# Enregistrements fixes -> texte lisible (blancs de fin supprimés)
from_fb() { fold -w "$2" "$1" | awk '{ sub(/ +$/, ""); print }' > "$3"; }

# Lance un programme et affiche son code retour, sans arrêter le script
run_step() {
  local step="$1" prog="$2" rc=0
  echo "---- $step : $prog"
  echo "$DATE_TRT" | "$BUILD/$prog" || rc=$?
  echo "---- $step : $prog RC=$rc"
  echo
  return "$rc"
}

echo "==== Compilation"
for p in BNKINI01 BNKVAL01 BNKMAJ01; do
  cobc -x -std=ibm -I "$ROOT/src/copybook" -o "$BUILD/$p" \
       "$ROOT/src/cobol/$p.cbl" 2>&1 | grep -v -e FORTIFY -e 'previous definition' || true
done
echo

to_fb "$ROOT/data/comptes.txt"    80 "$BUILD/seedcpt.dat"
to_fb "$ROOT/data/mouvements.txt" 80 "$BUILD/mvtin.dat"

export DD_SEEDCPT="$BUILD/seedcpt.dat"
export DD_CPTMST="$BUILD/cptmst.ksds"
export DD_MVTIN="$BUILD/mvtin.dat"
export DD_MVTOK="$BUILD/mvtvalid.dat"
export DD_MVTTRI="$BUILD/mvttri.dat"
export DD_MVTAPP="$BUILD/mvtapp.dat"
export DD_RAPPORT="$BUILD/rapport.dat"

run_step STEP000 BNKINI01

export DD_MVTREJ="$BUILD/mvtrej1.dat"
RC010=0; run_step STEP010 BNKVAL01 || RC010=$?
[ "$RC010" -le 4 ] || { echo "STEP010 en erreur, arrêt de la chaîne"; exit 1; }

# STEP020 : SORT FIELDS=(13,11,CH,A,36,8,CH,A,24,1,CH,A,1,12,CH,A)
echo "---- STEP020 : SORT (compte, date, type C avant D, référence)"
fold -w 80 "$BUILD/mvtvalid.dat" \
  | LC_ALL=C sort -t '|' -k1.13,1.23 -k1.36,1.43 -k1.24,1.24 -k1.1,1.12 \
  | tr -d '\n' > "$BUILD/mvttri.dat"
echo "---- STEP020 : SORT RC=0"
echo

export DD_MVTREJ="$BUILD/mvtrej2.dat"
RC030=0; run_step STEP030 BNKMAJ01 || RC030=$?
[ "$RC030" -le 4 ] || { echo "STEP030 en erreur, arrêt de la chaîne"; exit 1; }

echo "---- STEP040 : BNKDB201 (DB2) non exécuté en local, à lancer sur z/OS"
echo

# Sorties lisibles
from_fb "$BUILD/mvtrej1.dat"  120 "$OUT/rejets_validation.txt"
from_fb "$BUILD/mvtrej2.dat"  120 "$OUT/rejets_maj.txt"
from_fb "$BUILD/mvtapp.dat"    80 "$OUT/mouvements_appliques.txt"
from_fb "$BUILD/rapport.dat"  132 "$OUT/rapport.txt"

echo "==== Compte rendu BNKMAJ01"
cat "$OUT/rapport.txt"
echo

if [ "${1:-}" = "--update" ]; then
  mkdir -p "$EXPECTED"
  cp "$OUT"/*.txt "$EXPECTED/"
  echo "Fichiers attendus régénérés dans tests/expected/"
  exit 0
fi

echo "==== Comparaison avec les résultats attendus"
status=0
for f in "$EXPECTED"/*.txt; do
  name="$(basename "$f")"
  if diff -u "$f" "$OUT/$name"; then
    echo "OK   $name"
  else
    echo "KO   $name"
    status=1
  fi
done
[ "$RC010" -eq 4 ] && [ "$RC030" -eq 4 ] \
  && echo "OK   codes retour (STEP010=4, STEP030=4)" \
  || { echo "KO   codes retour (STEP010=$RC010, STEP030=$RC030)"; status=1; }
exit "$status"
