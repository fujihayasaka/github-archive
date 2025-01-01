FROM ghcr.io/github/gh-base-image/ruby-builder:v3.4-focal@sha256:0ce7a3bf7bfad4d1c2cd766dd5c9f29dde83abc5d685927e0817660791586738 AS base

# We touch app-env to prevent the docker-compose behavior we normally use in local dev
RUN touch /etc/app-env
# Use local caches for vendor gems.
ENV BUNDLE_PATH=/localcache/vendor/gem

ARG node_major_version=20
ARG npm_version=8.7.0
ARG yarn_version=1.22.18

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    # This conditional is necessary because the file will not exist in a Codespace.
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get update

RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get install -y ca-certificates curl gnupg
RUN mkdir -p /etc/apt/keyrings
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
RUN echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$node_major_version.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list

RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
     apt-get update \
     && apt-get -y install \
     libmysqlclient-dev \
     build-essential \
     nodejs \
     netcat \
     libicu-dev \
     mysql-client \
     linux-libc-dev

RUN npm install --global npm@$npm_version
RUN npm install --global yarn@$yarn_version

WORKDIR /app

COPY --chown=github:github . .

RUN git config --global --add safe.directory /app

# The ruby-builder image contains _some_ version of ruby via rbenv, but it might
# not be the one we want. First install ruby-build if it's not already installed.
RUN test -n "$(rbenv commands | grep -e '^install$')" \
    || git clone https://github.com/rbenv/ruby-build.git "$(rbenv root)"/plugins/ruby-build

# Now install the version of ruby specified in .ruby-version and make it the
# default. We also need to install bundler for the new ruby version.
RUN RUBY_VERSION=$(cat .ruby-version) \
    && rbenv install -s $RUBY_VERSION \
    && rbenv global $RUBY_VERSION \
    && gem install bundler

RUN bundle install
RUN yarn install --ignore-engines

RUN chown github:github /app

# We have some tests that use a top level test folder in our image.
RUN mkdir /test
RUN chown github:github /test

RUN bin/rake assets:precompile

FROM base AS production

# Running some of our app as root in the dev stage means the /app/log folder is created with root permissions even though /app was copied with github:github
RUN chown -R github:github /app/log
USER github:github
EXPOSE 3000
CMD "script/server"
