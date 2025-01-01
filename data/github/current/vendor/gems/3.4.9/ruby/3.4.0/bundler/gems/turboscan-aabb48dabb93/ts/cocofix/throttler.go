package cocofix

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	capiThrottler "github.com/github/token-scanning-service/cmd/capi-throttler/client"
	capiThrottlerConfig "github.com/github/token-scanning-service/cmd/capi-throttler/config"
	"github.com/github/turboscan/ts"
	"github.com/pkg/errors"
)

var ErrInvalidThrottlerWorload = errors.New("Invalid ThrottlerWorload")

type Throttler struct {
	highPriorityThrottler capiThrottler.CapiThrottler
	lowPriorityThrottler  capiThrottler.CapiThrottler
}

func NewThrottler(logger log.Logger, capiThrottlerUrl string) (*Throttler, error) {
	highPriorityThrottler, err := capiThrottler.NewCapiThrottler(logger, capiThrottlerUrl, capiThrottlerConfig.CodeScanningAutofixHighPriority)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create high priority throttler")
	}

	lowPriorityThrottler, err := capiThrottler.NewCapiThrottler(logger, capiThrottlerUrl, capiThrottlerConfig.CodeScanningAutofixLowPriority)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create low priority throttler")
	}

	return &Throttler{
		highPriorityThrottler: highPriorityThrottler,
		lowPriorityThrottler:  lowPriorityThrottler,
	}, nil
}

func (t *Throttler) getCapiThrottler(workload ts.ThrottlerWorkload) (capiThrottler.CapiThrottler, error) {
	switch workload {
	case ts.ThrottlerWorkload_HIGH:
		return t.highPriorityThrottler, nil
	case ts.ThrottlerWorkload_LOW:
		return t.lowPriorityThrottler, nil
	default:
		return nil, ErrInvalidThrottlerWorload
	}
}

func (t *Throttler) getDelay(ctx context.Context, workload ts.ThrottlerWorkload) (int64, error) {
	throttler, err := t.getCapiThrottler(workload)
	if err != nil {
		return 0, err
	}
	return throttler.GetDelay(ctx, capiThrottlerConfig.GPT4, 1)
}

func (t *Throttler) WaitOnThrottler(ctx context.Context, workload ts.ThrottlerWorkload) error {
	delay, err := t.getDelay(ctx, workload)
	if err != nil {
		if errors.Is(err, ErrInvalidThrottlerWorload) {
			return err
		}
		// Ignore errors from the throttler
		// If calls to the server fail, client is expected to fallback to direct requests to copilot-api and honor any rate limiting 429's they receive from them.
		// https://github.com/github/token-scanning-service/blob/main/cmd/capi-throttler/docs/architecture.md
		appctx.Report(ctx, err, nil)
		return nil
	}

	msDelay := time.Duration(delay) * time.Millisecond
	appctx.Stats(ctx).DistributionMs("cocofix_runner.capi_throttler.delay", stats.Tags{"workload": workload.String()}, msDelay)

	// If 0 delay, short-circuit now instead of spinning up a timer goroutine
	if msDelay == 0 {
		return nil
	}

	select {
	case <-ctx.Done():
		return errors.Wrap(ctx.Err(), "context cancelled during throttler wait")
	case <-time.After(msDelay):
		// done waiting
	}

	return nil
}
