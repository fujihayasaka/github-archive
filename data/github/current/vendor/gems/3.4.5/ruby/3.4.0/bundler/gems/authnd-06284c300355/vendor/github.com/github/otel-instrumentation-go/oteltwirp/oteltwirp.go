package oteltwirp

import (
	"context"
	"log"
	"net/http"
	"net/url"

	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

const tracerName = "github.com/github/otel-instrumentation-go/oteltwirp"

// Twirp is opinionated about not exposing HTTP concepts to their hooks, and Go's middleware design means you can't see context after
// handing it off to "nested" middlewares, so we have to pass stuff around ourselves.
type headersContextKey struct{}
type requestUrlContextKey struct{}
type responseWriterContextKey struct{}

// We create the span on inc request and release it on response
type spanContextKey struct{}

// Middleware is meant to be used as a middleware for Twirp services.
func Middleware(base http.Handler) http.Handler {
	return http.HandlerFunc(func(wr http.ResponseWriter, req *http.Request) {
		ctx := req.Context()
		ctx = context.WithValue(ctx, headersContextKey{}, req.Header)
		ctx = context.WithValue(ctx, responseWriterContextKey{}, wr)
		ctx = context.WithValue(ctx, requestUrlContextKey{}, req.URL)
		req = req.WithContext(ctx)
		base.ServeHTTP(wr, req)
	})
}

// NewServerHooks returns a new ServerHooks instance that can be used to instrument Twirp services.
func NewServerHooks() *twirp.ServerHooks {
	return &twirp.ServerHooks{
		RequestRouted: requestRouted,
		ResponseSent:  responseSent,
	}
}

// requestRouted is called when a request is routed to a service and method.
func requestRouted(ctx context.Context) (context.Context, error) {
	headers := getHeaders(ctx)
	if headers == nil {
		return ctx, nil
	}
	ctx = otel.GetTextMapPropagator().Extract(ctx, propagation.HeaderCarrier(headers))

	tracer := otel.Tracer(tracerName, trace.WithInstrumentationVersion(SemVersion()))

	methodName, ok := twirp.MethodName(ctx)
	if !ok {
		methodName = "unknown"
	}

	ctx, span := tracer.Start(ctx, methodName, trace.WithSpanKind(trace.SpanKindServer))
	ctx = context.WithValue(ctx, spanContextKey{}, span)
	return ctx, nil
}

// responseSent is called after a response is sent, with its HTTP status code.
func responseSent(ctx context.Context) {
	span, ok := setSpanContext(ctx)
	if !ok {
		return
	}
	defer span.End()

	spanName, ok := twirp.MethodName(ctx)
	if ok {
		span.SetName(spanName)
	}

	status, _ := twirp.StatusCode(ctx)
	if status == "" {
		status = "200"
	}

	switch status[0] {
	case '5', '4':
		span.SetStatus(codes.Error, status)
	default:
		// 2xx, 3xx, 1xx etc is fine
		span.SetStatus(codes.Ok, status)
	}

	headers := getHeaders(ctx)
	reqid := ""
	if headers != nil {
		reqid = headers.Get("X-GitHub-Request-Id")
	}
	reqUrl := getReqURL(ctx)
	if reqUrl == nil {
		reqUrl = &url.URL{}
	}

	attrs := []attribute.KeyValue{
		attribute.String("gh.request_id", reqid),
		attribute.String("http.target", reqUrl.String()),
		attribute.String("http.status_code", status),
	}

	responseWriterValue := ctx.Value(responseWriterContextKey{})
	if responseWriterValue != nil {
		wr, ok := responseWriterValue.(http.ResponseWriter)
		if !ok {
			log.Print("responseWriterContextKey pointed to a value that was not an http.ResponseWriter")
		}

		// Log all response headers? Reviewer input needed. Middleware isn't guaranteed to have the correct WR instance (it can get wrapped as you go down)
		for k := range wr.Header() {
			attrs = append(attrs, attribute.String("http.resp_header."+k, wr.Header().Get(k)))
		}
	}

	span.SetAttributes(attrs...)
}

// getHeaders returns the headers from the context, or nil if they are not present.
func getHeaders(ctx context.Context) http.Header {
	headersCtxValue := ctx.Value(headersContextKey{})
	if headersCtxValue == nil {
		return nil
	}

	return headersCtxValue.(http.Header)
}

// getReqURL returns the request URL from the context, or nil if it is not present.
func getReqURL(ctx context.Context) *url.URL {
	reqURLCtxValue := ctx.Value(requestUrlContextKey{})
	if reqURLCtxValue == nil {
		return nil
	}

	return reqURLCtxValue.(*url.URL)
}

// setSpanContext returns the span from the context, or nil if it is not present.
func setSpanContext(ctx context.Context) (trace.Span, bool) {
	spanCtxValue := ctx.Value(spanContextKey{})
	if spanCtxValue == nil {
		return nil, false
	}

	return spanCtxValue.(trace.Span), true
}
