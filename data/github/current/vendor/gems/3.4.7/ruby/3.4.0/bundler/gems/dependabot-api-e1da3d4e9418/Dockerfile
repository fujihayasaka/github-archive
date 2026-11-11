FROM ghcr.io/github/gh-base-image/ruby-builder:v3.3-focal-20251009045733 AS builder-base

ARG USERNAME=dependabot
ARG USER_UID=1001
ARG USER_GID=$USER_UID

ENV LD_LIBRARY_PATH=ssl/build/lib

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    # This conditional is necessary because the file will not exist in a Codespace.
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    touch /etc/app-env && \
    apt-get -qq update && \
    apt-get -y --no-install-recommends install \
      cmake \
      default-mysql-client \
      libsodium23 \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

ENV GEM_HOME=/home/${USERNAME}/.local/share/gem/ruby
RUN echo 'gem: --no-document' >> /etc/gemrc && \
    mkdir -p /app/.bundle && \
    chown -R $USER_UID:$USER_UID /app/.bundle && \
    groupadd --gid $USER_GID $USERNAME && \
    useradd --uid $USER_UID --gid $USER_GID -m $USERNAME && \
    echo 'ssl_mode=DISABLED' >> /etc/mysql/conf.d/mysql.cnf

# =============================================================================

FROM builder-base AS builder

ARG USERNAME=dependabot
ARG USER_UID=1001
ARG USER_GID=$USER_UID

WORKDIR /app

COPY --chown=$USER_UID:$USER_GID .ruby-version .ruby-version
COPY --chown=$USER_UID:$USER_GID Gemfile Gemfile
COPY --chown=$USER_UID:$USER_GID Gemfile.lock Gemfile.lock
COPY --chown=$USER_UID:$USER_GID vendor/cache vendor/cache
COPY --chown=$USER_UID:$USER_GID vendor/activejob-scheduled_job vendor/activejob-scheduled_job
COPY --chown=$USER_UID:$USER_GID gen/ruby gen/ruby

RUN bundle install --local --jobs="$(nproc)"

# =============================================================================

FROM ghcr.io/github/gh-base-image/ruby-base:v3.3-focal-20251009045828

ARG USERNAME=dependabot
ARG USER_UID=1001
ARG USER_GID=$USER_UID

LABEL org.opencontainers.image.source=https://github.com/github/dependabot-api

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    # This conditional is necessary because the file will not exist in a Codespace.
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    touch /etc/app-env && \
    apt-get -qq update && \
    apt-get -y --no-install-recommends install \
      curl \
      default-mysql-client \
      git \
      libsodium23 \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

ENV GEM_HOME=/home/${USERNAME}/.local/share/gem/ruby
RUN echo 'gem: --no-document' >> /etc/gemrc && \
    groupadd --gid $USER_GID $USERNAME && \
    useradd --uid $USER_UID --gid $USER_GID -m $USERNAME && \
    echo 'ssl_mode=DISABLED' >> /etc/mysql/conf.d/mysql.cnf && \
    mkdir -p /tmp/bootsnap

COPY --chown=$USER_UID:$USER_GID --from=builder /home/${USERNAME}/.local/share/gem/ruby /home/${USERNAME}/.local/share/gem/ruby
COPY --chown=$USER_UID:$USER_GID . /app

WORKDIR /app

USER $USERNAME

EXPOSE 3000/tcp

CMD ["script/server"]
