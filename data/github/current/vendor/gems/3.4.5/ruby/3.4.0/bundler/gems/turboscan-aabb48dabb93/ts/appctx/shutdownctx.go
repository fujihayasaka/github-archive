package appctx

import (
	"context"

	"github.com/pkg/errors"
)

// IsShuttingDown returns true if the process was signalled to shut down
func IsShuttingDown(ctx context.Context) bool {
	return errors.Is(context.Cause(ctx), errShutdown)
}

// errShutdown is used as a cause if a service is terminating due to a signal
var errShutdown = errors.New("service shutting down")

// WithShutdown will cancel the context so IsShuttingDown will return true
func WithShutdown(ctx context.Context, done <-chan struct{}) context.Context {
	var cancelCause context.CancelCauseFunc
	ctx, cancelCause = context.WithCancelCause(ctx)

	go func() {
		<-done
		cancelCause(errShutdown)
	}()
	return ctx
}
