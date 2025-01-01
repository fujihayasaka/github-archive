package mysql

import (
	"math"
	"sync"
	"time"

	"github.com/influxdata/tdigest"
)

const (
	// only allow 1 hedge per mysql request
	maxHedges = 1

	// before firing off a hedge, we wait for _at least_ this many milliseconds
	// we try to determine the best value for this by calculating the 90th percentile of the
	// _primary_ operation durations that succeed. We set a minimum value for this in order to
	// protect ourselves from being too aggressive with the wait time before a hedge is fired off.
	minMillisecondsBetweenHedges = 3

	// the compression parameter for tdigest
	tdigestCompression = 1000

	// the batch size used for adding durations to tdigest
	tdigestBatchSize = 100
)

type hedgeManager struct {
	mu    sync.Mutex
	td    *tdigest.TDigest
	batch []time.Duration
}

func NewHedgeManager() *hedgeManager {
	return &hedgeManager{
		td:    tdigest.NewWithCompression(tdigestCompression),
		batch: make([]time.Duration, 0, tdigestBatchSize),
	}
}

func (hm *hedgeManager) GetWaitTime() time.Duration {
	hm.mu.Lock()
	quantile := hm.td.Quantile(0.9)
	hm.mu.Unlock()

	if math.IsNaN(quantile) {
		quantile = minMillisecondsBetweenHedges
	}
	minQuantile := math.Max(quantile, minMillisecondsBetweenHedges)
	return time.Duration(minQuantile * float64(time.Millisecond))
}

func (hm *hedgeManager) GetMaxNumberOfHedges() int {
	return maxHedges
}

func (hm *hedgeManager) HandleOperationDuration(operationDuration time.Duration) {
	hm.mu.Lock()
	defer hm.mu.Unlock()

	if len(hm.batch) > tdigestBatchSize {
		hm.handleOperationDurationBatch(hm.batch)
		hm.batch = make([]time.Duration, 0, tdigestBatchSize)
	}
	hm.batch = append(hm.batch, operationDuration)
}

func (hm *hedgeManager) handleOperationDurationBatch(durations []time.Duration) {
	for _, duration := range durations {
		hm.td.Add(float64(duration.Milliseconds()), 1)
	}
}
