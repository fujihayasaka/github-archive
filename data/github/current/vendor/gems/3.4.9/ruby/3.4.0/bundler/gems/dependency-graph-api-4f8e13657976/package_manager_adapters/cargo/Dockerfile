# Quick'n'dirty local dev:
# ./package_manager_adapters/script/build cargo
# docker run -i -t --rm --entrypoint /bin/bash <DOCKER_IMAGE_SHA>

FROM ghcr.io/github/gh-base-image/ruby-builder:v3.3-focal-20250726230750@sha256:119b46a7530e9a15c0b41dd52c730e92bdf3d90647b2cd713a8d79a63c14ba9d
RUN apt-get update && apt-get install -y --no-install-recommends apt-utils build-essential tar libsqlite3-dev sqlite3 pkg-config

ENV APP_PATH /adapter
ENV TMP_PATH ${APP_PATH}/tmp

RUN mkdir -p $APP_PATH $TMP_PATH

WORKDIR $APP_PATH

COPY Gemfile .
COPY Gemfile.lock .
RUN bundle install

# Fixes Invalid byte sequence in US-ASCII since upgrading to ruby 3.3
ENV RUBYOPT="-KU -E utf-8:utf-8"

COPY wrapper .
COPY lib/ ./lib
COPY test/ ./test
COPY Rakefile .


ENTRYPOINT ["./wrapper"]
