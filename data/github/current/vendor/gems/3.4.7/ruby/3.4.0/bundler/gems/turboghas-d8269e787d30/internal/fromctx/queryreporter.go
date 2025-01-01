package fromctx

import (
	"context"
	"time"

	"github.com/simon-engledew/ctxkey"
)

type ReportQuery func(ctx context.Context) func(query string, duration time.Duration, results int64)

type queryReporter struct {
	ctxkey.ContextKey[ReportQuery]
}

var QueryReporter = queryReporter{
	ctxkey.New[ReportQuery](nil),
}

func (q queryReporter) Report(ctx context.Context, query string, duration time.Duration, results int64) {
	if fn := q.Value(ctx); fn != nil {
		if reporter := fn(ctx); reporter != nil {
			reporter(query, duration, results)
		}
	}
}
