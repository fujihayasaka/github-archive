FROM mcr.microsoft.com/vscode/devcontainers/ruby:3

COPY welcome-message.txt /usr/local/etc/vscode-dev-containers/first-run-notice.txt

RUN apt-get -y update

USER vscode

# Setup Homebrew
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/5e7f30635a945f475a557240f006973c81c71324/install.sh)" && \
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "${HOME}/.bashrc" && \
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
    brew install gcc