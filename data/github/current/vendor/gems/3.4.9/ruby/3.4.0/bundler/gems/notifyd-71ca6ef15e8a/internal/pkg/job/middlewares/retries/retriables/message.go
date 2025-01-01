package retriables

import (
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"google.golang.org/protobuf/proto"

	entities_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/pkg/errors"
)

// ErrUnknownMsgType is an error that is returned when the message type is unknown
var ErrUnknownMsgType = errors.New("unknown message type")

// Message provides all the methods required to make a notification retriable
type Message interface {
	// GetRetries returns the Retries entity from the message. This method is implicitly implemented
	// on any protobuf message that includes the Retries entity and doens't need to be implemented by
	// the code generator.
	GetRetries() *entities_pb.Retries
	// GetAttempts returns how many times a message has been retried.
	GetAttempts() int32
	// UpdateRetries increases the number of retries in 1, preparing the message for the next retry.
	UpdateRetries()
	// Encode returns the byte slice that is sent to aqueduct through the wire.
	Encode() ([]byte, error)
	// From unmarshals an envelope's content into this retriable.
	From(*hydro_pb.Envelope) error
	// GetName returns the name of the message in a simplified form. e.g. Notify or DeliverMobilePush
	GetName() string
	// HydroMessage returns the original message that needs to be published to hydro.
	HydroMessage() proto.Message
	// Queue returns the name of the queue to use to process the retry.
	Queue() string
}

// BuildMessage returns a retriable that can be used to send a retry into aqueduct or to
// redeliver such message into hydro.
func BuildMessage(envelope *hydro_pb.Envelope) (Message, error) {
	var msg Message
	switch MsgType(envelope.TypeUrl) {
	case NotifyType:
		msg = &Notify{}
	case DeliverMobilePushType:
		msg = &MobilePush{}
	case DeliverEmailType:
		msg = &Email{}
	case DeleteRepositoryType:
		msg = &DeleteRepository{}
	case DeleteRepositoryForUsersType:
		msg = &DeleteRepositoryForUsers{}
	case DeleteUserType:
		msg = &DeleteRepository{}
	case DeleteUserRepositoriesType:
		msg = &DeleteUserRepositories{}
	default:
		return nil, errors.Wrap(ErrUnknownMsgType, envelope.TypeUrl)
	}

	err := msg.From(envelope)
	return msg, err
}
