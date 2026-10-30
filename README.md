# cl-bench

Reproducible benchmarks for CloudLogics virtual machines. Every test uses public, standard tools,
and the same script runs unchanged on CloudLogics or on AWS, so anyone can check the numbers.

## What it measures

| Test | Tool | What it shows |
|---|---|---|
| CPU | 7-Zip `7z b`, sysbench, Linux 6.6 kernel build | Compute throughput |
| Memory | STREAM (McCalpin) | Memory bandwidth |
| Block storage | fio | IOPS, throughput, p99 latency on the attached data volume |
| Database | PostgreSQL + pgbench (TPC-B and select-only) | Transactions per second |
| Consistency | 7-Zip repeated every 5 minutes for 2 hours | Whether neighbors on a shared host slow the VM down |

## How the CloudLogics results were produced

- Two 16 vCPU / 128 GB VMs with a 500 GB block volume mounted at `/data`, Ubuntu 24.04:
  - **AMD:** AMD EPYC 9745 (one vCPU = one physical core)
  - **Intel:** Intel Xeon 6756E (one vCPU = one physical E-core)
- Both VMs ran on **shared production hosts** alongside other tenants' VMs. The AMD host was also
  running GPU workloads at the time. Nothing was isolated or tuned for the test.

## Reproduce it

```bash
git clone <this repo> && cd cl-bench
# attach and mount a block volume at /data first (EBS gp3 on AWS)
DATA=/data ./run_all.sh setup cpu storage postgres consistency
```

Results land in `results/<hostname>-<timestamp>/`. Run any subset: `./run_all.sh setup cpu`.

### Suggested AWS comparisons (16 vCPU / 128 GB)

| Instance | Why |
|---|---|
| r7a.4xlarge | AMD EPYC, one vCPU = one physical core: the closest match to the AMD VM |
| r6a.4xlarge | AMD EPYC with SMT (16 vCPU = 8 cores) |
| r7i.4xlarge | Intel Xeon |

For PostgreSQL on **RDS**, create a `db.r5.4xlarge` or `db.r7g.4xlarge` instance, then run the
pgbench commands from `tests/03_postgres.sh` from an EC2 client with `-h <endpoint> -U <user>`.

## Results

See [RESULTS.md](RESULTS.md) and the raw output under `results/`.
