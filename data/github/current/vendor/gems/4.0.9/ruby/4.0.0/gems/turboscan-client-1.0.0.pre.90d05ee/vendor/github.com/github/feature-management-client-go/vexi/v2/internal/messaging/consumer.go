package messaging

import (
	"context"
)

// consumer is a message consumer for a single topic that consumes events for a single topic from a messaging system without a consumer group.
type consumer interface {
	// Close closes the source, blocking until all internal resources have been
	// closed.
	//
	// Any error(s) that occur during its shutdown process will be returned as an
	// ErrorList.
	//
	// It's not recommended to be called multiple times or concurrently in order to
	// best ensure the caller handles any error(s) returned during its synchronized
	// shutdown process.
	//
	// Once closed the stateless consumer can't be used again.
	Close() error

	// HighWaterMarks returns the current high water marks for each partition. This is the offset the next published message will have in each partition.
	// Consistency between partitions is not guaranteed since high water marks are updated separately.
	HighWaterMarks() (map[int32]int64, error)

	// CurrentWaterMarks returns the current local water marks for each partition. This is the offset of the last message read from each partition.
	CurrentWaterMarks(context.Context) map[int32]int64

	// ReadMessage attempts to return the next Message from one of its
	// partition subscriptions (ordering between multiple partitions is
	// non-deterministic).
	//
	// It blocks until a Message is read, the provided context is canceled, or the
	// source is closed.
	//
	// It returns the context's error when canceled/timed-out.
	//
	// When an error is returned the Message must be discarded.
	ReadMessage(ctx context.Context) (*Message, error)

	// Start subscribes to configured topic. Does nothing if already started.
	Start(ctx context.Context) error
}
