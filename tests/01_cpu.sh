#!/usr/bin/env bash
# CPU: 7-Zip benchmark, Linux kernel compile, sysbench, STREAM. All public, all repeatable.
set -euo pipefail
OUT=$1; N=$(nproc)
echo "== 7-Zip (7z b), $N threads, 3 runs" | tee -a "$OUT/cpu.log"
for i in 1 2 3; do 7z b -mmt$N 2>&1 | grep -E "^Tot:" | tee -a "$OUT/cpu.log"; done
echo "== sysbench cpu (prime 20000), $N threads, 60 s" | tee -a "$OUT/cpu.log"
sysbench cpu --threads=$N --cpu-max-prime=20000 --time=60 run | grep -E "events per second" | tee -a "$OUT/cpu.log"
echo "== STREAM, $N threads" | tee -a "$OUT/cpu.log"
OMP_NUM_THREADS=$N stream | grep -E "^(Copy|Scale|Add|Triad):" | tee -a "$OUT/cpu.log"
echo "== Linux 6.6 defconfig build, -j$N, 3 runs (seconds)" | tee -a "$OUT/cpu.log"
cd "$DATA/src/linux-6.6"
for i in 1 2 3; do
  make -s mrproper; make -s defconfig >/dev/null
  s=$(date +%s.%N); make -s -j$N >/dev/null 2>&1; e=$(date +%s.%N)
  echo "kernel_build_s $(echo "$e - $s" | bc)" | tee -a "$OUT/cpu.log"
done
make -s mrproper
