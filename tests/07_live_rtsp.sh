#!/usr/bin/env bash
# Live-camera latency: DeepStream reads N live RTSP camera feeds (TCP) from another machine
# (tools/rtsp_cameras.py) and runs NVIDIA's TrafficCamNet detector on every frame. NVIDIA's latency
# measurement reports, per frame, decoder input -> detection done. Add the RTSP jitter buffer
# (LATENCY_MS) and the network one-way time for "frame arrives from the camera -> flagged".
# Usage: CAM_HOST=<ip> bash tests/07_live_rtsp.sh <outdir>
set -euo pipefail
OUT=$1; N=${N:-30}; CAM_HOST=${CAM_HOST:?}; JB=${LATENCY_MS:-100}; RUN_S=${RUN_S:-60}
IMG=${DS_IMAGE:-nvcr.io/nvidia/deepstream:8.0-samples-multiarch}
D="$OUT/live_rtsp"; mkdir -p "$D"
ping -c 50 -i 0.2 -q $CAM_HOST | tail -1 | tee "$D/ping.txt"
cat > "$D/run_live.sh" <<IN
#!/usr/bin/env bash
cd /opt/nvidia/deepstream/deepstream/samples/configs/deepstream-app
E=../../models/Primary_Detector/resnet18_trafficcamnet_pruned.onnx_b${N}_gpu0_fp16.engine
sed -e "s/^batch-size=30/batch-size=${N}/" -e "s#^model-engine-file=.*#model-engine-file=\$E#" config_infer_primary.txt > config_infer_live.txt
awk -v n=${N} -v eng=\$E '
  /^\[/ {sec=\$0; skip=(sec=="[source0]"||sec=="[source1]")}
  skip {next}
  sec=="[tiled-display]" && /^enable=/ {\$0="enable=0"}
  sec=="[osd]" && /^enable=/ {\$0="enable=0"}
  sec=="[sink0]" && /^type=/ {\$0="type=1"}
  sec=="[sink0]" && /^sync=/ {\$0="sync=0"}
  sec=="[streammux]" && /^batch-size=/ {\$0="batch-size=" n}
  sec=="[streammux]" && /^live-source=/ {\$0="live-source=1"}
  sec=="[streammux]" && /^batched-push-timeout=/ {\$0="batched-push-timeout=33333"}
  sec=="[primary-gie]" && /^batch-size=/ {\$0="batch-size=" n}
  sec=="[primary-gie]" && /^model-engine-file=/ {\$0="model-engine-file=" eng}
  sec=="[primary-gie]" && /^config-file=/ {\$0="config-file=config_infer_live.txt"}
  {print}' source30_1080p_dec_infer-resnet_tiled_display.txt > live_app.txt
for k in \$(seq 1 ${N}); do printf "[source%d]\nenable=1\ntype=4\nuri=rtsp://${CAM_HOST}:8554/cam%d\nnum-sources=1\ngpu-id=0\nlatency=${JB}\nselect-rtp-protocol=4\ncudadec-memtype=0\n\n" \$((k-1)) \$k >> live_app.txt; done
cp live_app.txt /out/live_app.txt
timeout ${RUN_S} deepstream-app -c live_app.txt > /out/log_live_n${N}_jb${JB}.txt 2>&1 || true
IN
sudo docker run --rm --gpus all --network host -e NVDS_ENABLE_LATENCY_MEASUREMENT=1 -e NVDS_ENABLE_COMPONENT_LATENCY_MEASUREMENT=1 \
  -v "$D:/out" -v ds_engines:/opt/nvidia/deepstream/deepstream/samples/models/Primary_Detector $IMG bash /out/run_live.sh >/dev/null 2>&1
python3 - "$D/log_live_n${N}_jb${JB}.txt" $N $JB <<'PY' | tee -a "$D/summary.txt"
import re,sys,statistics as st,collections
d=collections.defaultdict(list); fps=[]
for l in open(sys.argv[1]):
    m=re.search(r"Comp name = (\S+).*component latency= ([\d.]+)",l)
    if m: d["decoder" if m.group(1).startswith("nvv4l2decoder") else m.group(1)].append(float(m.group(2)))
    m=re.search(r"Frame latency = ([\d.]+)",l)
    if m: d["frame (decoder in -> detection done)"].append(float(m.group(1)))
    if l.startswith("**PERF:"): fps.append(sum(float(x) for x in re.findall(r"([\d.]+) \(",l)))
print(f"live RTSP: cameras={sys.argv[2]} rtsp_jitter_buffer_ms={sys.argv[3]} total_fps_median={st.median(fps[2:]) if len(fps)>2 else 'n/a'}")
for k,v in d.items():
    v=v[len(v)//10:]; q=st.quantiles(v,n=100)
    print(f"  {k:40} n={len(v):6} median={st.median(v):7.1f} ms p95={q[94]:7.1f} p99={q[98]:7.1f}")
PY
