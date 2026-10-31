#!/usr/bin/env bash
set -uo pipefail
N=$1; SYNC=$2; RUN_S=$3; O=/out
cd /opt/nvidia/deepstream/deepstream/samples/configs/deepstream-app
E=../../models/Primary_Detector/resnet18_trafficcamnet_pruned.onnx_b${N}_gpu0_fp16.engine
sed -e "s/^batch-size=30/batch-size=$N/" -e "s#^model-engine-file=.*#model-engine-file=$E#" config_infer_primary.txt > config_infer_bench.txt
awk -v n=$N -v sync=$SYNC -v eng=$E '
  /^\[/ {sec=$0}
  sec=="[tiled-display]" && /^enable=/ {$0="enable=0"}
  sec=="[osd]" && /^enable=/ {$0="enable=0"}
  sec=="[sink0]" && /^type=/ {$0="type=1"}
  sec=="[sink0]" && /^sync=/ {$0="sync=" sync}
  sec=="[source0]" && /^num-sources=/ {$0="num-sources=" n}
  sec=="[source1]" && /^enable=/ {$0="enable=0"}
  sec=="[streammux]" && /^batch-size=/ {$0="batch-size=" n}
  sec=="[streammux]" && /^live-source=/ {$0="live-source=" sync}
  sec=="[primary-gie]" && /^batch-size=/ {$0="batch-size=" n}
  sec=="[primary-gie]" && /^model-engine-file=/ {$0="model-engine-file=" eng}
  sec=="[primary-gie]" && /^config-file=/ {$0="config-file=config_infer_bench.txt"}
  sec=="[tests]" && /^file-loop=/ {$0="file-loop=1"}
  {print}' source30_1080p_dec_infer-resnet_tiled_display.txt > bench_app.txt
# build the TensorRT engine for this batch size first (not timed)
[ -f "$E" ] || timeout 900 deepstream-app -c bench_app.txt > /dev/null 2>&1 & 
for i in $(seq 1 180); do [ -f "$E" ] && break; sleep 5; done; pkill -f deepstream-app; sleep 3
cp bench_app.txt $O/config_n${N}_sync${SYNC}.txt
timeout $RUN_S deepstream-app -c bench_app.txt > $O/log_n${N}_sync${SYNC}.txt 2>&1 || true
