FROM vllm/vllm-openai:latest

# Pin transformers below 5.15.0: that release enforces strict per-layer config
# access for Gemma 4's mixed attention layout, which crashes vLLM 0.27.x with
# AmbiguousGlobalPerLayerAttributeError on startup (fixed upstream but not yet
# released — see https://github.com/vllm-project/vllm/issues/51744).
RUN pip install --no-cache-dir 'transformers==5.14.1'

COPY start-vllm.sh /start-vllm.sh
RUN chmod +x /start-vllm.sh

EXPOSE 8000

ENTRYPOINT ["/start-vllm.sh"]
