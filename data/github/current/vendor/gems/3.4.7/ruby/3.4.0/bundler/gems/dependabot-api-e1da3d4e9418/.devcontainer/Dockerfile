# syntax=docker/dockerfile:1
# check=error=true

FROM ghcr.io/github/codespaces-base/codespaces-base:latest

# Copy over a few files we need for the build
COPY .ruby-version /tmp/.ruby-version

# Install core dependencies.
ENV DEBIAN_FRONTEND=noninteractive
RUN <<NUR
    sudo --preserve-env=DEBIAN_FRONTEND apt-get update -qq
    sudo --preserve-env=DEBIAN_FRONTEND apt-get install -y --no-install-recommends \
                 libgmp-dev \
                 libyaml-dev \
                 cmake \
                 pkg-config
    sudo --preserve-env=DEBIAN_FRONTEND apt-get upgrade -y
    sudo --preserve-env=DEBIAN_FRONTEND apt-get clean
NUR

# The codespaces-base image installs rbenv and ruby-build via linuxbrew, but no
# Ruby version.
RUN <<NUR
    RUBY_VERSION=$(cat /tmp/.ruby-version)

    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    eval "$(rbenv init -)"
    brew upgrade ruby-build
    rbenv install --skip-existing $RUBY_VERSION
    rbenv global $RUBY_VERSION
NUR

# Install bundler and any gems for the vscode extensions defined in
# devcontainer.json
RUN <<NUR
    cat <<EOF > ${HOME}/.gemrc
install: --no-document
update: --no-document
:disable_default_gem_server: true
EOF
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    eval "$(rbenv init -)"
    gem update --system
    gem install "bundler:> 2" \
                rubocop \
                ruby-lsp \
                rufo \
                solargraph \
                --no-post-install-message
NUR

# Cleanup our temp file
RUN sudo rm -f /tmp/.ruby-version