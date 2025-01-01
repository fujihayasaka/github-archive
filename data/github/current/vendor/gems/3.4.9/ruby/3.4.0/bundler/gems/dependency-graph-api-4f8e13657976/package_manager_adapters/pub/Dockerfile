# Quick'n'dirty local dev:
# ./package_manager_adapters/script/build pub
# docker run -i -t --rm --entrypoint /bin/bash <DOCKER_IMAGE_SHA>

FROM ghcr.io/github/gh-base-image/ruby-builder:v3.3-focal-20250726230750@sha256:119b46a7530e9a15c0b41dd52c730e92bdf3d90647b2cd713a8d79a63c14ba9d
RUN apt-get update && apt-get install -y --no-install-recommends apt-utils build-essential

ENV APP_PATH /adapter

RUN mkdir -p $APP_PATH

WORKDIR $APP_PATH

COPY Gemfile .
COPY Gemfile.lock .

RUN bundle install

COPY wrapper .
COPY lib/ ./lib
COPY test/ ./test
COPY Rakefile .


ENTRYPOINT ["./wrapper"]
