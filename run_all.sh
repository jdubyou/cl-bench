#!/usr/bin/env bash
# Usage: DATA=/data ./run_all.sh [tests...]   (default: setup cpu storage postgres)
# DATA must be the attached block volume (not the boot disk).
set -euo pipefail
cd "$(dirname "$0")"
export DATA=${DATA:-/data}
OUT=$PWD/results/$(hostname)-$(date -u +%Y%m%dT%H%MZ); mkdir -p "$OUT"
{ echo "host=$(hostname)"; echo "date=$(date -u +%FT%TZ)"; lscpu | grep -E "Model name|^CPU\(s\)|Thread|Socket|Flags" | sed 's/Flags:.*avx512f.*/avx512=yes/;s/Flags:.*/avx512=no/'
  free -g | awk '/Mem:/{print "mem_gb="$2}'; uname -r; lsb_release -ds; } > "$OUT/system.txt"
TESTS=${*:-setup cpu storage postgres}
for t in $TESTS; do
  case $t in
    setup) bash tests/00_setup.sh ;;
    cpu) bash tests/01_cpu.sh "$OUT" ;;
    storage) bash tests/02_storage.sh "$OUT" ;;
    postgres) bash tests/03_postgres.sh "$OUT" ;;
    consistency) bash tests/04_consistency.sh "$OUT" ;;
    gpu) bash tests/05_gpu.sh "$OUT" ;;
    deepstream) bash tests/06_deepstream.sh "$OUT" ;;
  esac
done
echo "results in $OUT"
