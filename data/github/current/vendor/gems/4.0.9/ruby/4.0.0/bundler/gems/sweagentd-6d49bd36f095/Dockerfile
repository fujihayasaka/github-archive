FROM ghcr.io/github/gh-base-image/gh-builder-noble:20260515-172950-gbb0c5b6a9 AS builder

WORKDIR /app
COPY . .
# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get update && \
    apt-get install -y curl && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
ARG RUSTUP_VERSION=1.28.2
ARG RUSTUP_INIT_SHA256=20a06e644b0d9bd2fbdbfd52d42540bdde820ea7df86e92e533c073da0cdd43c
ENV PATH="/root/.cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -fsSLo /usr/local/bin/rustup-init "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init" && \
    echo "${RUSTUP_INIT_SHA256}  /usr/local/bin/rustup-init" | sha256sum -c - && \
    chmod +x /usr/local/bin/rustup-init && \
    /usr/local/bin/rustup-init -y --profile default --default-toolchain none && \
    rm /usr/local/bin/rustup-init
WORKDIR /app/runtime
RUN npm ci
RUN ls -la /run/secrets/ || echo "No /run/secrets/ directory found"
# Fetch the pre-built Windows runtime napi addon for the current runtime submodule SHA
# and stage it where the runtime's esbuild step (script/action-build below) looks for
# napi addons (script/napi-addons-build-plugin.ts::getAddonSourcePath). This is required
# so the action.tar.gz baked into this image (served by sweagentd's /runtime route in
# staging stamps and Proxima) bundles the Windows variant alongside the Linux one.
# Production downloads its own tarball from github/copilot-developer-action releases,
# which already include the Windows addon, and is unaffected by this step.
# The release is published by the publish-runtime-windows-addon job in moda-ci.yaml.
RUN --mount=type=secret,id=GITHUB_TOKEN \
    set -eu; \
    export GH_TOKEN="$(cat /run/secrets/GITHUB_TOKEN)"; \
    RUNTIME_SHA="$(git -C /app/runtime rev-parse HEAD)"; \
    RELEASE_TAG="runtime-windows-addon-${RUNTIME_SHA}"; \
    if [ -f /app/runtime/src/runtime/package.json ]; then \
      runtime_addon_dir=/app/runtime/src/runtime; \
    else \
      runtime_addon_dir=/app/runtime/src/runtime/runtime; \
    fi; \
    mkdir -p "${runtime_addon_dir}"; \
    gh release download "${RELEASE_TAG}" \
      --repo github/sweagentd \
      --pattern 'runtime.win32-x64-msvc.node' \
      --dir "${runtime_addon_dir}" \
      --clobber
RUN --mount=type=secret,id=EBPF_DOWNLOAD_GITHUB_TOKEN \
    --mount=type=secret,id=BLACKBIRD_DOWNLOAD_GITHUB_TOKEN \
    --mount=type=secret,id=AUTOFIND_DOWNLOAD_GITHUB_TOKEN \
    --mount=type=secret,id=GPGSIGN_DOWNLOAD_GITHUB_TOKEN \
    /app/script/runtime-linux-sysroot-env --shell x64 > /tmp/runtime-sysroot-env && \
    . /tmp/runtime-sysroot-env && \
    EBPF_DOWNLOAD_GITHUB_TOKEN="$(cat /run/secrets/EBPF_DOWNLOAD_GITHUB_TOKEN)" BLACKBIRD_DOWNLOAD_GITHUB_TOKEN="$(cat /run/secrets/BLACKBIRD_DOWNLOAD_GITHUB_TOKEN)" AUTOFIND_DOWNLOAD_GITHUB_TOKEN="$(cat /run/secrets/AUTOFIND_DOWNLOAD_GITHUB_TOKEN)" GPGSIGN_DOWNLOAD_GITHUB_TOKEN="$(cat /run/secrets/GPGSIGN_DOWNLOAD_GITHUB_TOKEN)" script/action-build ./copilot-developer-action-main && \
    EXPECTED_GLIBC_VERSION=2.28 SEARCH_PATH=src/runtime script/linux/verify-glibc-requirements.sh
RUN tar -czf action.tar.gz ./copilot-developer-action-main
WORKDIR /app
RUN make build

FROM ghcr.io/github/gh-base-image/gh-base-noble:20260515-161630-g47be52c8e AS run
COPY --chown=github:github --from=builder /app/runtime/action.tar.gz /app/runtime/
ENV RUNTIME_APP_PATH=/app/runtime/action.tar.gz
COPY --chown=github:github --from=builder /app/bin/ /app/bin/
USER github
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/bin/sweagentd"]
