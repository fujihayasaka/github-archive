FROM ruby:3.4

RUN touch /etc/inside-container

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip

ENV PROTOC_VERSION 3.14.0
RUN ARCH=$([ $(uname -m) = 'aarch64' ] && echo 'aarch_64' || echo 'x86_64') && \
    echo "installing protoc ${PROTOC_VERSION} for ${ARCH}" && \
    curl -s -L -o protoc.zip https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOC_VERSION/protoc-$PROTOC_VERSION-linux-${ARCH}.zip && \
    unzip -d /usr/local protoc.zip && \
    chmod -R a+r /usr/local/include/google/protobuf && \
    rm protoc.zip

RUN mkdir hydro-client-ruby
WORKDIR /hydro-client-ruby

COPY lib/hydro/version.rb ./lib/hydro/version.rb
COPY Gemfile hydro-client.gemspec ./
RUN bundle install

COPY . .

CMD ["bash"]
