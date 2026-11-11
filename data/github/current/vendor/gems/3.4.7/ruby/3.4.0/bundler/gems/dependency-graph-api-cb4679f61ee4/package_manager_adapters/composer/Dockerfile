FROM ghcr.io/github/gh-base-image/ruby-builder:v3.3-focal-20251013205304@sha256:59adf8b8b7e7ec4485f3fa45e776c1a79bb6d89347e62664394306edd55a7959

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
COPY tmp/ ./tmp
COPY Rakefile ./

ENTRYPOINT ["./wrapper"]
