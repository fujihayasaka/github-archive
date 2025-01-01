// Package helpers provides helper functions for testing.
package helpers

import (
	"testing"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	v1 "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
	protobuf "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
)

// NewEnvelopeFromProtoMessage creates a hydro Envelope from a proto message.
func NewEnvelopeFromProtoMessage(t *testing.T, msg protoreflect.ProtoMessage) *v1.Envelope {
	t.Helper()

	value, err := hydro.NewDefaultEncoder().Encode(msg, time.Now())
	require.NoError(t, err)

	var envelope v1.Envelope
	err = protobuf.Unmarshal(value, &envelope)
	require.NoError(t, err)
	return &envelope
}

// NewAqueductJobFromProtoMessage creates an aqueduct job from a proto message.
// This is useful for testing handlers that receive messages from the aqueduct bridge.
func NewAqueductJobFromProtoMessage(t *testing.T, msg protoreflect.ProtoMessage) *aqueduct.Job {
	t.Helper()

	envelope := NewEnvelopeFromProtoMessage(t, msg)
	envelopeBytes, err := protobuf.Marshal(envelope)
	require.NoError(t, err)

	job := &aqueduct.Job{Payload: envelopeBytes}
	return job
}

// LockUUIDGeneration is a helper function to ensure that UUIDs are generated deterministically for tests.
func LockUUIDGeneration() {
	uuid.SetRand(&deterministicReader{})
}

// deterministicReader is a reader that always returns the same byte.
type deterministicReader struct{}

// Read always returns the same byte.
func (r *deterministicReader) Read(p []byte) (n int, err error) {
	for i := range p {
		p[i] = byte(i % 256)
	}
	return len(p), nil
}

// ResetUUIDGeneration is a helper function to reset UUID generation to use the default generator function.
func ResetUUIDGeneration() {
	uuid.SetRand(nil)
}
