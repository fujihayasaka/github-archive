package kafka

import "time"

// MessageID uniquely identifies a Kafka message.
type MessageID struct {
	Topic     string    // The topic the message belongs to
	Partition int32     // The partition the message belongs to
	Offset    int64     // The offset in the partition of the message
	Timestamp time.Time // The LogAppendTime of the message
}
