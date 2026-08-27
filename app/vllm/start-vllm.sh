#!/bin/bash
set -e

: "${MODEL_ID:?MODEL_ID environment variable is required (e.g. google/gemma-4n-e4b-it)}"

# The name clients send in the "model" field of OpenAI-compatible requests.
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-$MODEL_ID}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-32768}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.90}"

echo "=== Starting vLLM OpenAI-compatible server ==="
echo "Model:               $MODEL_ID"
echo "Served model name:   $SERVED_MODEL_NAME"
echo "Max model length:    $MAX_MODEL_LEN"
echo "GPU memory util.:    $GPU_MEMORY_UTILIZATION"

# vLLM handles concurrent requests natively via continuous batching, so unlike
# Ollama there is no need to pre-pull or retry-loop; huggingface_hub downloads
# and caches the weights on first load, then vllm serve blocks in the foreground.
exec vllm serve "$MODEL_ID" \
    --served-model-name "$SERVED_MODEL_NAME" \
    --host 0.0.0.0 \
    --port 8000 \
    --max-model-len "$MAX_MODEL_LEN" \
    --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
    ${EXTRA_ARGS:-}
