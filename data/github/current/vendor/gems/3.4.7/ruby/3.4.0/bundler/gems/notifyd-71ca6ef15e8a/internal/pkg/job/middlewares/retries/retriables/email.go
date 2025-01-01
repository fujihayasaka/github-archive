package retriables

import (
	"time"

	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"

	pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	entities_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/pkg/aqueduct"
)

// Email represents a retriable DeliverEmail message
type Email struct {
	*pb.DeliverEmail
}

// GetAttempts returns the number of attempts made to deliver
func (m *Email) GetAttempts() int32 {
	ret := m.GetRetries()
	if ret != nil {
		return ret.Attempts
	}

	return 0
}

// UpdateRetries increments the number of attempts made to deliver
func (m *Email) UpdateRetries() {
	m.Retries = &entities_pb.Retries{Attempts: m.GetAttempts() + 1}
}

// From unmarshals the message from the envelope
func (m *Email) From(envelope *hydro_pb.Envelope) error {
	msg := new(pb.DeliverEmail)
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		return err
	}

	m.DeliverEmail = msg

	return nil
}

// Encode encodes the message
func (m *Email) Encode() ([]byte, error) {
	encoder := hydro.NewDefaultEncoder()
	return encoder.Encode(m.DeliverEmail, m.TriggeredAt())
}

// GetName returns the name of the message
func (m *Email) GetName() string {
	return "DeliverEmail"
}

// HydroMessage returns the message
func (m *Email) HydroMessage() proto.Message {
	return m.DeliverEmail
}

// Queue returns the queue to deliver the message to
func (m *Email) Queue() string {
	return aqueduct.QueueDeliverEmail
}

// TriggeredAt returns the time the message was triggered
func (m *Email) TriggeredAt() time.Time {
	if m.Tracking != nil && m.Tracking.TriggeredAt != nil {
		return m.Tracking.TriggeredAt.AsTime()
	}
	return time.Now()
}
