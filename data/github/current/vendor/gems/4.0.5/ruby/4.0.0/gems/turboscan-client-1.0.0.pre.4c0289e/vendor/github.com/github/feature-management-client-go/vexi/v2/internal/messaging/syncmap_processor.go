package messaging

import (
	"context"
	"errors"
	"time"

	vexi_errors "github.com/github/feature-management-client-go/vexi/v2/errors"
	"github.com/github/feature-management-client-go/vexi/v2/internal"

	"github.com/github/feature-management-client-go/vexi/v2/internal/telemetry"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

const (
	// spanAttrEntityType is the log field for the entity type which can either be "feature-flag" or "segment".
	spanAttrEntityType = "gh.vexi.entity.type"

	// spanAttrMessageKey is the log field for the hydro message key.
	spanAttrMessageKey = "gh.vexi.message.key"

	// spanAttrMessageOffset is the log field for the hydro message offset.
	spanAttrMessageOffset = "gh.vexi.message.offset"

	// spanAttrMessagePartition is the log field for the hydro message partition.
	spanAttrMessagePartition = "gh.vexi.message.partition"

	// AllPartitions is a constant that can be used to indicate that all partitions should be consumed.
	AllPartitions = -1
)

// SyncMapProcessor is a service that consumes messages from the provided consumer and updates the entities in a sync map. It calls the provided caughtUpFunc when it has caught up
// to the latest that had been published up to the time it started.
type SyncMapProcessor struct {
	t                  internal.Telemetry
	entityType         string
	consumer           consumer
	caughtUpNotifier   CaughtUpNotifier
	caughtUp           bool
	highWaterMarks     map[int32]int64
	started            bool
	entityUpdater      EntityUpdater
	targetPartitionIDs map[int32]bool
}

// EntityUpdater is an interface used by the syncMapProcessor to update and store the entities.
type EntityUpdater interface {
	UpdateEntity(ctx context.Context, key, data []byte, updateTimestamp time.Time) error
}

// CaughtUpNotifier is an interface used by the entityMessageProcessor to notify when it has caught up to the latest messages across all partitions.
type CaughtUpNotifier interface {
	NotifyCaughtUp(ctx context.Context)
}

// NewSyncMapProcessor creates a new SyncMapProcessor instance.
func NewSyncMapProcessor(t internal.Telemetry, consumer consumer, entityType string, targetPartitionIDs map[int32]bool, entityUpdater EntityUpdater, caughtUpNotifier CaughtUpNotifier) *SyncMapProcessor {
	return &SyncMapProcessor{
		t:                  t,
		entityType:         entityType,
		consumer:           consumer,
		entityUpdater:      entityUpdater,
		targetPartitionIDs: targetPartitionIDs,
		caughtUpNotifier:   caughtUpNotifier,
	}
}

// Start starts the consumer and records the high water marks at the time of starting. This must be called before ConsumeMessages.
func (s *SyncMapProcessor) Start(ctx context.Context) error {
	// Start the consumer.
	if err := s.consumer.Start(ctx); err != nil {
		return vexi_errors.NewWrappedError(err, "failed to start consumer")
	}

	// Get the consumer's high watermarks.
	waterMarks, err := s.consumer.HighWaterMarks()
	if err != nil {
		return vexi_errors.NewWrappedError(err, "failed to get high water marks")
	}

	// Set the high water marks.
	s.highWaterMarks = waterMarks
	s.started = true

	return nil
}

// ConsumeMessages consumes messages from the provided consumer and updates the entity. It continues to wait for messagested until the provided context is canceled. Ensure that start is called before calling this method.
func (s *SyncMapProcessor) ConsumeMessages(ctx context.Context) {
	if !s.started {
		panic("consumeMessages called on sync map processor before start")
	}

	// This checks for the corner case where no messages exist in the topic.
	if s.compareWaterMarks(s.consumer.CurrentWaterMarks(ctx), s.targetPartitionIDs) {
		s.caughtUp = true
		s.caughtUpNotifier.NotifyCaughtUp(ctx)
	}

	for {
		select {
		case <-ctx.Done():
			return
		default:
			abort := s.readAndProcessMessage(ctx)
			if abort {
				return
			}
		}
	}
}

// readAndProcessMessage reads a message from the consumer and updates the entity. The only error it returns is context.Canceled which indicates the for loop in ConsumeMessages should exit.
func (s *SyncMapProcessor) readAndProcessMessage(ctx context.Context) bool {
	msg, err := s.consumer.ReadMessage(ctx)
	if err != nil {
		// If context is canceled return.
		if errors.Is(err, context.Canceled) {
			return true
		}

		// In case of any other type of error continue listening for messages.
		s.t.LogWithError(ctx, err, "error reading message")
		s.t.MetricCounter(ctx, "vexi_sync_map_processor.read_message_error", nil, 1)
		return false
	}

	// Start a trace.
	ctx, span := s.t.StartTrace(ctx,
		"process "+msg.Topic,
		trace.WithSpanKind(trace.SpanKindConsumer),
		trace.WithAttributes(
			attribute.String(spanAttrEntityType, s.entityType),
			attribute.String(spanAttrMessageKey, string(msg.Key)),
			attribute.Int64(spanAttrMessageOffset, msg.Offset),
			attribute.Int64(spanAttrMessagePartition, int64(msg.Partition)),
		))
	defer span.End()

	// Update the entity.
	if err := s.entityUpdater.UpdateEntity(ctx, msg.Key, msg.Value, msg.Timestamp); err != nil {
		// If context is canceled return.
		if errors.Is(err, context.Canceled) {
			telemetry.SetSpanStatus(ctx, codes.Ok, "context canceled")
			return true
		}

		offsetField := zap.Int64("offset", msg.Offset)
		partitionField := zap.Int32("partition", msg.Partition)
		s.t.LogWithError(ctx, err, "error updating entity for message", offsetField, partitionField)

		telemetry.RecordErrorToSpan(ctx, err)
		telemetry.SetSpanStatus(ctx, codes.Error, err.Error())
		s.t.MetricCounter(ctx, "vexi_message_processor.update_entity_error", nil, 1)

		// Despite not being able to update the entity check if we have caught up to the latest message.
		if !s.caughtUp && s.compareWaterMarks(s.consumer.CurrentWaterMarks(ctx), s.targetPartitionIDs) {
			s.caughtUp = true
			s.caughtUpNotifier.NotifyCaughtUp(ctx)
		}
		return false
	}

	// Check if we have caught up to the latest message.
	if !s.caughtUp && s.compareWaterMarks(s.consumer.CurrentWaterMarks(ctx), s.targetPartitionIDs) {
		s.caughtUp = true
		s.caughtUpNotifier.NotifyCaughtUp(ctx)
	}

	s.t.MetricCounter(ctx, telemetry.HydroAdapterUpdateSuccess, nil, 1)
	telemetry.SetSpanStatus(ctx, codes.Ok, "success")
	return false
}

// CompareWaterMarks compares the current water marks with the high water marks for the target partitions. If any current water mark is less than the corresponding high water mark then it returns false.
func (s *SyncMapProcessor) compareWaterMarks(currentWaterMarks map[int32]int64, targetPartitionIDs map[int32]bool) bool {
	for partition, partitionHighWaterMark := range s.highWaterMarks {
		// Unless we are consuming all partitions we should only consider the target partitions.
		if !targetPartitionIDs[AllPartitions] && !targetPartitionIDs[partition] {
			continue
		}

		// If the high water mark for a partition is 0 then we have caught up with that partition regardless of the current water mark.
		if partitionHighWaterMark == 0 {
			continue
		}

		offsetToCatchUpTo := partitionHighWaterMark - 1
		currentWaterMark, ok := currentWaterMarks[partition]
		// High water marks are the offset of the next message to be published whereas current water marks are the offset of the last message read. Hence the -1.
		if !ok || currentWaterMark < offsetToCatchUpTo {
			return false
		}
	}

	return true
}
