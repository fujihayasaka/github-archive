FROM node:18-bookworm

RUN apt update && \
    apt -y install unzip

ARG TARGETARCH

# Install protoc
RUN <<EOF
set -e
if [ "$TARGETARCH" = "arm64" ]; then
    PROTOC_ARCH="aarch_64";
else
    PROTOC_ARCH="x86_64";
fi
curl -sL https://github.com/protocolbuffers/protobuf/releases/download/v27.5/protoc-27.5-linux-${PROTOC_ARCH}.zip -o /tmp/protoc.zip
unzip /tmp/protoc.zip -d /tmp/protoc
chmod -R go+rX /tmp/protoc
mv /tmp/protoc/bin/protoc /usr/local/bin/protoc
mv /tmp/protoc/include/google /usr/local/include/
rm -rf /tmp/protoc.zip /tmp/protoc
EOF

# Install protobuf-ts plugin
RUN npm install -g @protobuf-ts/plugin@2.11.1

# Install twirp-ts package which includes the protoc plugin
RUN npm install -g twirp-ts@2.5.0

WORKDIR /workspace

ADD config/tools/generate-typescript/generate /workspace/generate
ADD _template/typescript /workspace/_template/typescript


ENTRYPOINT ["/workspace/generate"]
