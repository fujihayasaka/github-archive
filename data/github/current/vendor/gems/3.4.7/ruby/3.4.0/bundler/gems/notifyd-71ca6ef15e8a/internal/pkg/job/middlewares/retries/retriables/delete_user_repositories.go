package retriables

import (
	"time"

	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"

	entities_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	pb "github.com/github/notifyd/hydro/schemas/notifyd/v1"
	"github.com/github/notifyd/internal/pkg/aqueduct"
)

// DeleteUserRepositories represents a retriable DeleteUserRepositories message
type DeleteUserRepositories struct {
	*pb.DeleteUserRepositories
}

// GetAttempts returns the number of attempts made to deliver
func (m *DeleteUserRepositories) GetAttempts() int32 {
	ret := m.GetRetries()
	if ret != nil {
		return ret.Attempts
	}

	return 0
}

// UpdateRetries increments the number of attempts made to deliver
func (m *DeleteUserRepositories) UpdateRetries() {
	m.Retries = &entities_pb.Retries{Attempts: m.GetAttempts() + 1}
}

// From unmarshals the message from the envelope
func (m *DeleteUserRepositories) From(envelope *hydro_pb.Envelope) error {
	msg := new(pb.DeleteUserRepositories)
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		return err
	}

	m.DeleteUserRepositories = msg

	return nil
}

// Encode encodes the message
func (m *DeleteUserRepositories) Encode() ([]byte, error) {
	encoder := hydro.NewDefaultEncoder()
	return encoder.Encode(m.DeleteUserRepositories, m.TriggeredAt())
}

// GetName returns the name of the message
func (m *DeleteUserRepositories) GetName() string {
	return "DeleteUserRepositories"
}

// HydroMessage returns the message
func (m *DeleteUserRepositories) HydroMessage() proto.Message {
	return m.DeleteUserRepositories
}

// Queue returns the queue name
func (m *DeleteUserRepositories) Queue() string {
	return aqueduct.QueueDeleteUserRepositories
}

// TriggeredAt returns the time the message was triggered
func (m *DeleteUserRepositories) TriggeredAt() time.Time {
	if m.Tracking != nil && m.Tracking.TriggeredAt != nil {
		return m.Tracking.TriggeredAt.AsTime()
	}
	return time.Now()
}
