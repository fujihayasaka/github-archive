# Quick'n'dirty local dev:
# ./package_manager_adapters/script/build pub
# docker run -i -t --rm --entrypoint /bin/bash <DOCKER_IMAGE_SHA>

FROM ghcr.io/github/gh-base-image/ruby-builder:v3.3-focal-20251013205304@sha256:59adf8b8b7e7ec4485f3fa45e776c1a79bb6d89347e62664394306edd55a7959
RUN apt-get update && apt-get install -y --no-install-recommends apt-utils build-essential

ENV APP_PATH /adapter

RUN mkdir -p $APP_PATH

WORKDIR $APP_PATH

COPY Gemfile .
COPY Gemfile.lock .
COPY vendor/cache vendor/cache
RUN bundle install --local

COPY wrapper .
COPY lib/ ./lib
COPY test/ ./test
COPY Rakefile .

ENTRYPOINT ["./wrapper"]
