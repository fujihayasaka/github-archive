package utils

import (
	"context"
	"runtime/debug"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
)

func PanicLogger(ctx context.Context) {
	if err := recover(); err != nil {
		statting.Counter(ctx, "panic", 1)
		logging.Error(ctx, "panic", kvp.Any("err", err), kvp.String("stack", string(debug.Stack())))
		panic(err)
	}
}
