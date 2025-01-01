package eventworker

import (
	"context"
	"fmt"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/delayedctx"
	"github.com/github/migrations-vnext/internal/pkg/events"
	"github.com/github/migrations-vnext/internal/pkg/kafka"
	"github.com/github/migrations-vnext/internal/pkg/retry"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// DeadLetterWorker produces and consumes from the dead letter queue for failed events.
type DeadLetterWorker struct {
	loader   events.Loader
	consumer kafka.Consumer
	producer kafka.Producer
	dag      dag.DAG
	logger   log.Logger
	statter  stats.Client
	// backoffPolicy is the backoff policy to use when retrying to load a resource
	backoffPolicy retry.BackoffPolicyFn
	waitIteration time.Duration

	// firstEvent is the first failed event that was processed.
	// It is used to determine if we are done going through all the resources.
	firstEvent *v1.FailedEvent
}

// NewDeadLetterWorker creates an initialized DeadLetterWorker.
func NewDeadLetterWorker(loader events.Loader, consumer kafka.Consumer, producer kafka.Producer, d dag.DAG, logger log.Logger, statter stats.Client) *DeadLetterWorker {
	return &DeadLetterWorker{
		loader:   loader,
		consumer: consumer,
		producer: producer,
		dag:      d,
		logger:   logger.WithFields(kvp.String("component", "event-deadletter-worker")),
		statter:  statter,
		backoffPolicy: func() backoff.BackOff {
			return backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(1 * time.Second))
		},
		waitIteration: time.Minute * 1,
	}
}

func (w *DeadLetterWorker) processEvent(ctx context.Context, msg []byte) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}

	var e v1.FailedEvent
	if err := proto.Unmarshal(msg, &e); err != nil {
		return fmt.Errorf("failed to unmarshal failed event: %w", err)
	}

	// Check if we have completed an iteration, i.e: we have retried all the failed resources,
	// and the current resource is the first failed resource that we saw.
	if proto.Equal(w.firstEvent, &e) {
		w.logger.Info("all failed events have been retried, waiting before starting a new iteration")
		select {
		case <-time.After(w.waitIteration):
		case <-ctx.Done():
			return ctx.Err()
		}
		w.firstEvent = nil
	}

	logger := w.logger.WithFields(kvp.String("event", e.String()))
	logger.Info("processing event")

	delayedCtx, cancel := delayedctx.WithDelayedCancelContext(ctx, 5*time.Second)
	defer cancel()

	loadFn := func() error { return w.loader.LoadEvent(delayedCtx, e.Event) }
	backOffCtx := backoff.WithContext(w.backoffPolicy(), delayedCtx)
	if err := retry.Retry(loadFn, backOffCtx, logger); err != nil {
		return w.handleError(ctx, &e, err)
	}

	if proto.Equal(w.firstEvent, &e) {
		w.firstEvent = nil
	}

	return nil
}

func (w *DeadLetterWorker) handleError(ctx context.Context, e *v1.FailedEvent, err error) error {
	failedEvent := v1.FailedEvent{
		ErrorMessage:     err.Error(),
		FailedAt:         timestamppb.New(nowFn()),
		RetriesAttempted: e.RetriesAttempted + 1,
		Event:            e.Event,
	}
	bs, err := proto.Marshal(&failedEvent)
	if err != nil {
		return fmt.Errorf("failed to marshal failed event: %w", err)
	}

	if err := w.producer.Produce(ctx, bs); err != nil {
		return fmt.Errorf("failed to send resource to dead letter: %w", err)
	}

	if w.firstEvent == nil {
		w.firstEvent = &failedEvent
	}

	return nil
}

// Run starts the worker.
func (w *DeadLetterWorker) Run(ctx context.Context) error {
	return w.consumer.Consume(ctx, w.processEvent)
}
