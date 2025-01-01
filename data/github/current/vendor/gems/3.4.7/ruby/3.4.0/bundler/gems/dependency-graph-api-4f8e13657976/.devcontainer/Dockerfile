# Trying to build this? Run
#  docker build -f .devcontainer/Dockerfile .
# from the dependency-graph-api source folder
FROM mcr.microsoft.com/devcontainers/base:focal

ENV LANG C.UTF-8
ENV DG_DEVCONTAINER true

# - shellcheck used for linting/formatting shell scripts
# - clang-format: Used for formatting protobuf files
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  shellcheck clang-format sudo \
  autoconf bison patch build-essential rustc libssl-dev \
  libyaml-dev libreadline6-dev zlib1g-dev libgmp-dev libncurses5-dev \
  libffi-dev libgdbm6 libgdbm-dev libdb-dev uuid-dev \
  zip unzip git wget curl zsh cmake pkg-config vim libicu-dev mysql-client tmux acl

# Install NodeJS the same way we install it in production
COPY package_manager_adapters/npm/script/install_node_sources_16.x /app/package_manager_adapters/npm/script/install_node_sources_16.x
RUN bash /app/package_manager_adapters/npm/script/install_node_sources_16.x && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install protobuf
ENV PROTOC_VERSION="21.12"
ENV PROTOC_CHECKSUM="3a4c1e5f2516c639d3079b1586e703fc7bcfa2136d58bda24d1d54f949c315e8"
RUN mkdir -p /tmp/protoc && \
    curl -L "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOC_VERSION/protoc-$PROTOC_VERSION-linux-$(uname -m).zip" -o "/tmp/protoc/protoc.zip" && \
    echo "${PROTOC_CHECKSUM}" "/tmp/protoc/protoc.zip" | sha256sum --check --status && \
    unzip "/tmp/protoc/protoc.zip" -d /tmp/protoc && \
    mv /tmp/protoc/bin/protoc /usr/bin/protoc && \
    mv /tmp/protoc/include/google /usr/local/include/google && \
    rm -rf /tmp/protoc

# Install overmind
RUN curl -L https://github.com/DarthSim/overmind/releases/download/v2.4.0/overmind-v2.4.0-linux-amd64.gz > /tmp/overmind.gz \
  && gunzip /tmp/overmind.gz \
  && mv /tmp/overmind /usr/local/bin \
  && chmod +x /usr/local/bin/overmind

# Install our profile
COPY .devcontainer/profile.dependency-graph.sh /etc/profile.dependency-graph.sh
RUN echo "# Source dg-api profile\n. /etc/profile.dependency-graph.sh" | tee -a /etc/bash.bashrc
RUN echo "# Source dg-api profile\n. /etc/profile.dependency-graph.sh" | tee -a /etc/zsh/zshrc

# Build the version of Ruby specified in .ruby-version
COPY .ruby-version /tmp/rubyver

# The vscode user is created by the base image
USER vscode

# Install rbenv and ruby-build, then install the version of ruby specified in .ruby-version
RUN git clone --depth 1 https://github.com/rbenv/rbenv.git "$HOME/.rbenv" && \
    mkdir -p "$HOME/.rbenv/plugins" && \
    git clone --depth 1 https://github.com/rbenv/ruby-build.git "$HOME/.rbenv/plugins/ruby-build" && \
    $HOME/.rbenv/bin/rbenv install --verbose "$(cat /tmp/rubyver)"
