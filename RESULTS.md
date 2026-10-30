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

**Status:** all CPU, memory, storage, PostgreSQL and consistency tests are done on all three VMs, plus a
GPU inference test on one NVIDIA L40S (CloudLogics only so far).

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

## GPU: LLM inference on one NVIDIA L40S (48 GB)

CloudLogics VM with one L40S (PCI passthrough, 16 vCPU, 64 GB), vLLM 0.10.2, random prompts of 512 input
and 256 output tokens. Script: [`tests/05_gpu.sh`](tests/05_gpu.sh). The matching AWS instance is
**g6e.xlarge** (also one L40S); AWS results are not in yet.

**Whole GPU, one Qwen2.5-7B-Instruct server**

| Simultaneous requests | Total output tokens/s | Median time to first token | Median time per output token |
|---|---|---|---|
| 1 | 49 | 44 ms | 20.5 ms |
| 16 | 650 | 160 ms | 23.7 ms |
| 64 | **1,853** | 124 ms | 31.3 ms |

**Shared GPU: N separate tenants, each with its own Qwen2.5-1.5B-Instruct server and 1/N of GPU memory, all
running at once (time-slicing; the L40S does not support MIG)**

| Tenants | Output tokens/s per tenant | Total output tokens/s | Median time per output token |
|---|---|---|---|
| 1 | 1,154 | 1,154 | 6.6 ms |
| 2 | 589 | 1,178 | 13.0 ms |
| 4 | 295 to 296 | 1,182 | 25.9 ms |
| 7 | 168 | 1,176 | 45.4 ms |

Total output stays flat as tenants are added, and every tenant gets an equal share (within 1%). Sharing
splits the GPU fairly without losing throughput; each tenant's speed falls to about 1/N. The 7-tenant run
gave each tenant 0.85/7 of GPU memory instead of 0.90/7 so all seven processes fit.

## Reproduce it

Run the same script on any VM (see the [README](README.md#reproduce-it)) and compare line by line.
