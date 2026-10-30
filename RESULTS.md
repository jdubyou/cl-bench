# Results

Run on October 30, 2026 on two CloudLogics VMs (16 vCPU, 128 GB RAM, 500 GB block volume, Ubuntu 24.04).
Both VMs ran on **shared production hosts** next to other tenants' workloads; the AMD host was also
running GPU VMs. Nothing was isolated or tuned. Raw output: [`results/`](results/).

**Status:** CPU, memory and storage done. PostgreSQL and the 2-hour consistency test are running and
will be added here when they finish.

## CPU and memory

| Test | AMD EPYC 9745 VM | Intel Xeon 6756E VM | Better is |
|---|---|---|---|
| 7-Zip `7z b`, total MIPS (median of 3) | **98,335** | 49,784 | higher |
| Linux 6.6 defconfig build, seconds (median of 3) | **67.8** | 164.7 | lower |
| sysbench cpu, events/second | **27,322** | 17,454 | higher |
| STREAM Triad, GB/s | **362** | 144 | higher |

Run-to-run spread across the three repeats was under 1.1% on both VMs (7-Zip and kernel build).

## Block storage (fio on the attached volume)

| Test | AMD VM | Intel VM |
|---|---|---|
| 4K random read, QD32 x 4 jobs | 66,188 IOPS | 52,996 IOPS |
| 4K random write, QD32 x 4 jobs | 62,115 IOPS | 40,375 IOPS |
| 1M sequential read | 1,487 MB/s | 1,487 MB/s |
| 1M sequential write | 2,518 MB/s | 1,951 MB/s |
| 4K random read latency, QD1 (p99) | 1.4 ms | 3.0 ms |

Both volumes are on the same CloudLogics NVMe Ceph storage cluster.

## Compare on AWS

Run the same script on an AWS instance of the same size (see the [README](README.md#reproduce-it)) and
compare line by line. The closest match to the AMD VM is **r7a.4xlarge** (AMD EPYC, one vCPU = one
physical core, 128 GB).
