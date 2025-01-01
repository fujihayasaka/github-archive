FROM ghcr.io/github/gh-base-image/ruby-builder:v3.3-focal-20250305010020@sha256:cb744b06dffebcaf512abdb890d58501a921bd4671a2c84c1d165ba79ed51794

ENV APP_PATH /adapter

RUN mkdir -p $APP_PATH

WORKDIR $APP_PATH

COPY Gemfile .
COPY Gemfile.lock .

RUN bundle install

COPY wrapper .
COPY lib/ ./lib
COPY test/ ./test
COPY tmp/ ./tmp
COPY Rakefile ./


ENTRYPOINT ["./wrapper"]
