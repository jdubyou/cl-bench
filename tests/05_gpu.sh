#!/usr/bin/env bash
# GPU: LLM inference with vLLM on one GPU.
#  A) whole GPU: one server, Qwen2.5-7B-Instruct, client concurrency 1 / 16 / 64
#  B) shared GPU: N separate servers ("tenants") on the same GPU, each Qwen2.5-1.5B-Instruct
#     with 1/N of GPU memory, all benchmarked at the same time. N = 1, 2, 4, 7.
# Same script on AWS g6e.xlarge (also 1x NVIDIA L40S).
set -euo pipefail
OUT=$1; VLLM=${VLLM_VERSION:-0.10.2}; V=$HOME/vllm-venv
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv | tee "$OUT/gpu.txt"
nvidia-smi topo -m >> "$OUT/gpu.txt" 2>&1 || true
if ! $V/bin/python -c "import transformers,sys; sys.exit(int(transformers.__version__.split(\".\")[0])>=5)" 2>/dev/null; then
  command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH=$HOME/.local/bin:$PATH
  uv venv -q --clear -p 3.12 $V && uv pip install -q -p $V/bin/python "vllm==$VLLM" "transformers<5"
fi
export PATH=$V/bin:$PATH HF_HOME=${HF_HOME:-$HOME/hf}
serve() { # model port mem_fraction
  vllm serve $1 --port $2 --gpu-memory-utilization $3 --max-model-len 4096 --disable-log-requests > "$OUT/serve_$2.log" 2>&1 &
  echo $!; }
wait_up() { for i in $(seq 1 180); do curl -sf localhost:$1/v1/models >/dev/null && return 0; sleep 5; done; return 1; }
bench() { # model port concurrency prompts tag
  vllm bench serve --backend vllm --model $1 --port $2 --dataset-name random --random-input-len 512 --random-output-len 256 \
    --num-prompts $4 --max-concurrency $3 --seed 42 --save-result --result-dir "$OUT" --result-filename "$5.json" > "$OUT/$5.log" 2>&1
  python3 - "$OUT/$5.json" "$5" <<'PY' | tee -a "$OUT/gpu.log"
import json,sys; r=json.load(open(sys.argv[1]))
print(f"{sys.argv[2]} output_tok_s={r['output_throughput']:.0f} req_s={r['request_throughput']:.2f} ttft_ms_median={r['median_ttft_ms']:.0f} tpot_ms_median={r['median_tpot_ms']:.1f}")
PY
}
if [ -z "${SKIP_WHOLE:-}" ]; then
echo "== A) whole GPU, Qwen/Qwen2.5-7B-Instruct" | tee -a "$OUT/gpu.log"
M=Qwen/Qwen2.5-7B-Instruct; pid=$(serve $M 8000 0.90); wait_up 8000
bench $M 8000 1 32 whole_c1; bench $M 8000 16 256 whole_c16; bench $M 8000 64 512 whole_c64
kill $pid; wait $pid 2>/dev/null || true; sleep 10
fi
echo "== B) shared GPU, N tenants x Qwen/Qwen2.5-1.5B-Instruct, each at concurrency 8" | tee -a "$OUT/gpu.log"
M=Qwen/Qwen2.5-1.5B-Instruct
for N in ${TENANTS:-1 2 4 7}; do
  frac=$(python3 -c "print(round(0.85/$N - 0.005, 3))")  # leaves room for each process's CUDA overhead; pids=()
  for t in $(seq 1 $N); do pids+=($(serve $M $((8100+t)) $frac)); wait_up $((8100+t)); done
  bp=(); for t in $(seq 1 $N); do bench $M $((8100+t)) 8 160 shared_n${N}_t${t} & bp+=($!); done; wait "${bp[@]}"
  for p in "${pids[@]}"; do kill $p; done; sleep 15
done
