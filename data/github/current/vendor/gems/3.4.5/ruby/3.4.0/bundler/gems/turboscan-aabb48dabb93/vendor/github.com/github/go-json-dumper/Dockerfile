FROM golang

COPY ./ /go/src/github.com/github/go-json-dumper

WORKDIR /go/src/github.com/github/go-json-dumper

RUN go install github.com/github/go-json-dumper/cmd/...

CMD [ "make", "test-conversion" ]
