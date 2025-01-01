package queueworker

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"

	aq "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/clock"
)

// Config denotes configuration required for a QueueWorker
//
//revive:disable-next-line:exported
type QueueWorkerConfig struct {
	LaunchEnv             string
	AqueductApp           string
	AqueductURL           string
	AqueductAPIKey        string
	AqueductAPIKeyVersion int
	AqueductQueues        []string
	AqueductTimeoutMs     int32
	AqueductWorkerPool    string

	NumWorkers int
	// How frequently do we attempt to send a heartbeat to aqueduct while processing a job?
	HeartbeatAttemptInterval time.Duration
	// How frequently do heartbeat attempts need to be successful?
	MaxTimeWithoutHeartbeat time.Duration
	IsMultiTenant           bool
}

// QueueWorker works an aqueduct queue.
type QueueWorker struct {
	cfg                   QueueWorkerConfig
	aqueductClientFactory aqueduct.Factory
	jobProcessor          JobProcessor
	obs                   *observability.Observability
	breaker               *circuit.Breaker
	done                  *int32
	graceful              chan bool
}

// New returns a Service for pulling jobs from Aqueduct and running them.
func New(cfg QueueWorkerConfig, jp JobProcessor, obs *observability.Observability, breaker *circuit.Breaker, aqueuductClientFactory aqueduct.Factory) (*QueueWorker, error) {
	var done int32

	return &QueueWorker{
		aqueductClientFactory: aqueuductClientFactory,
		cfg:                   cfg,
		jobProcessor:          jp,
		obs:                   obs,
		breaker:               breaker,
		done:                  &done,
		graceful:              make(chan bool),
	}, nil
}

// Run starts the QueueWorker, which will run cfg.NumWorkers different goroutines each processing the queue.
func (q *QueueWorker) Run(ctx context.Context) error {
	defer func() { close(q.graceful) }()

	var wg sync.WaitGroup

	for i := 0; i < q.cfg.NumWorkers; i++ {
		wg.Add(1)
		q.obs.Log(ctx, fmt.Sprintf("QueueWorker starting worker %d", i))

		clientOptions := &aqueduct.ClientOptions{
			App:           q.cfg.AqueductApp,
			URL:           q.cfg.AqueductURL,
			APIKey:        q.cfg.AqueductAPIKey,
			APIKeyVersion: q.cfg.AqueductAPIKeyVersion,
			WorkerID:      i,
		}
		client, err := q.aqueductClientFactory.NewClient(q.obs.Statter, q.breaker, clientOptions)
		if err != nil {
			return errors.Wrap(err, "error creating Aqueduct client")
		}

		w := &worker{
			cfg:   q.cfg,
			ID:    aq.NewWorkerMetadata(q.cfg.AqueductWorkerPool).ID,
			obs:   q.obs,
			aq:    client,
			jp:    q.jobProcessor,
			clock: clock.New(),
		}

		go func(ctx context.Context, w *worker) {
			queues := strings.Join(q.cfg.AqueductQueues, "|")

			for ctx.Err() == nil && !q.stop() { // Loop until we are triggered to stop
				start := time.Now()

				wCtx := appcontext.CopyRequestMetadata(ctx)
				res, nextRecvAt := w.Work(wCtx)
				tags := statter.Tags{"result": string(res), "queues": queues}
				q.obs.Timing(ctx, "queue.service.worker_loop", tags, time.Since(start))

				if backoff := time.Until(nextRecvAt); backoff > 0 && !q.stop() {
					w.Wait(wCtx, backoff)

					// emitting the same metric for backoff enables us to determine the percentage of time workers are active
					tags := statter.Tags{"result": "backoff", "queues": queues}
					q.obs.Timing(ctx, "queue.service.worker_loop", tags, backoff)
				}
			}

			wg.Done() // We've stopped, decrement the waitgroup

		}(ctx, w)
	}

	wg.Wait()

	return nil
}

// Shutdown stops the QueueWorker, ideally gracefully, but with context cancellation as fallback.
func (q *QueueWorker) Shutdown(ctx context.Context) error {
	atomic.AddInt32(q.done, 1)

GracefulLoop:
	for {
		select {
		case <-ctx.Done():
			q.obs.Log(ctx, "QueueWorker shutdown triggered by context cancel")
			return ctx.Err()

		case <-q.graceful:
			q.obs.Log(ctx, "QueueWorker shutdown triggered gracefully")
			break GracefulLoop
		}
	}

	return nil
}

func (q *QueueWorker) stop() bool {
	return atomic.LoadInt32(q.done) > 0
}
