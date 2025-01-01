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

// DeleteUser represents a retriable DeleteUser message
type DeleteUser struct {
	*pb.DeleteUser
}

// GetAttempts returns the number of attempts made to deliver
func (m *DeleteUser) GetAttempts() int32 {
	ret := m.GetRetries()
	if ret != nil {
		return ret.Attempts
	}

	return 0
}

// UpdateRetries increments the number of attempts made to deliver
func (m *DeleteUser) UpdateRetries() {
	m.Retries = &entities_pb.Retries{Attempts: m.GetAttempts() + 1}
}

// From unmarshals the message from the envelope
func (m *DeleteUser) From(envelope *hydro_pb.Envelope) error {
	msg := new(pb.DeleteUser)
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		return err
	}

	m.DeleteUser = msg

	return nil
}

// Encode encodes the message
func (m *DeleteUser) Encode() ([]byte, error) {
	encoder := hydro.NewDefaultEncoder()
	return encoder.Encode(m.DeleteUser, m.TriggeredAt())
}

// GetName returns the name of the message
func (m *DeleteUser) GetName() string {
	return "DeleteUser"
}

// HydroMessage returns the message
func (m *DeleteUser) HydroMessage() proto.Message {
	return m.DeleteUser
}

// Queue returns the queue name
func (m *DeleteUser) Queue() string {
	return aqueduct.QueueDeleteUser
}

// TriggeredAt returns the time the message was triggered
func (m *DeleteUser) TriggeredAt() time.Time {
	if m.Tracking != nil && m.Tracking.TriggeredAt != nil {
		return m.Tracking.TriggeredAt.AsTime()
	}
	return time.Now()
}
