#!/usr/bin/env bash
cd /opt/nvidia/deepstream/deepstream/samples/configs/deepstream-app
E=../../models/Primary_Detector/resnet18_trafficcamnet_pruned.onnx_b30_gpu0_fp16.engine
sed -e "s/^batch-size=30/batch-size=30/" -e "s#^model-engine-file=.*#model-engine-file=$E#" config_infer_primary.txt > config_infer_live.txt
awk -v n=30 -v eng=$E '
  /^\[/ {sec=$0; skip=(sec=="[source0]"||sec=="[source1]")}
  skip {next}
  sec=="[tiled-display]" && /^enable=/ {$0="enable=0"}
  sec=="[osd]" && /^enable=/ {$0="enable=0"}
  sec=="[sink0]" && /^type=/ {$0="type=1"}
  sec=="[sink0]" && /^sync=/ {$0="sync=0"}
  sec=="[streammux]" && /^batch-size=/ {$0="batch-size=" n}
  sec=="[streammux]" && /^live-source=/ {$0="live-source=1"}
  sec=="[streammux]" && /^batched-push-timeout=/ {$0="batched-push-timeout=33333"}
  sec=="[primary-gie]" && /^batch-size=/ {$0="batch-size=" n}
  sec=="[primary-gie]" && /^model-engine-file=/ {$0="model-engine-file=" eng}
  sec=="[primary-gie]" && /^config-file=/ {$0="config-file=config_infer_live.txt"}
  {print}' source30_1080p_dec_infer-resnet_tiled_display.txt > live_app.txt
for k in $(seq 1 30); do printf "[source%d]\nenable=1\ntype=4\nuri=rtsp://172.26.8.228:8554/cam%d\nnum-sources=1\ngpu-id=0\nlatency=0\nselect-rtp-protocol=4\ncudadec-memtype=0\n\n" $((k-1)) $k >> live_app.txt; done
cp live_app.txt /out/live_app.txt
timeout 60 deepstream-app -c live_app.txt > /out/log_live_n30_jb0.txt 2>&1 || true
