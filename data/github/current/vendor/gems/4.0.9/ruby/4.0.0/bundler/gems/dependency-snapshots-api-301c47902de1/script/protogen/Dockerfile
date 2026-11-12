FROM bufbuild/buf@sha256:8237e37d15d73e9d3a536332d352c6a4fae2d37ed041cf17a5066ffa4403ea40

# Install go
RUN apk add --no-cache go

# Add Go binaries to PATH
ENV GOPATH=/go
ENV PATH=$PATH:$GOPATH/bin

# Installing twirp plugins since they are not included in the buf remote registry.
RUN go install github.com/twitchtv/twirp/protoc-gen-twirp@v8.1.3
RUN go install github.com/arthurnn/twirp-ruby/protoc-gen-twirp_ruby@v1.11.0

# Create cache directory with write permissions for non-root users
RUN mkdir -p /tmp/cache && chmod 777 /tmp/cache
ENV HOME=/tmp/cache

# Set working directory.
WORKDIR /proto
