# `Authzd` Go Client

A Go client to interact with the authzd RPC interface which supports the `authorize`, `enumerate`, and `capevaluate` APIs

## Using it


### Authorization Requests
There are currently two kinds of requests you can issue against the `authorize` endpoint:

- Authorization requests
- Batched authorization requests

The first aims to answer questions like "is this actor allowed to perform this action on this subject?"
The second allows the client to batch multiple individual authorization requests in a single RPC call.

This is helpful to remove network overhead and leverage concurrent evaluation of requests.

These two RPCs are defined as part of authzd's [`Authorizer` service](https://github.com/github/authzd/blob/295aa92e072b44389717d1fd6650140bcf38f353/proto/authz.proto#L104-L107), which this client
implements.

A basic implementation looks like:

```go
import (
    "context"

    "github.com/github/authzd/pkg/client"
    "github.com/github/authzd/pkg/proto"
)

SERVER_ADDRESS := "https://authzd.domain.com/twirp"

authzdClient := client.New(SERVER_ADDRESS)
request := &proto.Request{}
decision, err := authzdClient.Authorize(context.TODO, request)
```

The above automatically uses the net/http.DefaultClient; see below for instructions on how to provider your own as an option to `New`.

### Batching Requests

A `BatchRequest` is nothing more than multiple `Request`s packed in one call. The batched responses
will correspond to the incoming batched requests through the order specified (i.e. request[3] ->
response[3]):

```go
request1 := &proto.Request{}
request2 := &proto.Request{}
batch := &proto.BatchRequest{
    Requests: []*proto.Request{
        request1,
        request2,
    }
}
batchDecision := authzdClient.BatchAuthorizer(context.TODO, batch)
response1 := batchDecision.decisions[0]
```

BatchAuthorize requests are resolved on the Authzd node that receives the request. For large `BatchRequests`, 
splitting the request into multiple requests resolves the query across multiple Authzd nodes, which spreads
the load and avoids hot spots. It is recommended to do 
batch slicing when you expect slices to be larger than 100 elements.

This behavior can be requested when initiating the Client by specifying `WithBatchSlicing` as an option. The option is documented below in [Splitting BatchAuthorize requests into Slices](#splitting-batchauthorize-requests-into-slices).


### Enumeration Requests

The Enumeration RPC is an implementation of authorized actor and resource enumeration via Authzd. This endpoint can perform:

- Subject Enumeration
- Actor Enumeration

Note that production Enumeration requests require a valid HMAC header.

#### Subject Enumeration

This endpoint answers the question: what subjects does this actor have access to? More specifically, given a `user`, enumerate the repositories that for which the `User` has `read` abilities. We currently only support 1 subject type (`Repository`) and 1 actor type (`User`).

```go
import (
    "github.com/github/authzd/pkg/client"
    enumeratorpb "github.com/github/authzd/pkg/enumerator"
)

hmacSecret := "a-sample-hmac-secret"
authzdClient := client.New(SERVER_ADDRESS, client.WithWithHMACSignature(hmacSecret))
actorReq := enumeratorpb.ForActorRequest{ActorType: "User", ActorId: 17, SubjectType: "Repository"}
result, err := authzdClient.ForActor(context.Background(), &actorReq)

subjectIds := result.ResultIds
```

#### Actor Enumeration

This endpoint answers the question: what actors have access to this subject? More specifically, given a repository, enumerate the users that have read access. We currently only support 1 subject type (`Repository`) and 1 actor type (`User`).

```go
import (
    "github.com/github/authzd/pkg/client"
    enumeratorpb "github.com/github/authzd/pkg/enumerator"
)

hmacSecret := "a-sample-hmac-secret"
authzdClient := client.New(SERVER_ADDRESS, client.WithWithHMACSignature(hmacSecret))
subjectReq := enumeratorpb.ForSubjectRequest{ActorType: "User", SubjectId: 17, SubjectType: "Repository"}
result, err := authzdClient.ForSubject(context.Background(), &subjectReq)

actorIds := result.ResultIds
```

### Conditional Access Policy Evaluation (Cap Evaluator) Requests

The `EvaluatePoliciesForSingleResource` RPC is an implementation of single resource conditional access policy evaluation (aka cap enforcement) via Authzd.

Note that production Cap Evaluation requests require a valid HMAC header (can be retrieved via the `.authzd cap-hmac` chatop in Slack).

#### Single Resource Conditional Access Policy Evaluation (aka "cap enforcement")

```go
import (
    "github.com/github/authzd/pkg/client"
    authorizerpb "github.com/github/authzd/pkg/proto"
    capevaluatorpb "github.com/github/authzd/pkg/capevaluator"
)

hmacSecret := "a-sample-hmac-secret"
authzdClient := client.New(SERVER_ADDRESS, client.WithWithHMACSignature(hmacSecret))
req := capevaluator.SingleResourceRequest{
    Attributes: []*authorizerpb.Attribute{
        {
            Id:    "conditional.access.resource.id",
            Value: authorizerpb.NewInt64Value(1),
        },
        {
            Id:    "conditional.access.resource.type",
            Value: authorizerpb.NewStringValue("User"),
        },
    },
}
response, err := authzdClient.EvaluatePoliciesForSingleResource(context.Background(), &req)

results := response.Results
```

## Client Options

### Custom HTTP Client

To specify a custom HTTP client, use the `WithHTTPClient` option to `New`:

```go
myHTTPClient := &http.Client{}

authzdClient := client.New(SERVER_ADDRESS, client.WithHTTPClient(myHTTPClient))
```

### User Agent

We strongly recommend you send a User Agent ID in any requests to Authzd - this allows quickly identify
application and owning team in case of errors or incorrect behaviour. This is implemented by overriding the User Agent
HTTP header to contain a client-specified string.

```go
authzdClient := client.New(SERVER_ADDRESS, client.WithUserAgent("repo/binary"))
```

This is a freeform string, but we recommend something like the above format so we can enumerate
our clients and inform the service owner of any new updates to this client library.

### Request ID Forwarding

In order to support tracing requests through GitHub infrastructure, we encourage clients to set
the `X-GitHub-Request-ID` header in any requests to Authzd. You can enable this behaviour by using
`WithRequestIDForwarder`.

```go
authzdClient := client.New(SERVER_ADDRESS, client.WithRequestIDForwarder())
```

As long as the context you use for requests contains a GitHub Request ID already (perhaps by using
the requestid.Handler in your server chain) this will be passed through appropriately.

If you do not use this middleware then the Authzd server will generate a new request ID for each
request it receives, making correlation more difficult.

### Retries

In order to use retries, you will need to use an HTTP client that supports this - an example is Hashicorp's `go-retryablehttp`.

```go
import (
    "github.com/github/authzd/pkg/client"
    retryablehttp"github.com/hashicorp/go-retryablehttp"
)

clientWithRetries := retryablehttp.NewClient()
clientWithRetries.RetryMax = 3
clientWithRetries.RetryWaitMin = 10 * time.Millisecond
authzdClient := client.New(SERVER_ADDRESS, client.WithHTTPClient(clientWithRetries.StandardClient()))
```

Note that this will only retry based on the HTTP response (any 50x response except 501). Notably,
it will not duplicate the Ruby client behaviour of retrying requests that return `Indeterminate`
responses.

### Circuit Breaker

You can also use a CircuitBreaker implementation like [rubyist](https://github.com/rubyist/circuitbreaker) as part of
the HTTP client setup.

```go
import (
    "github.com/rubyist/circuitbreaker"
)

circuitBreakingClient := circuitbreaker.NewHTTPClient(10*time.Second, 25, myHTTPClient)
authzdClient := client.New(SERVER_ADDRESS, client.WithHTTPClient(circuitBreakingClient))
```

Note that the rubyist circuitbreaker only short-circuits on HTTP timeouts and in particular does not inspect the Twirp
response for `failure`s.

### HMAC Header

The Enumerator endpoints require an [HMAC header](https://thehub.github.com/engineering/development-and-ops/secure-coding/secure-coding-general/service-to-service-auth/#how-to-implement-authentication-between-services). The `WithHMACSignature` client `Option` will generate an HMAC token using the current time and the provided shared secret, and will add the `REQUEST_HMAC` header to the request.

```go
hmacSecret := "a-sample-hmac-secret"
myHTTPClient := &http.Client{}
request := &enumeratorpb.ForSubjectRequest{SubjectId: 4, SubjectType: "Repository", ActorType: "User"})
authzdClient := client.New(SERVER_ADDRESS, client.WithHMACSignature(hmacSecret)))

```
### Telemetry

You can pass an instance of `github.com/github/go-stats.Client` to `WithStatter()` to get metrics reported.

```go
import (
    "github.com/github/authzd/pkg/client"
    "github.com/github/go-stats"
)

statsClient := stats.NewClient(...)

authzdClient := client.New(SERVER_ADDRESS, client.WithStatter(statsClient, "client-id"))
```

You must pass a Client ID to this middleware in order to allow us to differentiate metrics from various clients.

We currently report the following metrics:

<dl>
<dt>authzd.client.request</dt>
<dd>A counter that increases on each request to Authzd. Through metric tags, batch requests can be distinguished from individual requests..</dd>
<dt>authzd.client.timing</dt>
<dd>A distribution that measures the latency of each request to Authzd. Through metric tags, batch requests can be distinguished from individual requests.
</dl>

### OpenTelemetry support

GitHub is migrating from OpenTracing to OpenTelemetry, so services using it are becoming more common. We can
achieve the same by using OpenTelemetry [`otelhttp`](https://pkg.go.dev/go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp) go package:

```go
import (
    "time"

    "github.com/github/authzd/pkg/client"
    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

func main() {
    otelCli := otelhttp.DefaultClient
    otelCli.Timeout =  5 * time.Second
    authzdClient, err := client.New("https://authzd-server-url", client.WithHTTPClient(otelCli))
```

### Splitting BatchAuthorize requests into Slices

`WithBatchSlicing` enables slicing of BatchAuthorize requests, by issuing smaller batch requests with a maximum
size defined by the "sliceSize" argument. This helps spread the load across the service fleet.

It's recommended to do batch slicing when you expect slices to be larger than 100 elements.

```go
authzdClient := client.New(SERVER_ADDRESS, client.WithBatchSlicing(100, 1)
```

The first argument is the `sliceSize`. The second argument, `maxConcurrency` defines the maximum number of concurrent 
requests for each one of the slices. It currently has no effect, but
will be relevant once splitting batches into concurrently executed slices is implemented. 
## Putting it all together

An example stack that handles all of the above concerns is as follows:

```go
package main

import (
    "context"
    "os"
    "time"

    "github.com/github/authzd/pkg/client"
    "github.com/github/authzd/pkg/proto"
    "github.com/github/go-kvp"
    "github.com/github/go-log"
    "github.com/github/go-stats"

    "github.com/hashicorp/go-retryablehttp"
    "github.com/opentracing/opentracing-go"
    circuit "github.com/rubyist/circuitbreaker"
)

const addr = "http://127.0.0.1:8081"
const clientID = "test"

func main() {

    logger := log.DefaultLogger
    statter := stats.NullStatter

    retryingClient := retryablehttp.NewClient()
    retryingClient.RetryMax = 3
    retryingClient.RetryWaitMin = 1 * time.Millisecond
    circuitBreakingClient := circuit.NewHTTPClient(5*time.Second, 25, retryingClient.StandardClient())
    events := circuitBreakingClient.Panel.Subscribe()
    go reportBreakerStats(events, statter, log)

    tracer := opentracing.NoopTracer{}
    tracingClient := ottwirp.NewTraceHTTPClient(circuitBreakingClient, tracer)

    hmacSecret := "example-shared-secret"

    ac, _ := client.New(addr,
        client.WithUserAgent(clientID),
        client.WithHMACSignature(hmacSecret),
        client.WithRequestIDForwarder(),
        client.WithHTTPClient(tracingClient),
        client.WithBatchSlizing(100, 1)
        client.WithStatter(statter, clientID),
    )

    dec, err := ac.Authorize(context.Background(), &proto.Request{})
    if err != nil {
        log.Error("request to authzd failed", kvp.Err(err))
        os.Exit(1)
    }
    log.Info("response from authzd", kvp.String("result", dec.Result.String()))
}

func reportBreakerStats(events <-chan circuit.PanelEvent, statter stats.Client, logger *log.Logger) {
    for {
        event := <-events

        switch event.Event {
        case circuit.BreakerTripped:
            statter.Counter("authzd.client.circuit_breaker", stats.Tags{"state": "open"}, 1)
            logger.Error("circuit breaker open")
        case circuit.BreakerFail:
            statter.Counter("authzd.client.circuit_breaker", stats.Tags{"state": "failure"}, 1)
            logger.Error("circuit breaker failure")
        case circuit.BreakerReady:
            statter.Counter("authzd.client.circuit_breaker", stats.Tags{"state": "closed"}, 1)
            logger.Info("circuit breaker closed")
        case circuit.BreakerReset:
            statter.Counter("authzd.client.circuit_breaker", stats.Tags{"state": "reset"}, 1)
            logger.Info("circuit breaker reset")
        }
    }
}
```

Please note that the order in which these clients can be constructed is heavily constrained and may
result in strange or unexpected behaviour if not carefully monitored. We advise not changing the order proposed above.

**We are aware of the awkwardness here and will be addressing it in future releases of the Client.**

## Developing & Testing

To run the test suite:

```bash
go test ./pkg/client
```

To run a single test file:

```bash
go test ./pkg/client/client_test.go
```

## Releasing

We will need to tag the authzd repository in order to allow users to retrieve the go client by version.
