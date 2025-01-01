ARG VARIANT="3.3.0"
FROM ghcr.io/rails/devcontainer/images/ruby:${VARIANT}

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends default-mysql-client && \
    rm -rf /var/lib/apt/lists/*