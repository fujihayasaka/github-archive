package hooks

import (
	"github.com/github/otel-instrumentation-go/oteltwirp"
	"github.com/twitchtv/twirp"
)

// TracingHooks is a convenience function to combine TraceHooks.
func TracingHooks() *twirp.ServerHooks {
	return twirp.ChainHooks(
		TraceHooks(),
	)
}

// TraceHooks returns a set of hooks that will trace requests.
// It uses the oteltwirp auto-instrumentation package to create
// spans for each request.
func TraceHooks() *twirp.ServerHooks {
	return oteltwirp.NewServerHooks()
}
