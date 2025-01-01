package aqueduct

import (
	"context"
	"sync"
	"time"

	"github.com/avast/retry-go"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
)

// NewWorker creates a new aqueduct worker.
func NewWorker(cfg WorkerConfig, client aqueduct.Client, logger log.Logger, statter stats.Client, handler aqueduct.JobHandler) (*aqueduct.Worker, error) {
	statsConfig, err := aqueduct.NewStatsConfig(aqueduct.WithStatsClient(statter))
	if err != nil {
		return nil, errors.Wrap(err, "initializing worker stats")
	}

	retrierConfig, err := aqueduct.NewRetrierConfig(
		aqueduct.WithRetryIf(func(err error) bool {
			if errors.Is(err, context.Canceled) {
				return false
			}
			return retry.DefaultRetryIf(err)
		}),
	)
	if err != nil {
		return nil, errors.Wrap(err, "initializing worker retrier")
	}

	worker, err := aqueduct.NewWorker(
		client,
		cfg.App,
		[]string{cfg.Queue},
		handler,
		aqueduct.WithLogger(logger),
		aqueduct.WithWorkerStats(statsConfig),
		aqueduct.WithRetrierConfig(retrierConfig),
	)
	if err != nil {
		return nil, errors.Wrap(err, "initializing worker")
	}

	return worker, nil
}

// Pool builds a pool of N aqueduct workers that pool in parallel for new jobs to process.
type Pool struct {
	telem       *telemetry.Provider
	worker      *aqueduct.Worker
	concurrency int
	stop        bool
	mu          sync.RWMutex
	wg          sync.WaitGroup
}

// NewPool creates a new pool of workers.
func NewPool(concurrency int, telem *telemetry.Provider, worker *aqueduct.Worker) *Pool {
	return &Pool{concurrency: concurrency, telem: telem, worker: worker}
}

// Run spawns a pool of workers that will each pool jobs and process them as specified by the given
// handler.
func (p *Pool) Run(ctx context.Context) func() {
	p.wg.Add(p.concurrency)
	for i := 0; i < p.concurrency; i++ {
		go func(workerID int) {
			defer p.wg.Done()
			// TODO(abeaumont): Add workerID to the context
			logger := p.telem.Logger.WithFields(kvp.Int("gh.notifyd.worker.id", workerID))

			for {
				p.mu.RLock()
				stopped := p.stop
				p.mu.RUnlock()
				if stopped {
					logger.WithFields(kvp.String("gh.notifyd.ctx", "shutdown")).Info("worker stopped")
					return
				}

				logger.Debug("polling for a new job")

				if err := p.worker.ProcessJob(ctx); err != nil {
					logger.WithError(err).WithFields(kvp.String("gh.notifyd.exit_reason", "received error")).Error("worker exited")
				}
			}
		}(i)
	}

	cleanup := func() {
		p.telem.Logger.Info("stopping worker pool")
		p.mu.Lock()
		p.stop = true
		p.mu.Unlock()
		p.worker.Close(5 * time.Second)
		p.telem.Logger.Info("waiting for workers to complete")
		p.wg.Wait()
	}
	return cleanup
}
