FROM jruby:9.4.10.0@sha256:a5e898ec11bbaa4be98e53b5ebabf8a34712cf189e3b7528dc63e208c1eef798

ENV APP_PATH /adapter
RUN mkdir -p $APP_PATH
WORKDIR $APP_PATH

RUN apt-get update -qq && apt-get install -qq netbase

COPY . ./
RUN default_bundler_version=$(gem list bundler | sed -r 's/.*default: ([^)]+).*/\1/') && \
    gem install bundler:$default_bundler_version ruby-maven:3.3.12 jbundler:0.9.4 warbler:2.0.5
ENV BUNDLE_FROZEN=true
RUN bundle install
RUN jbundle install
RUN lock_jars
RUN warble runnable jar

ENTRYPOINT ["./wrapper"]
