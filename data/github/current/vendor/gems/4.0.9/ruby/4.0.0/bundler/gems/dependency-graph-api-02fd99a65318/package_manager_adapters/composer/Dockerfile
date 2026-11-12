FROM ghcr.io/github/gh-base-image/ruby-builder:v3.3-noble-20260318201530@sha256:9f5b0b1c5ac1ab19bb8322bbda8559f7d725c12e6d4c7d2574316fcab370d103

ENV APP_PATH /adapter

RUN mkdir -p $APP_PATH

WORKDIR $APP_PATH

COPY Gemfile .
COPY Gemfile.lock .
COPY vendor/cache vendor/cache
ENV BUNDLE_FROZEN=true
RUN bundle install --local

COPY wrapper .
COPY lib/ ./lib
COPY test/ ./test
COPY tmp/ ./tmp
COPY Rakefile ./

ENTRYPOINT ["./wrapper"]
