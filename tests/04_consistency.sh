#!/usr/bin/env bash
# Noisy-neighbor check on a shared production host: repeat a short 7-Zip run every
# INTERVAL seconds and record the spread. Steady numbers = neighbors are not hurting us.
set -euo pipefail
OUT=$1; ROUNDS=${ROUNDS:-24}; INTERVAL=${INTERVAL:-300}; N=$(nproc)
for i in $(seq 1 $ROUNDS); do
  r=$(7z b -mmt$N 2>&1 | awk '/^Tot:/{print $4}')
  st=$(awk '/^cpu /{print $9}' /proc/stat)
  echo "$(date -u +%FT%TZ) mips=$r steal_jiffies=$st load=$(cut -d' ' -f1 /proc/loadavg)" | tee -a "$OUT/consistency.log"
  [ $i -lt $ROUNDS ] && sleep $INTERVAL
done
