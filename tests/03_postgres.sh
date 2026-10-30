#!/usr/bin/env bash
# PostgreSQL 16 + pgbench on the data volume. To compare against RDS, run the pgbench
# lines with -h <rds-endpoint> -U <user> against an RDS instance of the same size.
set -euo pipefail
OUT=$1; PGD="$DATA/pg"; V=$(ls /usr/lib/postgresql | sort -n | tail -1); B=/usr/lib/postgresql/$V/bin
MEM=$(free -g | awk '/Mem:/{print $2}')
sudo systemctl stop postgresql || true
sudo rm -rf "$PGD"; sudo mkdir -p "$PGD"; sudo chown postgres "$PGD"
sudo -u postgres $B/initdb -D "$PGD" >/dev/null
sudo -u postgres tee -a "$PGD/postgresql.conf" >/dev/null <<CONF
shared_buffers = $((MEM/4))GB
effective_cache_size = $((MEM*3/4))GB
max_connections = 200
max_wal_size = 32GB
checkpoint_timeout = 15min
wal_compression = on
CONF
sudo -u postgres $B/pg_ctl -D "$PGD" -l "$PGD/server.log" -w start >/dev/null
PB="sudo -u postgres $B/pgbench"
echo "== pgbench init, scale 1000 (~15 GB)" | tee -a "$OUT/postgres.log"
sudo -u postgres $B/createdb bench
s=$(date +%s); $PB -i -s 1000 -q bench >/dev/null 2>&1; echo "init_s $(( $(date +%s)-s ))" | tee -a "$OUT/postgres.log"
echo "== TPC-B read/write, 32 clients, 300 s" | tee -a "$OUT/postgres.log"
$PB -c 32 -j 16 -T 300 -P 60 bench 2>&1 | grep -E "^(tps|latency average)" | tee -a "$OUT/postgres.log"
echo "== select-only, 64 clients, 120 s" | tee -a "$OUT/postgres.log"
$PB -S -c 64 -j 16 -T 120 bench 2>&1 | grep -E "^(tps|latency average)" | tee -a "$OUT/postgres.log"
sudo -u postgres $B/pg_ctl -D "$PGD" -w -t 900 stop >/dev/null
sudo cp "$PGD/server.log" "$OUT/pg_server.log"; sudo chown $(id -u) "$OUT/pg_server.log"
sudo rm -rf "$PGD"
