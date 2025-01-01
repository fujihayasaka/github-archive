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

// MobilePush represents a retriable MobilePush message
type MobilePush struct {
	*pb.DeliverMobilePush
}

// GetAttempts returns the number of attempts made to deliver
func (m *MobilePush) GetAttempts() int32 {
	ret := m.GetRetries()
	if ret != nil {
		return ret.Attempts
	}

	return 0
}

// UpdateRetries increments the number of attempts made to deliver
func (m *MobilePush) UpdateRetries() {
	m.Retries = &entities_pb.Retries{Attempts: m.GetAttempts() + 1}
}

// From unmarshals the message from the envelope
func (m *MobilePush) From(envelope *hydro_pb.Envelope) error {
	msg := new(pb.DeliverMobilePush)
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		return err
	}

	m.DeliverMobilePush = msg

	return nil
}

// Encode encodes the message
func (m *MobilePush) Encode() ([]byte, error) {
	encoder := hydro.NewDefaultEncoder()
	return encoder.Encode(m.DeliverMobilePush, m.TriggeredAt())
}

// GetName returns the name of the message
func (m *MobilePush) GetName() string {
	return "DeliverMobilePush"
}

// HydroMessage returns the message
func (m *MobilePush) HydroMessage() proto.Message {
	return m.DeliverMobilePush
}

// Queue returns the queue to deliver the message to
func (m *MobilePush) Queue() string {
	return aqueduct.QueueDeliverMobilePush
}

// TriggeredAt returns the time the message was triggered
func (m *MobilePush) TriggeredAt() time.Time {
	if m.Tracking != nil && m.Tracking.TriggeredAt != nil {
		return m.Tracking.TriggeredAt.AsTime()
	}
	return time.Now()
}
