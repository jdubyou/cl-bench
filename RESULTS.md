# Results

Run on October 30, 2026 with the same scripts on three 16 vCPU / 128 GB VMs, each with a 500 GB block
volume and Ubuntu 24.04:

| VM | CPU | One vCPU is | Block volume |
|---|---|---|---|
| CloudLogics AMD | AMD EPYC 9745 | one physical core | CloudLogics NVMe Ceph |
| CloudLogics Intel | Intel Xeon 6756E | one physical E-core | CloudLogics NVMe Ceph |
| AWS r7a.4xlarge (us-east-1, $1.2172/hr on demand) | AMD EPYC 9R14 | one physical core | EBS gp3, default settings |

Both CloudLogics VMs ran on **shared production hosts** next to other tenants' workloads; the AMD host
was also running GPU VMs. Nothing was isolated or tuned. Raw output: [`results/`](results/).

**Status:** CPU, memory, storage, PostgreSQL and the 2-hour consistency test are done on all three VMs.
A GPU test (NVIDIA L40S) is in progress.

## CPU and memory

| Test | CloudLogics AMD | AWS r7a.4xlarge | CloudLogics Intel | Better is |
|---|---|---|---|---|
| 7-Zip `7z b`, total MIPS (median of 3) | **98,335** | 87,407 | 49,784 | higher |
| Linux 6.6 defconfig build, seconds (median of 3) | **67.8** | 86.8 | 164.7 | lower |
| sysbench cpu, events/second | **27,322** | 26,231 | 17,454 | higher |
| STREAM Triad, GB/s | **362** | 79 | 144 | higher |

Spread across the three repeats: kernel build within 1% on all VMs; 7-Zip within 1.1% (CloudLogics
AMD), 1.4% (AWS) and 3.7% (CloudLogics Intel).

## Block storage (fio on the attached volume)

| Test | CloudLogics AMD | AWS r7a.4xlarge (gp3) | CloudLogics Intel |
|---|---|---|---|
| 4K random read, QD32 x 4 jobs | **66,188 IOPS** | 2,998 IOPS | 52,996 IOPS |
| 4K random write, QD32 x 4 jobs | **62,115 IOPS** | 2,998 IOPS | 40,375 IOPS |
| 1M sequential read | **1,487 MB/s** | 125 MB/s | 1,487 MB/s |
| 1M sequential write | **2,518 MB/s** | 125 MB/s | 1,951 MB/s |
| 4K random read, QD1: IOPS / p99 latency | 870 / 1.4 ms | **1,734 / 0.67 ms** | 392 / 3.0 ms |

AWS gp3 was used at its default 3,000 IOPS and 125 MB/s, which it hit exactly; gp3 can be raised to
16,000 IOPS and 1,000 MB/s for an extra charge. CloudLogics volumes deliver much higher throughput,
while a single request at a time (QD1) completes faster on gp3.

## PostgreSQL (pgbench, scale 1000, about 15 GB)

| Test | CloudLogics AMD | AWS r7a.4xlarge | CloudLogics Intel |
|---|---|---|---|
| TPC-B read/write, 32 clients, 300 s | 5,129 TPS (6.2 ms avg) | **16,308 TPS** (2.0 ms avg) | 3,299 TPS (9.7 ms avg) |
| Select-only, 64 clients, 120 s | **723,722 TPS** (0.09 ms avg) | 402,765 TPS (0.16 ms avg) | 213,639 TPS (0.30 ms avg) |
| Load 100M rows (seconds) | **135** | 328 | 289 |

PostgreSQL 16, data on the attached block volume, settings in [`tests/03_postgres.sh`](tests/03_postgres.sh).
Read-heavy work and bulk loads ran faster on CloudLogics AMD. The write-heavy TPC-B test ran faster on
AWS: each commit waits for one small write to the volume, and that single-write latency (see the QD1 row
above) is lower on gp3.

## Consistency on a shared host (2 hours)

7-Zip benchmark repeated 24 times, every 5 minutes, while each VM's host carried its normal load. A
small spread means other tenants on the same host are not slowing the VM down.

| | CloudLogics AMD | AWS r7a.4xlarge | CloudLogics Intel |
|---|---|---|---|
| Runs | 24 | 24 | 24 |
| Median MIPS | **98,807** | 87,493 | 48,276 |
| Lowest / highest | 97,908 / 99,479 | 86,386 / 88,130 | 46,727 / 49,464 |
| Coefficient of variation | 0.44% | **0.41%** | 1.69% |

The CloudLogics AMD VM was as steady as AWS while running about 13% faster, on a host shared with
other tenants' CPU and GPU VMs.

## Reproduce it

Run the same script on any VM (see the [README](README.md#reproduce-it)) and compare line by line.
