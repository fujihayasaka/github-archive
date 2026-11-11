FROM ghcr.io/github/gh-base-image/gh-builder-noble:20250811-230528-ge5515c1aa AS builder

WORKDIR /app
COPY . .
RUN apt-get update && \
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
WORKDIR /app/runtime
RUN npm ci
RUN ls -la /run/secrets/ || echo "No /run/secrets/ directory found"
RUN --mount=type=secret,id=EBPF_DOWNLOAD_GITHUB_TOKEN \
    --mount=type=secret,id=BLACKBIRD_DOWNLOAD_GITHUB_TOKEN \
    --mount=type=secret,id=AUTOFIND_DOWNLOAD_GITHUB_TOKEN \
    EBPF_DOWNLOAD_GITHUB_TOKEN="$(cat /run/secrets/EBPF_DOWNLOAD_GITHUB_TOKEN)" BLACKBIRD_DOWNLOAD_GITHUB_TOKEN="$(cat /run/secrets/BLACKBIRD_DOWNLOAD_GITHUB_TOKEN)" AUTOFIND_DOWNLOAD_GITHUB_TOKEN="$(cat /run/secrets/AUTOFIND_DOWNLOAD_GITHUB_TOKEN)" script/action-build ./copilot-developer-action-main
RUN tar -czf action.tar.gz ./copilot-developer-action-main
WORKDIR /app
RUN make build

FROM ghcr.io/github/gh-base-image/gh-base-noble:20250805-204228-g50c20871f AS run
COPY --chown=github:github --from=builder /app/runtime/action.tar.gz /app/runtime/
ENV RUNTIME_APP_PATH=/app/runtime/action.tar.gz
COPY --chown=github:github --from=builder /app/bin/ /app/bin/
USER github
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/bin/sweagentd"]
