# Quick'n'dirty local dev:
# ./package_manager_adapters/script/build cargo
# docker run -i -t --rm --entrypoint /bin/bash <DOCKER_IMAGE_SHA>

FROM ghcr.io/github/gh-base-image/ruby-builder:v3.3-focal-20250305010020@sha256:cb744b06dffebcaf512abdb890d58501a921bd4671a2c84c1d165ba79ed51794
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
