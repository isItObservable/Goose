# syntax=docker/dockerfile:1
# ─────────────────────────────────────────────────────────────────────────────
# Goosetown image — goose (agent engine) + goosetown (multi-agent orchestration
# + real-time "geese on a map" dashboard) + the isItObservable recipes & BMAD
# crew roles.
#
# Built from the validated goose v1.52.0 binary (ghcr.io/aaif-goose/goose:latest,
# the only image with working native OTel — see docs/observability.md) plus the
# goosetown framework pinned to a known commit.
# ─────────────────────────────────────────────────────────────────────────────

# --- Stage 1: pull the validated goose binary --------------------------------
FROM ghcr.io/aaif-goose/goose:latest AS goose-bin

# --- Stage 2: goosetown runtime ----------------------------------------------
# Pin to Debian bookworm (glibc 2.36) to match the goose image's base and avoid
# any ABI surprises with the copied Rust binary.
FROM python:3.11-slim-bookworm

# goose CLI (native OTel, verified on v1.52.0)
COPY --from=goose-bin /usr/local/bin/goose /usr/local/bin/goose

# Runtime deps: curl (Ollama reachability), sqlite3 (goose sessions DB read by the
# dashboard), procps/screen (dashboard launcher), git (build-time goosetown clone).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl sqlite3 procps screen git \
    && rm -rf /var/lib/apt/lists/*

# goosetown Python deps (matches goosetown/pyproject.toml)
RUN pip install --no-cache-dir \
        "starlette>=0.40,<1.0" \
        "uvicorn[standard]>=0.30,<1.0" \
        "pyyaml>=6.0"

# goosetown framework — pinned commit for reproducibility.
ARG GOOSETOWN_REF=d1f62b0bce24ad0ec74bae51044378c4fed40600
RUN git clone --depth 1 https://github.com/aaif-goose/goosetown.git /opt/goosetown \
    && git -C /opt/goosetown checkout ${GOOSETOWN_REF} 2>/dev/null || true \
    && rm -rf /opt/goosetown/.git

# Make goosetown's helpers available on PATH.
ENV PATH="/opt/goosetown:/opt/goosetown/scripts:${PATH}"

# isItObservable recipes (our "recipe") + BMAD crew roles (our "agents").
COPY recipes/ /recipes/
COPY config/goosetown/ /opt/goosetown/config/

# Non-root runtime user (mirrors the goose image's uid 1000).
RUN useradd -m -u 1000 -s /bin/bash goose \
    && mkdir -p /home/goose/.config/goose /home/goose/.goosetown/walls /home/goose/.local/share/goose \
    && chown -R goose:goose /home/goose /recipes /opt/goosetown/config
USER goose

# Defaults — overridable at run/deploy time via env.
ENV GOOSE_PROVIDER=ollama \
    GOOSE_MODEL=qwen3.6 \
    OLLAMA_HOST=http://10.0.0.185:11434 \
    GOOSETOWN_BIND_HOST=0.0.0.0

# Native OTel is wired in the k8s manifest via OTEL_* env vars (HTTP/4318).

EXPOSE 4242

# Default: the real-time goosetown dashboard. Launch the orchestrator with:
#   kubectl exec -it <pod> -- goose session      (interactive, loads recipes/ + config/goosetown/)
# or headless: goose run --recipe /recipes/04-bmad-crew.yaml --params goal="..."
CMD ["python3", "/opt/goosetown/scripts/goosetown-ui", "--host", "0.0.0.0", "--port", "4242"]
