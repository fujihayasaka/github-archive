package common

import (
	"context"
	"strconv"
	"sync"
	"time"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
)

type HedgeManager interface {
	GetWaitTime() time.Duration
	GetMaxNumberOfHedges() int
	HandleOperationDuration(time.Duration)
}

type hedgeData struct {
	err     error
	hedge   int
	isHedge bool
}

func WithHedging(ctx context.Context, operationName string, operation func(ctx context.Context) error, hedgeManager HedgeManager) error {
	maxNumberOfHedges := hedgeManager.GetMaxNumberOfHedges()
	timeBetweenHedges := hedgeManager.GetWaitTime()
	diagnostics.Statter(ctx).DistributionMs("hedging.wait_time", stats.Tags{"operation": operationName}, timeBetweenHedges)

	var wg sync.WaitGroup
	var operationHedgeData *hedgeData

	newCtx, cancel := context.WithCancel(ctx)
	ch := make(chan *hedgeData, maxNumberOfHedges+1)
	sent := 0

Loop:
	for {
		if sent <= maxNumberOfHedges {
			sent++
			// The scheduler may run goroutines out of the definition order. We
			// increment outside the goroutine to guarantee it happens here,
			// specifically, before the call to wg.Wait further below.
			wg.Add(1)
			go func(sent int) {
				// Calling Done implies that this thread has no further use for the
				// chan (i.e. won't write to it). When every thread signals this, then
				// parent thread may close it safely.
				defer wg.Done()

				isHedge := sent > 1
				hedgeNum := sent - 1
				innerCtx := newCtx

				tags := stats.Tags{"operation": operationName, "is_hedge": strconv.FormatBool(isHedge)}
				if isHedge {
					innerCtx = diagnostics.WithLoggerFields(innerCtx, kvp.Int("gh.authnd.request.hedge", hedgeNum))
					diagnostics.Logger(innerCtx).Info("[Hedging] Beginning hedged operation: " + operationName)
					tags["hedge"] = strconv.Itoa(hedgeNum)
				}
				diagnostics.Statter(innerCtx).Counter("hedging.request", tags, 1)

				start := time.Now()
				err := operation(innerCtx)

				// only track the duration of primary requests (non hedges) that are successful (e.g. no error)
				if !isHedge && err == nil {
					hedgeManager.HandleOperationDuration(time.Since(start))
				}

				ch <- &hedgeData{
					err:     err,
					hedge:   hedgeNum,
					isHedge: isHedge,
				}
			}(sent)
		}

		// Proceed with whichever one is ready first:
		// 1. One of the requests has finished processing;
		// 2. Caller cancelled the context;
		// 3. Time to issue a hedged request.
		select {
		case operationHedgeData = <-ch:
			break Loop
		case <-ctx.Done():
			operationHedgeData = &hedgeData{
				err: ctx.Err(),
			}
			break Loop
		case <-time.After(timeBetweenHedges):
			continue
		}
	}

	// Cancel the slower requests and wait for threads to acknowledge
	// cancellation before closing the channel.
	cancel()
	go func() {
		wg.Wait()
		close(ch)
	}()

	// stat when the hedge "paid off" - meaning the hedge beat the original request and it was successful
	if operationHedgeData.isHedge && operationHedgeData.err == nil {
		diagnostics.Logger(ctx).Info("[Hedging] Hedged request beat the original request", kvp.Int("gh.authnd.request.hedge", operationHedgeData.hedge))
		diagnostics.Statter(ctx).Counter("hedging.paid_off", stats.Tags{"hedge": strconv.Itoa(operationHedgeData.hedge), "operation": operationName}, 1)
	}

	return operationHedgeData.err
}
