#!/usr/bin/env bash
# Installs everything the tests need. Ubuntu 24.04. Same script on CloudLogics and AWS.
set -euo pipefail
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  p7zip-full fio sysbench postgresql postgresql-contrib build-essential flex bison bc \
  libssl-dev libelf-dev libncurses-dev wget jq gcc >/dev/null
# STREAM memory bandwidth (McCalpin), sized well past cache
if [ ! -x /usr/local/bin/stream ]; then
  wget -q https://www.cs.virginia.edu/stream/FTP/Code/stream.c -O /tmp/stream.c
  gcc -O3 -fopenmp -march=native -DSTREAM_ARRAY_SIZE=400000000 -DNTIMES=10 -mcmodel=large /tmp/stream.c -o /tmp/stream
  sudo mv /tmp/stream /usr/local/bin/stream
fi
# Linux kernel source for the compile test (pinned version)
mkdir -p "$DATA/src"
[ -d "$DATA/src/linux-6.6" ] || (cd "$DATA/src" && wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.tar.xz && tar xf linux-6.6.tar.xz)
echo "setup done"
