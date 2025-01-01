// Package testhelper contains test helpers for the job package.
package testhelper

import (
	"context"
	"time"

	"google.golang.org/protobuf/proto"

	"github.com/github/notifyd/internal/pkg/job"
)

// TinyRequest represents a small request type for testing purposes
// The payload should be the bytes of a protobuf message
// after marshalling it with proto.Marshal
type TinyRequest struct {
	start   time.Time
	payload []byte
}

// NewTinyRequest creates a new TinyRequest
func NewTinyRequest(start time.Time, msg proto.Message) (*TinyRequest, error) {
	payload, err := proto.Marshal(msg)
	if err != nil {
		return nil, err
	}

	return &TinyRequest{
		start:   start,
		payload: payload,
	}, nil
}

// UnmarshalMessage unmarshals the payload into a protobuf message
func (t *TinyRequest) UnmarshalMessage(msg proto.Message) error {
	return proto.Unmarshal(t.payload, msg)
}

// Elapsed returns the time since the request was created
func (t *TinyRequest) Elapsed() time.Duration {
	return time.Since(t.start)
}

// Payload returns the payload
func (t *TinyRequest) Payload() []byte {
	return t.payload
}

// SetPayload sets the payload
func (t *TinyRequest) SetPayload(payload []byte) {
	t.payload = payload
}

// Headers returns the headers
func (t *TinyRequest) Headers() *job.Headers {
	return nil
}

// HydroOffset returns the hydro offset
func (t *TinyRequest) HydroOffset(ctx context.Context) int64 {
	return 0
}

// HydroTopic returns the hydro topic
func (t *TinyRequest) HydroTopic(ctx context.Context) string {
	return "test"
}

// HydroPartition returns the hydro partition
func (t *TinyRequest) HydroPartition(ctx context.Context) int64 {
	return 1
}
