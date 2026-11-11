# syntax=docker/dockerfile:1.2
# Dockerfile for DG API Rails app. Run:
#
#   $ docker build .
#
# This step is usually run by the "GitHub CI / dependency-graph-api-docker-image"
# hook in response to a PR push. It is required by the DG moda configuration:
# See https://github.com/github/dependency-graph-api/blob/master/config/moda/deployment.yaml#L35

################################################################################
# Build helper Go programs (gopma, page_fetch, gomod2json, mysql-lock)
################################################################################
FROM ghcr.io/github/gh-base-image/go-builder-noble:20260415-201534-g088085f4b@sha256:2d4aa289dd6ffc83034f48c2650e80598b5a5664ef14df0b78c5325c2710ad20 AS GoHelpers

WORKDIR /gohelpers

COPY go/ go/
COPY script/configure-goproxy go/

ENV GOPROXY="https://goproxy.githubapp.com/mod,https://proxy.golang.org,direct"
ENV GOPRIVATE=
ENV GONOPROXY=
ENV GONOSUMDB=github.com/github/*

RUN --mount=type=secret,id=netrc,dst=/root/.netrc \
    cd go && \
    ./configure-goproxy && \
    go build -o /gohelpers \
       ./ecosystem/go/gomod2json \
       ./ecosystem/go/gopma \
       ./ecosystem/go/gooneoff \
       ./ecosystem/nuget/page_fetch \
       ./backfill \
       ./mysql-lock

################################################################################
# Build maven package manager adapter jar
################################################################################
FROM jruby:9.4.10.0@sha256:a5e898ec11bbaa4be98e53b5ebabf8a34712cf189e3b7528dc63e208c1eef798 AS MavenPackageManagerAdapterBuilder

ENV APP_PATH /maven_adapter
RUN mkdir -p $APP_PATH
WORKDIR $APP_PATH

COPY package_manager_adapters/maven ./

RUN apt-get update -qq && apt-get install -y netbase

# We need to reinstall the version of bundler that comes with ruby (labeled
# "default" in gem output), because it is missing the gemspec file, which
# warbler requires to build a jar
RUN default_bundler_version=$(gem list bundler | sed -r 's/.*default: ([^)]+).*/\1/') && \
    gem install bundler:$default_bundler_version ruby-maven:3.3.12 jbundler:0.9.4 warbler:2.0.5
ENV BUNDLE_FROZEN=true
RUN bundle install --without development test
RUN jbundle install --without development test
RUN lock_jars
RUN warble runnable jar

###############################################################
# BUILD COMMON
###############################################################
FROM ghcr.io/github/gh-base-image/ruby-builder:v3.3-noble-20260318201530@sha256:9f5b0b1c5ac1ab19bb8322bbda8559f7d725c12e6d4c7d2574316fcab370d103 AS build-common

ENV LANG C.UTF-8
ENV TREE_SITTER_PARSER_DIR=/src/app/parsers

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

# Install common build dependencies
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get update -qq && apt-get install -qq \
        cmake \
        libicu-dev \
        liblzma-dev \
        libpq-dev \
        pkg-config

# Copy the application over and set our WORKDIR so all RUN/COPY commands will be relative to /src/app
COPY . /src/app/
RUN rm -f go/.goproxytoken
WORKDIR /src/app

# Install our version of Node
COPY package_manager_adapters/npm/script/install_node_sources_20.x /app/package_manager_adapters/npm/script/install_node_sources_20.x
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    bash /app/package_manager_adapters/npm/script/install_node_sources_20.x
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get install -y nodejs

# Bootstrap the dependency-graph-api Rails application
ENV BUNDLE_FROZEN=true
RUN bundle config set without "development test" && \
    bundle config set path vendor/gems && \
    MAKE="make --jobs 4" bundle install --local

RUN npm ci --quiet

##############################################################
# BUILD MODA
###############################################################
FROM build-common AS build-moda

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get install -y \
    libsqlite3-dev \
    libxml2-dev \
    libxslt1-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-wheel

# PMA bundles
RUN cd package_manager_adapters/cargo && \
    bundle config set without "development test" && \
    bundle config set path vendor/gems && \
    bundle install --local
RUN cd package_manager_adapters/composer && \
    bundle config set without "development test" && \
    bundle config set path vendor/gems && \
    bundle install --local
RUN cd package_manager_adapters/nuget && \
    bundle config set without "development test" && \
    bundle config set path vendor/gems && \
    bundle install --local
RUN cd package_manager_adapters/pub && \
    bundle config set without "development test" && \
    bundle config set path vendor/gems && \
    bundle install --local

# cleanup PMA gem caches after gems are installed
RUN rm -rf package_manager_adapters/cargo/vendor/cache && \
    rm -rf package_manager_adapters/composer/vendor/cache && \
    rm -rf package_manager_adapters/nuget/vendor/cache && \
    rm -rf package_manager_adapters/pub/vendor/cache

# PMA bundles (outdated)
RUN cd package_manager_adapters/rubygems && bundle install --without development test --path /src/app/vendor/gems

# Install dependencies for the NPM Package Manager Adapter
RUN cd package_manager_adapters/npm && npm ci --omit=dev

# Python PMA packages
RUN cd package_manager_adapters/pypi && pip3 install --require-hashes --target packages -r requirements.txt
RUN mkdir package_manager_adapters/pypi/data

RUN rm -rf go && \
    rm -rf vendor/cache vendor/gems/ruby/*/cache && \
    find vendor/gems/ruby/*/gems/ -name "*.[choa]" -delete && \
    find vendor/gems/ruby/*/gems/ -name "*.cc" -delete

##############################################################
# RUN COMMON. Common setup for production images
###############################################################
FROM ghcr.io/github/gh-base-image/ruby-base:v3.3-noble-20260324003935@sha256:b5642cc3b43fd9dc3cecce7bfe29e151e42a8b0752d9308e1e3fee123a9ce6d1 AS run-common
# import shared variables
ARG RAILS_ENV_VALUE=production

ENV LANG C.UTF-8
ENV RAILS_ENV=${RAILS_ENV_VALUE}

# Shared user and group for Moda and GHES/GHPI run images.
# Statically defined user ID for dependency-graph-api created in enterprise2/chroot-prepare-base.sh
RUN groupadd --gid 621 dependency-graph-api && \
    useradd --uid 621 --gid 621 --create-home --shell /bin/bash dependency-graph-api

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get update -qq && apt-get install -y \
        libicu74 \
        default-mysql-client \
        patch \
        curl \
        libjemalloc2 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/share/rbenv/shims:${PATH}"

# Install our version of Node
COPY package_manager_adapters/npm/script/install_node_sources_20.x /app/package_manager_adapters/npm/script/install_node_sources_20.x
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    bash /app/package_manager_adapters/npm/script/install_node_sources_20.x
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

################################################################################
# Begin base image for moda deployment
################################################################################
FROM run-common AS run-moda

################################################################################
# Begin Maven Package Manager Adapter
################################################################################
# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

# Install JRE
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get update -qq && apt-get install -qq \
    openjdk-21-jre \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Fix java certificates
# In moda /etc/ssl/certs gets overridden by the host, but the host doesn't have
# the java cacerts. Since java actually looks in $JAVA_HOME and follows a
# symlink there, we just replace the symlink with the actual file.
RUN rm /usr/lib/jvm/java-21-openjdk-amd64/lib/security/cacerts && \
    cp /etc/ssl/certs/java/cacerts /usr/lib/jvm/java-21-openjdk-amd64/lib/security/cacerts

# Postgresql client for rubygems PMA
# We can no longer pin to postgresql 15 because PostgreSQL's own apt repo dropped focal support
# The standard postgresql-client version in focal is 12, which might be too old for rubygems PMA... to be tested.
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get update && apt-get install -y postgresql-client

# Link rbspy into /usr/local/bin for convenience
RUN ln -s /src/app/bin/tools/linux/rbspy/rbspy-x86_64-unknown-linux-musl /usr/local/bin/rbspy

COPY --chown=dependency-graph-api:dependency-graph-api --from=build-moda /src/app /src/app
WORKDIR /src/app

# Copy compiled adapter jar into workdir
COPY --chown=dependency-graph-api:dependency-graph-api --from=MavenPackageManagerAdapterBuilder /maven_adapter/maven_adapter.jar ./package_manager_adapters/maven/adapter.jar

# copy compiled page_fetch binary for nuget
COPY --chown=dependency-graph-api:dependency-graph-api --from=GoHelpers /gohelpers/page_fetch ./package_manager_adapters/nuget/page_fetch

# Get go{mod2{json,nwo},oneoff} helpers.
COPY --chown=dependency-graph-api:dependency-graph-api --from=GoHelpers /gohelpers/gomod2json /gohelpers/gooneoff ./

# Copy backfill tool
COPY --chown=dependency-graph-api:dependency-graph-api --from=GoHelpers /gohelpers/backfill ./

# Get gopma executable, which package_manager_adapters/go/wrapper expects to find in its directory.
COPY --chown=dependency-graph-api:dependency-graph-api --from=GoHelpers /gohelpers/gopma package_manager_adapters/go/

# Get mysql-lock executable, which package_manager_adapters/script/start_kube expects
# to find in its directory.
COPY --chown=dependency-graph-api:dependency-graph-api --from=GoHelpers /gohelpers/mysql-lock ./

################################################################################
# Begin Rust/Cargo PMA
################################################################################
RUN mkdir -p /src/app/tmp && chown -R dependency-graph-api:dependency-graph-api /src/app/tmp

USER dependency-graph-api

RUN bundle exec bootsnap precompile app lib script proto

################################################################################
# Don't let anything happen unless they override the entrypoint
CMD ["echo", "FATAL: no command entrypoint provided in deployment YAML for this subproject + env, please fix and redeploy"]


###############################################################
# BUILD ENTERPRISE
###############################################################
FROM build-common AS build-enterprise

COPY config/enterprise/database.yml /src/app/config/database.yml

# We can't have a separate dockerignore file for enterprise, so remove files
# here before /src/app is copied into the runtime image
RUN rm -rf \
    .github \
    docs \
    config/dev \
    config/dogstatsd.yaml \
    config/secrets.yaml \
    config/environments/development.rb \
    config/environments/test.rb \
    config/terraform/* \
    ownership.yaml \
    hooks \
    script/one_off \
    script/cibuild* \
    script/clearly_defined \
    script/dev \
    Brewfile \
    Procfile \
    parsers

RUN find . \( \
    -name Makefile -or \
    -name mkmf.log -or \
    -name CMakeError.log -or \
    -name config.status -or \
    -name gem_make.out -or \
    -name '*.md' \
    \) -delete

RUN rm -rf go && \
    rm -rf vendor/cache vendor/gems/ruby/*/cache && \
    find vendor/gems/ruby/*/gems/ -name "*.[choa]" -delete && \
    find vendor/gems/ruby/*/gems/ -name "*.cc" -delete

RUN find package_manager_adapters -type d -name test -exec rm -rf {} +

# Obfuscate Ruby source code because it's being sent to customers as part of GHES
RUN find . -iname '*.rb' -print0 | xargs -0 "ruby" "/bin/tools/ruby-concealer.rb" 2>&1 | awk '!/already concealed/'

###############################################################
# RUN ENTERPRISE. Use base image for main app
###############################################################
FROM run-common AS run-enterprise

LABEL ghes.licenses.path=/src/app/.licenses
LABEL org.opencontainers.image.source=https://github.com/github/dependency-graph-api

# Copy built files but they will be owned by DG API as opposed to ROOT
COPY --chown=dependency-graph-api:dependency-graph-api --from=build-enterprise /src/app /src/app

# Copy Go support binaries and related tooling
COPY --chown=dependency-graph-api:dependency-graph-api --from=GoHelpers /gohelpers/gomod2json /src/app

WORKDIR /src/app

RUN rm -rf tmp && mkdir -p tmp/pids && mkdir -p tmp/cache && chown -R dependency-graph-api:dependency-graph-api tmp
RUN touch log/production.log && chown -R dependency-graph-api:dependency-graph-api log

USER dependency-graph-api

EXPOSE 9596

CMD ["script/ghex-server"]

FROM build-common AS build-test

RUN bundle config set --local without development && \
    bundle config set --local with test && \
    bundle config set path vendor/gems && \
    MAKE="make --jobs 4" bundle install --local

FROM run-moda AS test-moda

COPY --chown=dependency-graph-api:dependency-graph-api --from=build-test /src/app/vendor/gems /src/app/vendor/gems

RUN bundle config set --local without development
RUN bundle config set --local with test

# Run setup-and-test, which will prep our test DB and run rspec.
CMD ["script/setup-and-test"]

# Set the default target
FROM run-moda
