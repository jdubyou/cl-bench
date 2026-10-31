#!/usr/bin/env bash
# NVIDIA DeepStream 8.0 multi-stream benchmark, using NVIDIA's own sample config
# (source30_1080p_dec_infer-resnet_tiled_display.txt) with display and on-screen drawing turned off:
# decode N copies of NVIDIA's 1080p H.264 sample video and run the TrafficCamNet person/vehicle
# detector (FP16, batch = N) on every frame. Total FPS / 30 = how many 1080p30 cameras one GPU carries.
# Then a real-time run (sync=1) with NVIDIA's latency measurement on, for per-frame latency.
# Same script on AWS g6e.xlarge. Needs Docker + NVIDIA Container Toolkit.
set -euo pipefail
OUT=$1; IMG=${DS_IMAGE:-nvcr.io/nvidia/deepstream:8.0-samples-multiarch}; RUN_S=${RUN_S:-90}
mkdir -p "$OUT/deepstream"
cat > "$OUT/deepstream/run_in_container.sh" <<'IN'
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
IN
for N in ${STREAMS-30 60 120}; do
  sudo docker run --rm --gpus all -v "$OUT/deepstream:/out" -v ds_engines:/opt/nvidia/deepstream/deepstream/samples/models/Primary_Detector \
    $IMG bash /out/run_in_container.sh $N 0 $RUN_S >/dev/null 2>&1
  python3 - "$OUT/deepstream/log_n${N}_sync0.txt" $N <<'PY' | tee -a "$OUT/deepstream.log"
import re,sys,statistics as st
rows=[[float(x) for x in re.findall(r"([\d.]+) \(", l)] for l in open(sys.argv[1]) if l.startswith("**PERF:")]
rows=[r for r in rows if r][2:]   # drop the first two 5 s intervals (warm-up)
tot=[sum(r) for r in rows]; n=int(sys.argv[2])
print(f"streams={n} intervals={len(rows)} total_fps={st.median(tot):.0f} per_stream_fps={st.median(tot)/n:.1f} equivalent_1080p30_cameras={st.median(tot)/30:.0f} equivalent_cameras_at_5fps={st.median(tot)/5:.0f}")
PY
done
# Latency: N cameras played at real-time speed (sync=1) with NVIDIA's frame-latency measurement on.
# DeepStream reports, per frame, the time from the decoder receiving it to the end of the pipeline
# (decode + batching + detection).
if [ -n "${LATENCY_STREAMS:-30}" ]; then
  N=${LATENCY_STREAMS:-30}
  sudo docker run --rm --gpus all -e NVDS_ENABLE_LATENCY_MEASUREMENT=1 -v "$OUT/deepstream:/out" \
    -v ds_engines:/opt/nvidia/deepstream/deepstream/samples/models/Primary_Detector \
    $IMG bash /out/run_in_container.sh $N 1 ${LAT_RUN_S:-60} >/dev/null 2>&1
  python3 - "$OUT/deepstream/log_n${N}_sync1.txt" $N <<'PY' | tee -a "$OUT/deepstream.log"
import re,sys,statistics as st
v=[float(m.group(1)) for l in open(sys.argv[1]) if (m:=re.search(r"Frame latency = ([\d.]+)", l))]
v=v[len(v)//10:]   # drop the first 10% (warm-up)
q=st.quantiles(v,n=100)
print(f"latency streams={sys.argv[2]} realtime frames={len(v)} median_ms={st.median(v):.1f} p95_ms={q[94]:.1f} p99_ms={q[98]:.1f} max_ms={max(v):.1f}")
PY
fi
