FROM jruby:9.4.10.0

ENV APP_PATH /adapter
RUN mkdir -p $APP_PATH
WORKDIR $APP_PATH

RUN apt-get update -qq && apt-get install -qq netbase

COPY . ./
RUN default_bundler_version=$(gem list bundler | sed -r 's/.*default: ([^)]+).*/\1/') && \
    gem install bundler:$default_bundler_version ruby-maven:3.3.12 jbundler:0.9.4 warbler:2.0.5
RUN bundle install
RUN jbundle install
RUN lock_jars
RUN warble runnable jar

ENTRYPOINT ["./wrapper"]
