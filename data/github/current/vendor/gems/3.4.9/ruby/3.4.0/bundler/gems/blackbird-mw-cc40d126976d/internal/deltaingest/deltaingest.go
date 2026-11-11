// Package deltaingest provides the ability to consume events from Kafka and
// concurrently crawl repositories to ingest content into blackbird.
package deltaingest

import (
	"context"
	"time"

	"github.com/github/blackbird-mw/internal/crawl"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/utils"
)

// The maximum number of times to attempt to ingest a repository (barring
// special handling of specific errors).
const defaultMaxIngestAttempts = 3

// RunWorkPool is the main entry point to start the Kafka consume loop and a
// pool of ingest workers (one worker can process a single repo at a time).
//
// Messages are received, decoded, and then queued up for the workers to
// process. Kafka offsets are managed by only committing offsets for messages
// that have been successfully processed.
//
// Any error from a worker task will shutdown the entire pool and exit the
// consume loop. This is to avoid advancing Kafka offsets.
func RunWorkPool(
	ctx context.Context,
	numWorkers int,
	corpus routing.Corpus,
	topicConfig routing.TopicConfig,
	store db.Store,
	consumer kafka.IngestConsumer,
	githubClient github.InternalAPIClient,
	gitClient gitaccess.Client,
	cacheClusters *routing.CacheClusters,
	indexerCluster *routing.IndexerCluster,
	stamp routing.Stamp,
) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	// Create a work pool of document crawlers.
	const crawlWorkers = 512
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, crawlWorkers, corpus)
	defer crawlPool.Close()

	// numWorkers defines the number of repos that can be ingested concurrently.
	// maxConcurrentTasks should be at least numWorkers, but can be even greater.
	maxConcurrentTasks := numWorkers * 10

	offsetTracker := kafka.NewOffsetTracker(consumer)

	// Create the ingest work pool and the innermost ingest operation.
	inner := NewIndexAPIIngestOp(offsetTracker, crawlPool, githubClient, gitClient, store, indexerCluster, topicConfig, defaultMaxIngestAttempts)
	workPool := NewWorkPoolOp(ctx, maxConcurrentTasks, numWorkers, inner)
	defer workPool.Close()

	// Create the app (a nested stack of task operations)
	app :=
		NewAbortableOp(
			cancel,
			maxConcurrentTasks,
			NewLoggingContextOp(
				NewOffsetTrackingOp(
					offsetTracker,
					NewPriorBackfillFilterOp(
						NewAncestorCheckOp(
							NewDebounceReposOp(
								NewAncestorOrderingOp(workPool),
							),
						),
					),
				),
			),
		)

	// Kafka consume loop
	go func() {
		defer utils.PanicLogger(ctx)

		for {
			task, err := read(ctx, consumer, stamp)
			if err != nil {
				app.Abort(err)
				return
			}

			app.Run(task)
		}
	}()

	// Periodic source Kafka offset reporting
	offsetReporter := newOffsetReporter(indexerCluster, offsetTracker)
	go func() {
		defer utils.PanicLogger(ctx)

		// NOTE: Our stale ingest alert will fire if source kafka offsets are > 1 hour behind committed Kafka offsets.
		ticker := time.NewTicker(1 * time.Minute)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				err := offsetReporter.sendConsumedOffsets(ctx)
				if err != nil {
					cancel()
					return
				}
			case <-ctx.Done():
				return
			}
		}
	}()

	return app.Wait()
}

func read(ctx context.Context, consumer kafka.IngestConsumer, stamp routing.Stamp) (*Task, error) {
	msg, state, err := consumer.ReadMessage(ctx)
	if err != nil {
		return nil, err
	}

	return NewTask(ctx, msg, state, stamp)
}
