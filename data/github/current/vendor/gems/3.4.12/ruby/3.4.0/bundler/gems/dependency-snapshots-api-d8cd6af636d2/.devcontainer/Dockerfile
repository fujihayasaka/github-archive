# Trying to build this? Run
#  docker build -f .devcontainer/Dockerfile .
# from the dependency-snapshots-api source folder
FROM mcr.microsoft.com/devcontainers/base:focal

ENV LANG C.UTF-8
ENV DS_DEVCONTAINER true

# Install dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  shellcheck clang-format sudo python3 python3-pip \
  zip unzip git wget curl zsh vim mysql-client tmux \
  acl wamerican

# Install pre-commit tool
RUN pip3 install pre-commit

# Install golang
ENV GOLANG_VERSION="1.22.0"
RUN wget "https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz" -O "/tmp/go${GOLANG_VERSION}.linux-amd64.tar.gz" && \
    tar -C /usr/local -xzf "/tmp/go${GOLANG_VERSION}.linux-amd64.tar.gz"

# Install protobuf
ENV PROTOC_VERSION="23.4"
ENV PROTOC_CHECKSUM="0502f286ac9ed860b629a7965a14527b1f2dd131e4283fa23c2d7f184672aa9a"
RUN mkdir -p /tmp/protoc && \
    curl -L "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOC_VERSION/protoc-$PROTOC_VERSION-linux-$(uname -m).zip" -o "/tmp/protoc/protoc.zip" && \
    echo "${PROTOC_CHECKSUM}" "/tmp/protoc/protoc.zip" | sha256sum --check --status && \
    unzip "/tmp/protoc/protoc.zip" -d /tmp/protoc && \
    mv /tmp/protoc/bin/protoc /usr/bin/protoc && \
    mv /tmp/protoc/include/google /usr/local/include/google && \
    rm -rf /tmp/protoc

# Install overmind
ENV OVERMIND_VERSION="2.3.0"
RUN curl -L https://github.com/DarthSim/overmind/releases/download/v${OVERMIND_VERSION}/overmind-v${OVERMIND_VERSION}-linux-amd64.gz > /tmp/overmind.gz \
  && gunzip /tmp/overmind.gz \
  && mv /tmp/overmind /usr/local/bin \
  && chmod +x /usr/local/bin/overmind

# Install our profile
COPY .devcontainer/profile.dependency-snapshots.sh /etc/profile.dependency-snapshots.sh
RUN echo "# Source ds-api profile\n. /etc/profile.dependency-snapshots.sh" | tee -a /etc/bash.bashrc
RUN echo "# Source ds-api profile\n. /etc/profile.dependency-snapshots.sh" | tee -a /etc/zsh/zshrc

# The vscode user is created by the base image
USER vscode
