package cmd

import (
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/retry"
	"github.com/github/migrations-vnext/internal/pkg/servermigrator"
	"github.com/github/migrations-vnext/internal/pkg/wal"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type (
	// WALTarget is a migration target that instead of sending resources and events directly to
	// the target (gh/gh), it uses a Write Ahead Log (WAL) to store the resources and events,
	// which can be processed once they have been written to the WAL file.
	WALTarget struct {
		wal    *wal.Log
		target servermigrator.MigrationTargetAPI
		logger log.Logger
	}

	// processBatchFn is a function that processes a batch of events.
	processBatchFn func([]*v1.WALEvent) error
)

var (
	// Ensure WALTarget implements the MigrationTargetAPI interface.
	_ servermigrator.MigrationTargetAPI = &WALTarget{}

	// retryCfg is the backoff configuration for retrying failed requests.
	retryCfg = func() *backoff.ExponentialBackOff {
		return backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(30 * time.Minute))
	}

	// maxSendBatchSize is the maximum number of events to send in a single batch.
	maxSendBatchSize = 100
)

// NewWALTarget creates a new WALTarget.
func NewWALTarget(path string, target servermigrator.MigrationTargetAPI, logger log.Logger) (*WALTarget, error) {
	w, err := wal.New(path, &wal.Options{Logger: logger})
	if err != nil {
		return nil, fmt.Errorf("error creating wal: %w", err)
	}

	return &WALTarget{
		wal:    w,
		target: target,
		logger: logger.WithFields(kvp.String("component", "wal_target")),
	}, nil
}

// SendResources sends the resources to the WAL file for further processing.
func (w *WALTarget) SendResources(ctx context.Context, sourceURL string, resources []*v1.Resource) error {
	w.logger.Info("appending resources",
		kvp.String("source_url", sourceURL), kvp.Int("resource_count", len(resources)))

	w.wal.Append(ctx, &v1.WALEvent{Resources: resources, SourceUrl: sourceURL})
	return nil
}

// SendEvents sends the events to the WAL file for further processing.
func (w *WALTarget) SendEvents(ctx context.Context, sourceURL string, events []*v1.Event) error {
	w.logger.Info("appending events",
		kvp.String("source_url", sourceURL), kvp.Int("event_count", len(events)))

	w.wal.Append(ctx, &v1.WALEvent{Events: events, SourceUrl: sourceURL})
	return nil
}

// Run runs the WAL target. Running the WAL target involves running two
// goroutines: one that periodically writes batches to the WAL file and another that reads them.
func (w *WALTarget) Run(ctx context.Context) error {
	errC := make(chan error, 2)
	go func() { errC <- w.wal.StartWriteBatchProcessor(ctx) }()
	go func() { errC <- w.wal.ReadBatches(w.buildProcessBatchFn(ctx)) }()
	return <-errC
}

// Close closes the WAL target.
func (w *WALTarget) Close() error {
	return w.wal.Close()
}

// buildProcessBatchFn builds a processBatchFn that sends the events to the target.
func (w *WALTarget) buildProcessBatchFn(ctx context.Context) processBatchFn {
	return func(events []*v1.WALEvent) error {
		// fn is a function that sends the events to the target that will be retried
		fn := func() error { return w.send(ctx, events) }
		// cfg is the backoff configuration for retrying failed requests
		cfg := backoff.WithContext(retryCfg(), ctx)
		// execute fn with retries
		if err := retry.Retry(fn, cfg, w.logger); err != nil {
			return fmt.Errorf("error sending events to target after retries: %w", err)
		}
		return nil
	}
}

// send sends a batch of events to the target in chunks of at most maxSendBatchSize events.
func (w *WALTarget) send(ctx context.Context, events []*v1.WALEvent) error {
	for chunk := range slices.Chunk(events, maxSendBatchSize) {
		var resources []*v1.Resource
		var events []*v1.Event
		var sourceURL string

		for _, e := range chunk {
			resources = append(resources, e.Resources...)
			events = append(events, e.Events...)
			if sourceURL == "" {
				sourceURL = e.SourceUrl
			}
		}

		if len(resources) > 0 {
			if err := w.target.SendResources(ctx, sourceURL, resources); err != nil {
				return fmt.Errorf("error sending resources to target: %w", err)
			}
		}
		if len(events) > 0 {
			if err := w.target.SendEvents(ctx, sourceURL, events); err != nil {
				return fmt.Errorf("error sending events to target: %w", err)
			}
		}
	}
	return nil
}
