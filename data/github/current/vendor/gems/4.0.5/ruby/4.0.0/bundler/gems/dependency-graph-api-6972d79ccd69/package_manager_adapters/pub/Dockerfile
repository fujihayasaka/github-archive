# Quick'n'dirty local dev:
# ./package_manager_adapters/script/build pub
# docker run -i -t --rm --entrypoint /bin/bash <DOCKER_IMAGE_SHA>

FROM ghcr.io/github/gh-base-image/ruby-builder:v3.3-focal-20260128001805@sha256:6c34d009674d90ee8155e5a479956b5131c0326df8057426bd86c462d317b44b
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
