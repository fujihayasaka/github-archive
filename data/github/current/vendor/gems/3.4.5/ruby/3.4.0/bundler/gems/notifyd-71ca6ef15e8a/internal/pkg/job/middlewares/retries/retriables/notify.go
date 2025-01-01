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

// Notify represents a retriable Notify message
type Notify struct {
	*pb.Notify
}

// GetAttempts returns the number of attempts made to deliver
func (m *Notify) GetAttempts() int32 {
	if ret := m.GetRetries(); ret != nil {
		return ret.Attempts
	}

	return 0
}

// UpdateRetries increments the number of attempts made to deliver
func (m *Notify) UpdateRetries() {
	m.Retries = &entities_pb.Retries{Attempts: m.GetAttempts() + 1}
}

// From unmarshals the message from the envelope
func (m *Notify) From(envelope *hydro_pb.Envelope) error {
	msg := new(pb.Notify)
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		return err
	}

	m.Notify = msg

	return nil
}

// Encode encodes the message
func (m *Notify) Encode() ([]byte, error) {
	encoder := hydro.NewDefaultEncoder()
	return encoder.Encode(m.Notify, m.TriggeredAt())
}

// GetName returns the name of the message
func (m *Notify) GetName() string {
	return "Notify"
}

// HydroMessage returns the message
func (m *Notify) HydroMessage() proto.Message {
	return m.Notify
}

// Queue returns the queue name
func (m *Notify) Queue() string {
	return aqueduct.QueueNotify
}

// TriggeredAt returns the time the message was triggered
func (m *Notify) TriggeredAt() time.Time {
	if m.Tracking != nil && m.Tracking.TriggeredAt != nil {
		return m.Tracking.TriggeredAt.AsTime()
	}
	return time.Now()
}
