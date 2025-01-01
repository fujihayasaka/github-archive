FROM golang:1.23

WORKDIR /go/src/github.com/github/launch

# Squash a warning about world-writable dirs in PATH
RUN chmod o-w /go/bin /go/

RUN rm -rf /go/src/github.com/golang/protobuf
RUN go install github.com/golang/protobuf/protoc-gen-go@v1.5.2

RUN rm -rf /go/src/github.com/twitchtv/twirp
RUN go install github.com/twitchtv/twirp/protoc-gen-twirp@v8.1.0

RUN go install github.com/twitchtv/twirp-ruby/protoc-gen-twirp_ruby@v1.8.0

# Add Ruby for protoc to all target languages:
RUN apt-get update && \
  apt-get install apt-transport-https
RUN apt-get update && \
  apt-get -y install ruby-bundler unzip ruby-dev
RUN curl -sL https://github.com/google/protobuf/releases/download/v3.11.3/protoc-3.11.3-linux-x86_64.zip -o /tmp/protoc.zip
RUN unzip /tmp/protoc.zip -d /tmp/protoc && \
  mv /tmp/protoc/bin/protoc /usr/local/bin/protoc && \
  mv /tmp/protoc/include/google /usr/local/include/


ADD Gemfile .
ADD Gemfile.lock .
ADD github-launch.gemspec .
ADD ruby/lib ruby/lib
RUN gem install bundler:2.1.4
RUN bundle install --quiet

ADD config/tools/protoc/protoc /go/src/github.com/github/launch/protoc

ENTRYPOINT ["/go/src/github.com/github/launch/protoc"]
