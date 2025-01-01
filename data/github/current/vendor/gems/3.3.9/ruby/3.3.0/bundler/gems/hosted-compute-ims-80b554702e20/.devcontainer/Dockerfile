FROM mcr.microsoft.com/vscode/devcontainers/go:1.23-bullseye

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends default-mysql-client 

# Install D2 CLI
RUN curl -fsSL https://d2lang.com/install.sh | sh -s -- --method standalone --version v0.6.7

# Install yq
RUN wget https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# Install skaffold
RUN curl -Lo skaffold "https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64" && install skaffold /usr/local/bin/ && rm -f skaffold

# copy custom welcome message
COPY welcome.txt /usr/local/etc/vscode-dev-containers/first-run-notice.txt
RUN chmod 644 /usr/local/etc/vscode-dev-containers/first-run-notice.txt

# We pre-install some other tools using devcontainers features
# Tools: Docker, minikube, kubectl, skaffold, GitHub CLI and Azure CLI
# Check "features" in devcontainer.json for actual list

# non-root user
USER vscode
