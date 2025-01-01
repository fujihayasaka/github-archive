// Package eventworker contains the business logic for processing events.
package eventworker

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/events"
	"github.com/github/migrations-vnext/internal/pkg/kafka"
	"github.com/github/migrations-vnext/internal/pkg/migrationctx"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// EventWorker is a struct which contains the business logic for processing events
type EventWorker struct {
	loader             events.Loader
	consumer           kafka.Consumer
	dag                dag.DAG
	logger             log.Logger
	statter            stats.Client
	deadLetterProducer kafka.Producer
}

// nowFn is a function that returns the current time and can be overidden in tests.
var nowFn = time.Now

// New creates a new EventWorker
func New(loader events.Loader, consumer kafka.Consumer, d dag.DAG, logger log.Logger, statter stats.Client, dlProducer kafka.Producer) *EventWorker {
	return &EventWorker{
		loader:             loader,
		consumer:           consumer,
		dag:                d,
		logger:             logger,
		statter:            statter,
		deadLetterProducer: dlProducer,
	}
}

func (w *EventWorker) processEvent(ctx context.Context, msg []byte) error {
	var event v1.Event
	if err := proto.Unmarshal(msg, &event); err != nil {
		return fmt.Errorf("failed to unmarshal failed resource: %w", err)
	}
	ns, err := migrationctx.Namespace(&event)
	if err != nil {
		return fmt.Errorf("failed to get namespace: %w", err)
	}

	logger := w.logger.WithFields(kvp.String("id", event.EventId),
		kvp.String("namespace", ns),
		kvp.String("resource_id", event.ResourceId),
		kvp.String("action", event.EventAction.String()))

	logger.Info("processing event")

	if err = w.loader.LoadEvent(ctx, &event); err != nil {
		if !isTwirpOutdatedError(err) {
			return w.handleError(ctx, &event, err)
		}
		logger.Warn("twirp request was skipped due to outdated event")
	}

	if err := w.dag.MarkAsProcessed(ctx, ns, []dag.Node{{ID: dag.ID(event.EventId), Kind: dag.EventNode}}); err != nil {
		return fmt.Errorf("failed to mark event %s as processed: %w", event.EventId, err)
	}

	return nil
}

func (w *EventWorker) handleError(ctx context.Context, e *v1.Event, err error) error {
	// Dead Letter Producer is not configured.
	if w.deadLetterProducer == nil {
		return fmt.Errorf("failed to process event: %w", err)
	}
	toDL := shouldSendToDeadLetter(err)
	w.logger.WithError(err).Error("failed to process event", kvp.Bool("to_dead_letter", toDL))

	if !toDL {
		return fmt.Errorf("failed to process event: %w", err)
	}

	failedEvent := v1.FailedEvent{
		ErrorMessage: err.Error(),
		FailedAt:     timestamppb.New(nowFn()),
		Event:        e,
	}
	bs, err := proto.Marshal(&failedEvent)
	if err != nil {
		return fmt.Errorf("failed to marshal failed event: %w", err)
	}

	if err := w.deadLetterProducer.Produce(ctx, bs); err != nil {
		return fmt.Errorf("failed to send resource to dead letter: %w", err)
	}

	return nil
}

// shouldSendToDeadLetter returns true if the error should be sent to the dead letter queue.
// For now, we only send:
//   - Twirp errors that are not a 'Canceled' error
func shouldSendToDeadLetter(err error) bool {
	var (
		twErr twirp.Error
	)
	switch {
	case errors.As(err, &twErr):
		return twErr.Code() != twirp.Canceled
	default:
		return false
	}
}

// Run starts the event worker
func (w *EventWorker) Run(ctx context.Context) error {
	return w.consumer.Consume(ctx, w.processEvent)
}

// isTwirpOutdatedError returns true if the error is a twirp.Canceled error with
// an octoshift_error_code of OUTDATED_UPDATED_AT.
func isTwirpOutdatedError(err error) bool {
	var twerr twirp.Error
	if !errors.As(err, &twerr) {
		return false
	}
	if twerr.Code() != twirp.Canceled {
		return false
	}
	return twerr.Meta("octoshift_error_code") == "OUTDATED_UPDATED_AT"
}
