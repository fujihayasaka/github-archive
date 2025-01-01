package reporter

import (
	"context"
	"sync"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-exceptions"
)

var (
	globalReporter *Reporter
	mu             sync.Mutex
)

func GetReporter() *Reporter {
	if globalReporter == nil {
		return NewReporter(exceptions.NullReporter)
	}

	return globalReporter
}

func GetBaseReporter() *exceptions.Reporter {
	return GetReporter().base
}

func SetReporter(baseReporter *exceptions.Reporter) {
	mu.Lock()
	globalReporter = NewReporter(baseReporter)
	mu.Unlock()
}

func Report(ctx context.Context, err error, fields ...kvp.Field) {
	GetReporter().Report(ctx, err, fields...)
}
