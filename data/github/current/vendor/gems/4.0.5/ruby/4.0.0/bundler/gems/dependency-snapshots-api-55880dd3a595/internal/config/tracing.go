package config

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/trace"

	"go.opentelemetry.io/otel"
)

// This whole file is heavily derivative from hookshot-go's tracing.go.
func Instrument(appConfig *Config) (func(), error) {
	l, err := log.NewFromEnv()
	if err != nil {
		return nil, err
	}
	eh := ErrorHandler{logger: l}
	otel.SetErrorHandler(eh)

	tp, err := trace.NewFromEnv()
	if err != nil {
		return nil, fmt.Errorf("could not start telemetry provider: %w", err)
	}

	return func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := tp.Provider.Shutdown(ctx); err != nil {
			l.Fatal("error shutting down tracer", kvp.String("err", err.Error()))
		}
	}, nil
}

type ErrorHandler struct {
	// TODO: This was a "multithreaded logger" in hookshot-go's implementation, a more limited interface.
	// The tl;dr is: Don't use "Add". hookshot-go created their own wrapper to hide the Add method, because it is not thread safe.
	logger log.Logger
}

func (eh ErrorHandler) Handle(err error) {
	if err != nil {
		eh.logger.Error("encountered a problem during tracing", kvp.String("exception.message", err.Error()))
	}
}
