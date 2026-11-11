FROM ghcr.io/github/gh-base-image/ruby-builder:v3.3-focal-20260128001805@sha256:6c34d009674d90ee8155e5a479956b5131c0326df8057426bd86c462d317b44b

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
