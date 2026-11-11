# uv: pinned external image as named stage for Dependabot tracking
FROM ghcr.io/astral-sh/uv:0.11.16@sha256:440fd6477af86a2f1b38080c539f1672cd22acb1b1a47e321dba5158ab08864d AS uv

# Node.js 24 (LTS): pinned external image as named stage for Dependabot tracking
FROM node:26-slim@sha256:1e738cb88890a15c71880323fbc35a739b7bbc703d72e8bfd1613128f8182f78 AS node

# Go: pinned external image as named stage for Dependabot tracking.
# We deliberately install Go via this multi-stage copy instead of the
# `ghcr.io/devcontainers/features/go` feature: that feature unconditionally
# compiles ~9 IDE/debugger tools (gopls, dlv, gomodifytags, etc.) from
# source, which exhausts disk on hosted runners and adds tools we don't
# need in a sandbox image.
FROM golang:1.25-bookworm@sha256:154bd7001b6eb339e88c964442c0ad6ed5e53f09844cc818a41ce4ecb3ce3b43 AS golang

FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Development tools
    curl \
    wget \
    git \
    vim \
    jq \
    ripgrep \
    fd-find \
    # Archive tooling
    unzip \
    zip \
    xz-utils \
    # File sync / remote
    rsync \
    openssh-client \
    gnupg \
    # Process monitoring
    procps \
    htop \
    btop \
    # Terminal multiplexer
    tmux \
    # Python (required by the python devcontainer feature with
    # version: os-provided; otherwise it compiles CPython from source,
    # which uses ~3 GB of intermediate-layer disk during the build)
    python3 \
    python3-pip \
    # Native build toolchain (needed by many npm/pip native modules)
    build-essential \
    pkg-config \
    libssl-dev \
    libffi-dev \
    zlib1g-dev \
    # CA certificates for HTTPS
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install uv from official image (pinned version, tracked by Dependabot)
COPY --from=uv /uv /uvx /usr/local/bin/

# Install Node.js from official pinned image (no remote script execution)
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
# Link npm/npx to the copied node_modules (the node image uses symlinks which
# get overwritten by the base devcontainer's stale npm binary).
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Install Go from official pinned image (no remote script execution, no
# extra IDE tools). See the `golang` build stage above for rationale.
COPY --from=golang /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"

# Create default working directory for projects
RUN mkdir -p /workspaces && chmod 777 /workspaces

# Set working directory
WORKDIR /workspaces

CMD ["/bin/bash"]
