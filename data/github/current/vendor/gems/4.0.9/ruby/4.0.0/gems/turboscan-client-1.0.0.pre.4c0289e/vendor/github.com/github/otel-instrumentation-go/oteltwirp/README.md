# [twitchtv/twirp] instrumentation for OpenTelemetry Go

[Twirp](https://github.com/twitchtv/twirp) is a service to service communication framework.

This package provides OpenTelemetry instrumentation for twirp services, covering both **server-side** (via server hooks and middleware) and **client-side** (via a wrapped HTTP client).

## Installation
```
go get github.com/github/otel-instrumentation-go/oteltwirp
```

## Server-Side Instrumentation

Use `Middleware` and `NewServerHooks` to instrument incoming twirp requests:

```go
twirpHandler := mona.NewMonaServer(&monaServer{}, twirp.WithServerHooks(oteltwirp.NewServerHooks()))
httpHandler := oteltwirp.Middleware(twirpHandler)
http.ListenAndServe(":8080", httpHandler)
```

## Client-Side Instrumentation

> [!NOTE]
> Twirp client calls made over HTTP could align to either [HTTP](https://opentelemetry.io/docs/specs/semconv/http/http-spans/) or [RPC](https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans/) semantic conventions. GitHub [decided](https://github.com/github/observability-experience/issues/12#issuecomment-2179374951) to align with HTTP conventions, and this client instrumentation applies HTTP semantics, with some optional RPC conventions that add additional value.

`TraceHTTPClient` wraps an `http.Client` (or any `HTTPClient` implementation) to create OpenTelemetry client spans for outgoing twirp RPC calls. Instrument a twirp-generated client:

```go
tracedHTTPClient := oteltwirp.NewTraceHTTPClient(http.DefaultClient)
client := mona.NewMonaProtobufClient("http://localhost:8080", tracedHTTPClient)
resp, err := client.MakeOctocat(ctx, &mona.Size{})
```

### Options

| Option | Description |
|---|---|
| `WithTracerProvider(tp)` | Sets a specific `trace.TracerProvider` instead of using the global provider. |

### Span Attributes

The client creates a span with `SpanKind = Client` for each `Do()` call. The span name is `<http.request.method> <url.template>`, e.g. `POST /twirp/mona.Mona/MakeOctocat`.

#### RPC Attributes

| Attribute | Value | Description |
|---|---|---|
| `rpc.system` | `"twirp"` | RPC system identifier |
| `rpc.method` | e.g. `"MakeOctocat"` | Method name from twirp context |
| `rpc.service` | e.g. `"Mona"` | Service name from twirp context |
| `rpc.package` | e.g. `"mona"` | Protobuf package name from twirp context |

#### HTTP Semantic Convention Attributes

| Attribute | Description |
|---|---|
| `url.full` | Full request URL |
| `url.template` | URL path (twirp paths are deterministic per-method) |
| `server.address` | Hostname of the target server |
| `server.port` | Port of the target server (defaults to 80 for HTTP, 443 for HTTPS) |
| `http.request.method` | HTTP method (always `POST` for twirp) |
| `http.response.status_code` | HTTP response status code |
| `error.type` | Status code as string for HTTP errors (e.g. `"404"`), or Go error type for transport errors (e.g. `"*url.Error"`) |

### Context Propagation

`TraceHTTPClient` automatically injects trace context into outgoing HTTP headers using the globally configured `TextMapPropagator` (e.g. W3C Trace Context).

## References

- [Twirp documentation](https://twitchtv.github.io/twirp/docs/intro.html)
- [OpenTelemetry RPC semantic conventions](https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans/)
- [OpenTelemetry HTTP semantic conventions](https://opentelemetry.io/docs/specs/semconv/http/http-spans/)
- [Examples](./example)
