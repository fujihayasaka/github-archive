ARG go_version

FROM golang:${go_version}

ARG protobuf_version
ARG protoc_gen_go_version
ARG protoc_gen_twirp_version
ARG protoc_gen_twirp_ruby_version
ARG buf_version

RUN apt-get update && \
    apt-get -y install unzip

RUN curl -sL https://github.com/google/protobuf/releases/download/v${protobuf_version}/protoc-${protobuf_version}-linux-x86_64.zip -o /tmp/protoc.zip && \
    unzip /tmp/protoc.zip -d /tmp/protoc && \
    chmod -R go+rX /tmp/protoc && \
    mv /tmp/protoc/bin/protoc /usr/local/bin/protoc && \
    mv /tmp/protoc/include/google /usr/local/include/ && \
    rm -rf /tmp/protoc.zip /tmp/protoc

ARG node_version
ARG nvm_version
ARG protoc_gen_twirp_ts_version
ARG protoc_gen_protobuf_ts_version

ENV NODE_DIR="/node"
ENV NVM_DIR="/node/nvm"
RUN mkdir -p $NVM_DIR && chmod o+rx $NVM_DIR
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${nvm_version}/install.sh | bash
RUN . "$NVM_DIR/nvm.sh" && \
    nvm install ${node_version} && \
    nvm use ${node_version} && \
    mkdir -p $NODE_DIR && ln -s $NVM_BIN $NODE_DIR
ENV PATH="${NODE_DIR}/bin:${PATH}"
RUN npm i -g @protobuf-ts/plugin@${protoc_gen_protobuf_ts_version} twirp-ts@${protoc_gen_twirp_ts_version}

ENV GO111MODULE=on

# Squash a warning about world-writable dirs in PATH
RUN chmod o-w /go/bin /go/

RUN go install github.com/golang/protobuf/protoc-gen-go@v${protoc_gen_go_version}
RUN go install github.com/twitchtv/twirp/protoc-gen-twirp@v${protoc_gen_twirp_version}
RUN go install github.com/github/twirp-ruby/protoc-gen-twirp_ruby@v${protoc_gen_twirp_ruby_version}
RUN go install github.com/bufbuild/buf/cmd/buf@v${buf_version}

WORKDIR /go/src/github.com/github/actions-proto

ADD buf.yaml /go/src/github.com/github/actions-proto/proto/buf.yaml
ADD buf.gen.go.yaml /go/src/github.com/github/actions-proto/buf.gen.go.yaml
ADD buf.gen.ruby.yaml /go/src/github.com/github/actions-proto/buf.gen.ruby.yaml
ADD buf.gen.ts.yaml /go/src/github.com/github/actions-proto/buf.gen.ts.yaml
ADD buf.work.yaml /go/src/github.com/github/actions-proto/buf.work.yaml

ENTRYPOINT ["/go/bin/buf"]
