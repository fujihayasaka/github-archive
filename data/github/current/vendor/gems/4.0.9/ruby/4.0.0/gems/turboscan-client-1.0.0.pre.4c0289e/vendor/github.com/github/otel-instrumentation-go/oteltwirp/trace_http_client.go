package oteltwirp

import (
	"fmt"
	"net/http"
	"net/url"
	"strconv"

	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	semconv "go.opentelemetry.io/otel/semconv/v1.37.0"
	"go.opentelemetry.io/otel/trace"
)

// HTTPClient is an interface that models [http.Client].
type HTTPClient interface {
	Do(req *http.Request) (*http.Response, error)
}

// TraceHTTPClient wraps an [http.Client] to instrument outgoing twirp RPC calls
// with OpenTelemetry spans and semantic convention attributes.
type TraceHTTPClient struct {
	client HTTPClient
	opts   *TraceOptions
	tracer trace.Tracer
}

var _ HTTPClient = (*TraceHTTPClient)(nil)

// NewTraceHTTPClient wraps the provided [http.Client] with OpenTelemetry
// instrumentation. If client is nil, [http.DefaultClient] is used.
func NewTraceHTTPClient(client HTTPClient, opts ...TraceOption) *TraceHTTPClient {
	if client == nil {
		client = http.DefaultClient
	}

	clientOpts := &TraceOptions{}
	for _, opt := range opts {
		opt(clientOpts)
	}

	tp := clientOpts.tracerProvider
	if tp == nil {
		tp = otel.GetTracerProvider()
	}

	return &TraceHTTPClient{
		client: client,
		opts:   clientOpts,
		tracer: tp.Tracer(tracerName, trace.WithInstrumentationVersion(SemVersion())),
	}
}

// Do executes the HTTP request with tracing instrumentation. It creates a
// client span, sets RPC and HTTP semantic convention attributes, injects
// trace context into outgoing headers, and captures the response status.
func (c *TraceHTTPClient) Do(req *http.Request) (*http.Response, error) {
	ctx := req.Context()

	spanName := clientSpanName(req)

	ctx, span := c.tracer.Start(ctx, spanName, trace.WithSpanKind(trace.SpanKindClient))

	// RPC attributes
	attrs := []attribute.KeyValue{
		semconv.RPCSystemKey.String("twirp"),
	}
	if methodName, ok := twirp.MethodName(ctx); ok {
		attrs = append(attrs, semconv.RPCMethod(methodName))
	}
	if serviceName, ok := twirp.ServiceName(ctx); ok {
		attrs = append(attrs, semconv.RPCService(serviceName))
	}
	if packageName, ok := twirp.PackageName(ctx); ok {
		attrs = append(attrs, attribute.String("rpc.package", packageName))
	}

	// HTTP semantic convention attributes
	attrs = append(attrs,
		semconv.URLFull(req.URL.String()),
		semconv.URLTemplate(req.URL.Path),
		semconv.ServerAddress(req.URL.Hostname()),
		semconv.HTTPRequestMethodKey.String(req.Method),
		semconv.ServerPort(serverPort(req.URL)),
	)

	span.SetAttributes(attrs...)

	// Inject trace context into outgoing headers
	otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))

	req = req.WithContext(ctx)

	res, err := c.client.Do(req)
	if err != nil {
		// transport level error, set error status and end span
		span.SetAttributes(semconv.ErrorType(err))
		span.RecordError(err)
		span.SetStatus(codes.Error, fmt.Sprintf("%T", err))
		span.End()
		return res, err
	}

	span.SetAttributes(semconv.HTTPResponseStatusCode(res.StatusCode))

	if res.StatusCode >= 400 {
		span.SetAttributes(semconv.ErrorTypeKey.String(strconv.Itoa(res.StatusCode)))
		span.SetStatus(codes.Error, http.StatusText(res.StatusCode))
	}

	span.End()
	return res, nil
}

// clientSpanName returns the span name for a client request:
// "<http.request.method> <url.template>", e.g. "POST /twirp/mona.Mona/MakeOctocat".
func clientSpanName(req *http.Request) string {
	return req.Method + " " + req.URL.Path
}

// serverPort returns the port from the URL, falling back to the default port
// for the scheme (80 for http, 443 for https).
func serverPort(u *url.URL) int {
	if p := u.Port(); p != "" {
		if port, err := strconv.Atoi(p); err == nil {
			return port
		}
	}
	switch u.Scheme {
	case "https":
		return 443
	default:
		return 80
	}
}
