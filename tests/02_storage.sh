#!/usr/bin/env bash
# Block storage: fio against the attached data volume (CloudLogics Ceph NVMe / AWS EBS).
set -euo pipefail
OUT=$1; F="$DATA/fio.test"
run() { fio --name=$1 --filename=$F --size=32G --direct=1 --ioengine=libaio --time_based --runtime=60 \
        --ramp_time=10 --group_reporting --output-format=json "${@:2}" > "$OUT/fio_$1.json"
        jq -r --arg n $1 '.jobs[0] | "\($n) read_iops=\(.read.iops|floor) write_iops=\(.write.iops|floor) read_MBps=\(.read.bw/1024|floor) write_MBps=\(.write.bw/1024|floor) read_p99_us=\((.read.clat_ns.percentile["99.000000"]//0)/1000|floor) write_p99_us=\((.write.clat_ns.percentile["99.000000"]//0)/1000|floor)"' "$OUT/fio_$1.json" | tee -a "$OUT/storage.log"; }
run randread_4k  --rw=randread  --bs=4k --iodepth=32 --numjobs=4
run randwrite_4k --rw=randwrite --bs=4k --iodepth=32 --numjobs=4
run seqread_1m   --rw=read      --bs=1M --iodepth=16 --numjobs=1
run seqwrite_1m  --rw=write     --bs=1M --iodepth=16 --numjobs=1
run lat_4k_qd1   --rw=randread  --bs=4k --iodepth=1  --numjobs=1
rm -f $F
