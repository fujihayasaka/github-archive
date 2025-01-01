# syntax = docker/dockerfile:1.3-labs

FROM ubuntu:jammy@sha256:6042500cf4b44023ea1894effe7890666b0c5c7871ed83a97c36c76ae560bb9b AS deb

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt <<END bash
  set -euo pipefail
  # do not remove downloaded packages after install as we will be using a cache mount
  rm -f /etc/apt/apt.conf.d/docker-clean
  apt-get -y update

  DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
    bundler \
    curl \
    gcc \
    git \
    jq \
    less \
    libc6-dev \
    make \
    nano \
    netcat \
    openssh-client \
    ruby \
    ruby-dev \
    unzip

  rm -rf /var/lib/apt/lists/*
END

FROM deb AS ruby

# Update Bundler
ARG BUNDLER_VERSION=2.3.22
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt <<END bash
  set -euo pipefail
  # do not remove downloaded packages after install as we will be using a cache mount
  rm -f /etc/apt/apt.conf.d/docker-clean
  apt-get -y update
  DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install cmake pkg-config libssl-dev
  gem install bundler -v ${BUNDLER_VERSION}
END

FROM deb AS base

WORKDIR /tmp

LABEL org.opencontainers.image.source=https://github.com/github/turboscan/

ENV LANG=C.UTF-8

# https://github.com/microsoft/vscode-dev-containers/commits/main
ARG MS_SCRIPT_LIBRARY_SHA=d8cdfa2651be9fba89a5ecd8ee5e012dea8f52af

ENV GOBIN=/bin GO111MODULE="on" PATH=/usr/local/go/bin/:$PATH

COPY .go-version .devcontainer/downloads.rb ./

RUN --mount=type=cache,target=/var/cache/downloads ./downloads.rb

RUN <<END bash
  set -euo pipefail
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  apt-get update
  apt-get install gh
END

COPY --from=ruby /var/lib/gems /var/lib/gems

ENV PATH="/cocofix/node_modules/.bin/:$PATH"
# Install cocofix
COPY /ts/cocofix/javascript/ /cocofix/
RUN --mount=type=secret,id=GH_TOKEN \
    cd /cocofix/ && \
    NODE_ENV=production GITHUB_TOKEN="$(cat /run/secrets/GH_TOKEN)" npm install && \
    cocofix --version

# For Linux users, these should be set to the values on the host so
# that any created files have the right ownership and permissions.
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN <<END  bash
  set -euo pipefail
  groupadd --gid $USER_GID devuser
  useradd -s /bin/bash --uid $USER_UID --gid $USER_GID -m devuser
  mkdir -p /home/devuser/.config/
  chown --recursive devuser:devuser /home/devuser/.config/
  chmod 700 /home/devuser/.config/
END

RUN <<END bash
  set -euo pipefail
  mkdir /commandhistory
  chown -R devuser /commandhistory
  echo "export PROMPT_COMMAND='history -a'" >> /home/devuser/.bashrc
  echo "export HISTFILE=/commandhistory/.bash_history" >> /home/devuser/.bashrc
END

FROM base as dev-run

# Force pulling Go modules over SSH.
RUN git config --system url."git@github.com:".insteadOf "https://github.com/"

USER devuser

ENV IN_TURBOSCAN_DEVCONTAINER=true \
  GOBIN=/home/devuser/bin \
  PATH=/home/devuser/bin:$PATH \
  GITHUB_TELEMETRY_LOGS_CONSOLE_ENCODING=console \
  GITHUB_TELEMETRY_LOGS_INCLUDE_RESOURCE_ATTRIBUTES='' \
  GITHUB_TELEMETRY_LOGS_PRECISION=second

FROM base as codespace

COPY .devcontainer/welcome-message.txt /usr/local/etc/vscode-dev-containers/first-run-notice.txt
ADD https://raw.githubusercontent.com/microsoft/vscode-dev-containers/${MS_SCRIPT_LIBRARY_SHA}/script-library/sshd-debian.sh /tmp/library-scripts/
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt <<END bash
  set -euo pipefail
  groupadd --system --force ssh
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt install -y sudo nodejs ripgrep
  bash /tmp/library-scripts/sshd-debian.sh 22 devuser
  echo 'devuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
  chown devuser /bin
  mkdir -p /home/devuser/.ssh/
  touch /home/devuser/.ssh/authorized_keys
  chown --recursive devuser:devuser /home/devuser/.ssh
  chmod 700 /home/devuser/.ssh
  chmod 600 /home/devuser/.ssh/authorized_keys
END

USER devuser

ENV IN_TURBOSCAN_CODESPACE=true \
  IN_TURBOSCAN_DEVCONTAINER=true \
  DOCKER_BUILDKIT=1 \
  GOBIN=/home/devuser/bin \
  PATH=/home/devuser/bin:$PATH \
  GOPROXY="https://goproxy.githubapp.com/mod,https://proxy.golang.org,direct" \
  GONOSUMDB="github.com/github/*"

RUN <<END bash
  set -euo pipefail
  unset GOPROXY
  go install github.com/lukehoban/go-outline@latest
  go install github.com/cweill/gotests/...@latest
  go install github.com/fatih/gomodifytags@latest
  go install github.com/josharian/impl@latest
  go install github.com/go-delve/delve/cmd/dlv@latest
  go install honnef.co/go/tools/cmd/staticcheck@latest
  go install golang.org/x/tools/gopls@latest
  go install github.com/cespare/reflex@latest
END

CMD ["sleep", "infinity"]
