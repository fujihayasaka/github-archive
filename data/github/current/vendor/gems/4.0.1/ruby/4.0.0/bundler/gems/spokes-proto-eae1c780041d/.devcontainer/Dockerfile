# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.187.0/containers/codespaces-linux/.devcontainer/base.Dockerfile

FROM mcr.microsoft.com/vscode/devcontainers/universal:1-focal

# ** [Optional] Uncomment this section to install additional packages. **
USER root

# Create a git user so we can more reliably interact with repository data
RUN groupadd --gid 500 -r git && \
    useradd --uid 500   --gid git --no-log-init --create-home -r git && \
    useradd --uid 503 --gid git --no-log-init --create-home -r gitro && \
    chown -R root:root /home/git /home/gitro

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends protobuf-compiler

USER codespace
