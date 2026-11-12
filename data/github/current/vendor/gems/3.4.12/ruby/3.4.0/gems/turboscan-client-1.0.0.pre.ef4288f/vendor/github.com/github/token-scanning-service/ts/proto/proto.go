package proto

import (
	"time"

	"google.golang.org/protobuf/proto" //nolint:staticcheck
	"google.golang.org/protobuf/types/known/timestamppb"
	timestamp "google.golang.org/protobuf/types/known/timestamppb"
)

// Message is a protocol buffer message.
type Message = proto.Message

// Unmarshal parses a wire-format message in b and places the decoded results in m.
func Unmarshal(b []byte, m proto.Message) error {
	return proto.Unmarshal(b, m)
}

// Marshal returns the wire-format encoding of m.
func Marshal(m proto.Message) ([]byte, error) {
	return proto.Marshal(m)
}

// Equal reports whether two messages are equal.
func Equal(x, y Message) bool {
	return proto.Equal(x, y)
}

// TimestampNow returns a google.protobuf.Timestamp for the current time.
func TimestampNow() *timestamppb.Timestamp {
	return timestamppb.Now()
}

// Timestamp converts a timestamppb.Timestamp to a time.Time.
func Timestamp(ts *timestamp.Timestamp) (time.Time, error) {
	return ts.AsTime(), nil
}

// TimestampProto converts the time.Time to a google.protobuf.Timestamp proto.
func TimestampProto(t time.Time) (*timestamp.Timestamp, error) {
	return timestamp.New(t), nil
}
