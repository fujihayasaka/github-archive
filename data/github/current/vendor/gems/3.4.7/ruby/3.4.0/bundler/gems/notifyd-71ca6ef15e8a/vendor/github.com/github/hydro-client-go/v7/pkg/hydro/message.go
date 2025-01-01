package hydro

import "time"

// Message represents a serialized Hydro event used for producing with a Sink
// and consuming with a Source.
type Message struct {
	Topic     string               `json:"topic"`
	Key       []byte               `json:"key,omitempty"`
	Value     []byte               `json:"value"`
	Partition int32                `json:"partition"`
	Offset    int64                `json:"offset"`
	Timestamp time.Time            `json:"timestamp"`
	Headers   map[string]string    `json:"headers"`
	Metadata  *PartitionerMetadata `json:"metadata,omitempty"`
}

// PartitionerMetadata contains optional Message metadata fields used to
// control Sink partitioning behavior.
type PartitionerMetadata struct {
	Partition    *int32 `json:"partition,omitempty"`
	PartitionKey []byte `json:"partitionKey,omitempty"`
}
