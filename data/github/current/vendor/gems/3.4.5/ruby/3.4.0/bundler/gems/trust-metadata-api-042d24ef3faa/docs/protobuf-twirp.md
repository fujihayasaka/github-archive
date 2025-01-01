# Protobuf and Twirp

## Protobuf

[Protobuf](https://protobuf.dev/) is a language-neutral, platform-neutral, extensible way of serializing structured data for use in rpc connections. The TMA uses protobuf to define the data structures that are passed between services. The protobuf files are kept in the [`rpc`](./rpc/) directory. These are used to generate the Go code that defines the Twirp API.

We keep copies of the Sigstore protobuf files found [here](https://github.com/sigstore/protobuf-specs) so that the TMA protobuf file can reference the types in the Sigstore protobuf files. This is done in [`rpc/tma/v0/service.proto`](../rpc/tma/v0/service.proto). TMA actually imports the sigstore protos during compile time from the `github.com/sigstore/protobuf-specs` package. The protobuf files in `rpc` are also used to generate the Ruby client for the TMA.

## Updating

To update the Sigstore protobuf files:

- Edit the `PROTO_SOURCE_REF` in `Makefile` by updating the commit hash to the latest commit in the [Sigstore protobuf-specs](https://github.com/sigstore/protobuf-specs)
- Run `make update-proto-files`
- Then run `make generate-twirp`
- If there are any changes to the Sigstore protobuf files, you may also need to update the Ruby client. See the `ruby` directory for more information
- Create a PR with the changes

## Twirp

Github services generally use [Twirp](https://twitchtv.github.io/twirp/docs/intro.html) as the inter-service communication protocol. It is built on [protobuf](https://developers.google.com/protocol-buffers/).

### Setup

Install the needed Go tools in [tools.go](../tools.go) with `go install <tool name>`.

See the [Twirp installation documentation](https://twitchtv.github.io/twirp/docs/install.html) for the most up to date directions.

To make updates to the Twirp API, modify [service.proto](../rpc/tma/v0/service.proto)
and run `make generate-twirp`. This will regenerate `service.pg.go` and `service.twirp.go` that define the twirp server and clients. The business logic is written by us and is kept in the [`pkg/transport`](../pkg/transport/) directory.

### Using Twirp

Once the service is running locally or remotely, a request can be made to the Twirp
API by importing the generated protobuf or JSON clients into a Go file:

```go
package main

import (
 "context"
 "fmt"
 "github.com/github/trust-metadata-api/rpc"
 "net/http"
 "os"
)

func main() {
  // default Twirp API port is 8080
 client := rpc.NewTrustMetadataAPIProtobufClient(
  "http://localhost:8080",
    &http.Client{},
 )

 status, err := client.Status(context.Background(), &rpc.StatusRequest{})
 if err != nil {
  fmt.Printf("request failed: %v", err)
  os.Exit(1)
 }
 fmt.Printf("The TMA protobuf API status is: %+v", status)
}
```

### Requests

You can access the Twirp endpoints [using curl](https://twitchtv.github.io/twirp/docs/curl.html) if you use the header `Content-Type: application/json` to signal that the request and response are JSON.

```shell
curl --header "Content-Type: application/json" \
  --request "POST" --data '{}' \
  http://localhost:8080/twirp/github.trust_metadata_api.TrustMetadataAPI/Status
```

### API documentation

API documentation exists at [api-docs.html](./api-docs.html) in this directory. It is generated from the Twirp service using [OpenAPI](https://www.openapis.org/) (Swagger) and [twirp-swagger-gen](https://github.com/go-bridget/twirp-swagger-gen).

Note that we depend on a fork of `twirp-swagger-gen` in order to produce valid documentation, as the current (as of Dec. 2022) version doesn't support camelCased field names or configurable proto paths. The PRs to add those features exist at [this link](https://github.com/go-bridget/twirp-swagger-gen/pull/12) and [this link](https://github.com/go-bridget/twirp-swagger-gen/pull/11) respectively.

In order to regenerate documentation, you'll need to install my fork of `twirp-swagger-gen`:

```shell
git clone https://github.com/codysoyland/twirp-swagger-gen.git
cd twirp-swagger-gen
git checkout origin/updates
go install ./cmd/twirp-swagger-gen
```

You'll also need `swagger-codegen`:

```shell
brew install swagger-codegen
```

Then enter the TMA repo and run:

```shell
make docs/api-docs.html
```

To view the rendered documentation, run:

```shell
open docs/api-docs.html
```

It is important that you follow these steps each time you make a change to our protobuf files. This will ensure that documentation is always up-to-date.
