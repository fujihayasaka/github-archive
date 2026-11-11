// Package messaging contains the models and interfaces for interacting with the messaging system.
package messaging

import "time"

const (
	// OffsetNewest is a special offset value that means the newest message
	// available on the topic at the time the message is received.
	OffsetNewest offset = offset(-1)

	// OffsetOldest is a special offset value that means the oldest message
	// available on the topic at the time the message is received.
	OffsetOldest offset = offset(-2)
)

// Message represents the metadata and payload of a message used in the messaging system.
type Message struct {
	Topic     string
	Key       []byte
	Value     []byte
	Partition int32
	Offset    int64
	Timestamp time.Time
	Headers   map[string]string
	Metadata  *PartitionerMetadata
}

// PartitionerMetadata contains optional Message metadata fields used to
// control Sink partitioning behavior.
type PartitionerMetadata struct {
	Partition    *int32 `json:"partition,omitempty"`
	PartitionKey []byte `json:"partitionKey,omitempty"`
}

type offset int64
