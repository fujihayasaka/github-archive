FROM ruby:3.4

RUN touch /etc/inside-container

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
      golang \
      wget \
      git \
      unzip

ENV PROTOC_VERSION 3.14.0
RUN ARCH=$([ $(uname -m) = 'aarch64' ] && echo 'aarch_64' || echo 'x86_64') && \
    echo "installing protoc ${PROTOC_VERSION} for ${ARCH}" && \
    curl -s -L -o protoc.zip https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOC_VERSION/protoc-$PROTOC_VERSION-linux-${ARCH}.zip && \
    unzip -d /usr/local protoc.zip && \
    chmod -R a+r /usr/local/include/google/protobuf && \
    rm protoc.zip

RUN go install github.com/arthurnn/twirp-ruby/protoc-gen-twirp_ruby@latest

WORKDIR /aqueduct-client-ruby
COPY . /aqueduct-client-ruby
RUN bundle install

CMD ["bash"]
