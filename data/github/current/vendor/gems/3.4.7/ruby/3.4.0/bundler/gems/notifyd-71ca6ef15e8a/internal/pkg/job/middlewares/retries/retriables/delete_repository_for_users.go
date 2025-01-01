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

// DeleteRepositoryForUsers represents a retriable DeleteRepositoryForUsers message
type DeleteRepositoryForUsers struct {
	*pb.DeleteRepositoryForUsers
}

// GetAttempts returns the number of attempts made to deliver
func (m *DeleteRepositoryForUsers) GetAttempts() int32 {
	ret := m.GetRetries()
	if ret != nil {
		return ret.Attempts
	}

	return 0
}

// UpdateRetries increments the number of attempts made to deliver
func (m *DeleteRepositoryForUsers) UpdateRetries() {
	m.Retries = &entities_pb.Retries{Attempts: m.GetAttempts() + 1}
}

// From unmarshals the message from the envelope
func (m *DeleteRepositoryForUsers) From(envelope *hydro_pb.Envelope) error {
	msg := new(pb.DeleteRepositoryForUsers)
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		return err
	}

	m.DeleteRepositoryForUsers = msg

	return nil
}

// Encode encodes the message
func (m *DeleteRepositoryForUsers) Encode() ([]byte, error) {
	encoder := hydro.NewDefaultEncoder()
	return encoder.Encode(m.DeleteRepositoryForUsers, m.TriggeredAt())
}

// GetName returns the name of the message
func (m *DeleteRepositoryForUsers) GetName() string {
	return "DeleteRepositoryForUsers"
}

// HydroMessage returns the message
func (m *DeleteRepositoryForUsers) HydroMessage() proto.Message {
	return m.DeleteRepositoryForUsers
}

// Queue returns the queue to send the message to
func (m *DeleteRepositoryForUsers) Queue() string {
	return aqueduct.QueueDeleteRepositoryForUsers
}

// TriggeredAt returns the time the message was triggered
func (m *DeleteRepositoryForUsers) TriggeredAt() time.Time {
	if m.Tracking != nil && m.Tracking.TriggeredAt != nil {
		return m.Tracking.TriggeredAt.AsTime()
	}
	return time.Now()
}
