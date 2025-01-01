FROM golang:1.23

WORKDIR /go/src/github.com/skeema/skeema

ENV SKEEMA_DIR=/go/src/github.com/skeema/skeema
# Ensure that this matches the version in the root Dockerfile!
ENV SKEEMA_SHA1=1db5e93748c6c58d8cadad4813195ef5f8b95c7b
RUN git clone -q https://github.com/skeema/skeema $SKEEMA_DIR && \
  git --work-tree $SKEEMA_DIR --git-dir $SKEEMA_DIR/.git checkout -q -f $SKEEMA_SHA1 && \
  go install github.com/skeema/skeema

ENTRYPOINT ["/go/bin/skeema"]
