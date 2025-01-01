package resourceworker

import (
	"context"
	"sync/atomic"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

// tracker is a struct that keeps track of the resources that are being imported
// and some stats about the import process. This will probably be replaced
// by datadog metrics in the future. However, for now, it's a way of getting some visibility
// into the import process in a local environment.
type tracker struct {
	delta  atomic.Int64
	total  atomic.Int64
	logger log.Logger
}

func (t *tracker) start(ctx context.Context, period time.Duration) {
	ticker := time.NewTicker(period)
	defer ticker.Stop()
	lastTick := time.Now()
	for {
		select {
		case <-ticker.C:
			num := t.delta.Swap(0)
			elapsed := time.Since(lastTick)
			lastTick = time.Now()
			if elapsed.Seconds() == 0 {
				continue
			}
			rate := float64(num) / elapsed.Seconds()
			t.logger.Info("processed resources",
				kvp.Int64("delta", num),
				kvp.Int64("total", t.total.Load()),
				kvp.Float64("rate", rate),
			)
		case <-ctx.Done():
			return
		}
	}
}

func (t *tracker) addResource() {
	t.delta.Add(1)
	t.total.Add(1)
}
