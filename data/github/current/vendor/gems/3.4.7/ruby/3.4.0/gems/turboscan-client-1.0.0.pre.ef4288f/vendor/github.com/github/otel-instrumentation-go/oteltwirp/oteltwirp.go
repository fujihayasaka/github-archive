// Package oteltwirp provides autoinstrumentation for twirp services using server hooks
package oteltwirp

import (
	"context"
	"fmt"
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
type httpMethodContextKey struct{}
type requestURLContextKey struct{}
type responseWriterContextKey struct{}

// We create the span on inc request and release it on response
type spanContextKey struct{}

// Middleware is tracing middleware for Twirp services.
func Middleware(base http.Handler) http.Handler {
	return http.HandlerFunc(func(wr http.ResponseWriter, req *http.Request) {
		ctx := req.Context()
		ctx = context.WithValue(ctx, headersContextKey{}, req.Header)
		ctx = context.WithValue(ctx, responseWriterContextKey{}, wr)
		ctx = context.WithValue(ctx, requestURLContextKey{}, req.URL)
		ctx = context.WithValue(ctx, httpMethodContextKey{}, req.Method)
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

	spanName := getSpanName(ctx)

	ctx, span := tracer.Start(ctx, spanName, trace.WithSpanKind(trace.SpanKindServer)) //nolint:spancheck // we are using the span to pass it around
	ctx = context.WithValue(ctx, spanContextKey{}, span)
	return ctx, nil //nolint:spancheck // we are using the span to pass it around
}

// responseSent is called after a response is sent, with its HTTP status code.
func responseSent(ctx context.Context) {
	span, ok := getSpanContext(ctx)
	if !ok {
		return
	}
	defer span.End()

	status, _ := twirp.StatusCode(ctx)
	if status == "" {
		status = "200"
	}

	switch status[0] {
	case '5':
		span.SetStatus(codes.Error, status)
	case '4':
		// 4xx range span status must be left unset for SpanKind.SERVER
	default:
		// 2xx, 3xx, 1xx etc is fine
		span.SetStatus(codes.Ok, status)
	}

	headers := getHeaders(ctx)
	reqid := ""
	if headers != nil {
		reqid = headers.Get("X-Github-Request-Id")
	}
	reqURL := getReqURL(ctx)
	if reqURL == nil {
		reqURL = &url.URL{}
	}

	attrs := []attribute.KeyValue{
		attribute.String("gh.request_id", reqid),
		attribute.String("http.target", reqURL.String()),
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
	headersCtxValue, ok := ctx.Value(headersContextKey{}).(http.Header)
	if !ok {
		return nil
	}
	return headersCtxValue
}

// getHTTPMethod returns the HTTP method from the context, or "" if it is not present.
func getHTTPMethod(ctx context.Context) string {
	httpMethodCtxValue, ok := ctx.Value(httpMethodContextKey{}).(string)
	if !ok {
		return ""
	}
	return httpMethodCtxValue
}

// getReqURL returns the request URL from the context, or nil if it is not present.
func getReqURL(ctx context.Context) *url.URL {
	reqURLCtxValue, ok := ctx.Value(requestURLContextKey{}).(*url.URL)
	if !ok {
		return nil
	}
	return reqURLCtxValue
}

// getSpanContext returns the span from the context, or nil if it is not present.
func getSpanContext(ctx context.Context) (trace.Span, bool) {
	spanCtxValue, ok := ctx.Value(spanContextKey{}).(trace.Span)
	if !ok {
		return nil, false
	}
	return spanCtxValue, true
}

// getSpanName returns the name of the span following OpenTelemetry semantic conventions for Twirp.
func getSpanName(ctx context.Context) string {
	httpMethod := getHTTPMethod(ctx)
	if httpMethod == "" {
		return "unknown"
	}

	requestURL := getReqURL(ctx)
	if requestURL == nil {
		return "unknown"
	}

	// <HTTP-METHOD> /<prefix>/<package>.<Service>/<Method>
	return fmt.Sprintf("%s %s", httpMethod, requestURL.Path)
}
