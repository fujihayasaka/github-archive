// Package sigctx provides copy of the parent context that is marked done when one of the listed signals arrives or when the parent context's Done channel is closed.
package sigctx

import (
	"context"
	"os"
	"os/signal"
)

// WithSignal returns a copy of the parent context that is marked done
// (its Done channel is closed) when one of the listed signals arrives
// or when the parent context's Done channel is closed.
//
// Deprecated. This interface provides no way to uninstall the signal
// handler.  Prefer signal.NotifyContext from the standard os/signal package.
func WithSignal(ctx context.Context, signals ...os.Signal) context.Context {
	ctx, _ = signal.NotifyContext(ctx, signals...)
	return ctx
}
