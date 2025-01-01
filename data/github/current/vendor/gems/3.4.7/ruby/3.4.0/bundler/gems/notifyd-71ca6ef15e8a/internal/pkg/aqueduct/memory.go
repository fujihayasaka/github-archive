package aqueduct

import (
	"context"

	ghaqueduct "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/google/uuid"

	"github.com/github/notifyd/internal/pkg/errors"
)

// MemorySender implements the Sender interface for sending messages to a channel
// This is intended for testing purposes only
type MemorySender struct {
	channel chan<- ghaqueduct.Job
}

// Ensure MemorySender implements the Sender interface
var _ Sender = &MemorySender{}

// Send writes a job to a channel
// NOTE: This sender doesn't apply SendOptions. If that is needed, it would
// need to save aqueduct-proto.SendRequest structs in the channel instead
// of just jobs. For the moment that's not necessary.
func (ms *MemorySender) Send(ctx context.Context, job ghaqueduct.Job, opts ...ghaqueduct.SendOption) (_id string, err error) {
	// If sending to the channel panics, this recovers it and returns an error
	defer func() {
		if r := recover(); r != nil {
			err = errors.New("error writing to the channel").With(errors.MarkPanic())
		}
	}()

	ms.channel <- job
	return uuid.New().String(), nil
}

// BuildMemorySender creates a new MemorySender
func BuildMemorySender(channel chan<- ghaqueduct.Job) (*MemorySender, error) {
	return &MemorySender{channel}, nil
}
