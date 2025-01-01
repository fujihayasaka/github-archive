package hydro

import (
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"

	"github.com/github/notifyd/internal/pkg/errors"
)

// UnmarshalMessage will write into the given proto message the unmarshalled content of the hydro
// message.
func UnmarshalMessage(msg hydro.Message, pb proto.Message) error {
	return UnmarshalBytes(msg.Value, pb)
}

// UnmarshalBytes will unmarshall the hydro envelop and content and write its content into the
// given proto message.
func UnmarshalBytes(bytes []byte, pb proto.Message) error {
	var envelope hydro_pb.Envelope
	if err := proto.Unmarshal(bytes, &envelope); err != nil {
		return errors.Wrap(err, "unmarshalling hydro envelope failed")
	}

	if err := proto.Unmarshal(envelope.Message, pb); err != nil {
		return errors.Wrap(err, "unmarshalling message failed")
	}
	return nil
}
