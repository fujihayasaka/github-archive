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

// DeleteRepository represents a retriable DeleteRepository message
type DeleteRepository struct {
	*pb.DeleteRepository
}

// GetAttempts returns the number of attempts made to deliver
func (m *DeleteRepository) GetAttempts() int32 {
	ret := m.GetRetries()
	if ret != nil {
		return ret.Attempts
	}

	return 0
}

// UpdateRetries increments the number of attempts made to deliver
func (m *DeleteRepository) UpdateRetries() {
	m.Retries = &entities_pb.Retries{Attempts: m.GetAttempts() + 1}
}

// From unmarshals the message from the envelope
func (m *DeleteRepository) From(envelope *hydro_pb.Envelope) error {
	msg := new(pb.DeleteRepository)
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		return err
	}

	m.DeleteRepository = msg

	return nil
}

// Encode encodes the message
func (m *DeleteRepository) Encode() ([]byte, error) {
	encoder := hydro.NewDefaultEncoder()
	return encoder.Encode(m.DeleteRepository, m.TriggeredAt())
}

// GetName returns the name of the message
func (m *DeleteRepository) GetName() string {
	return "DeleteRepository"
}

// HydroMessage returns the message
func (m *DeleteRepository) HydroMessage() proto.Message {
	return m.DeleteRepository
}

// Queue returns the queue name
func (m *DeleteRepository) Queue() string {
	return aqueduct.QueueDeleteRepository
}

// TriggeredAt returns the time the message was triggered
func (m *DeleteRepository) TriggeredAt() time.Time {
	if m.Tracking != nil && m.Tracking.TriggeredAt != nil {
		return m.Tracking.TriggeredAt.AsTime()
	}
	return time.Now()
}
