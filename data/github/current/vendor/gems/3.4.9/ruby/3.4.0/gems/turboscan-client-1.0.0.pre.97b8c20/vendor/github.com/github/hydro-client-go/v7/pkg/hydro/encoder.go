package hydro

import (
	"time"

	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"

	"github.com/google/uuid"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// Encoder is the interface that wraps the Encode method used to encode a
// proto.Message into bytes. createdAt is the time at which the message was
// created.
type Encoder interface {
	Encode(msg proto.Message, createdAt time.Time) ([]byte, error)
}

// JSONEncoder implements the Encoder interface to encode proto.Messages into
// JSON marshalled bytes.
type JSONEncoder struct {
	marshaler protojson.MarshalOptions
}

// NewJSONEncoder returns a new JSONEncoder configured to convert protobuf
// enums into integers, always include zero value fields, and use the original
// proto field names.
func NewJSONEncoder() *JSONEncoder {
	return &JSONEncoder{
		marshaler: protojson.MarshalOptions{
			UseEnumNumbers:  true,
			EmitUnpopulated: false,
			UseProtoNames:   true,
		},
	}
}

// Encode encodes the proto.Message into JSON marshalled bytes. It returns an
// error if it fails to marshal to JSON. This encoder ignores the createdAt
// timestamp.
func (je *JSONEncoder) Encode(m proto.Message, _ time.Time) ([]byte, error) {
	return je.marshaler.Marshal(m)
}

// EncoderOption is a function that configures a DefaultEncoder encoder.
type EncoderOption func(*DefaultEncoder)

// WithEnvelopeSiteName is an EncoderOption that sets site name metadata in the
// message envelope.
func WithEnvelopeSiteName(s string) EncoderOption {
	return func(e *DefaultEncoder) {
		e.site = s
	}
}

// DefaultEncoder encodes an event wrapped in a hydro.v1.Envelope along with
// publishing metadata.
//
// As indicated by its name, it is the default Encoder that should be used in
// almost every case when publishing events to a Hydro cluster. See the Encode
// method for details about the encoding format.
//
// It must be created with NewDefaultEncoder.
type DefaultEncoder struct {
	site string

	// for testing
	uuidFn func() (uuid.UUID, error)
}

// NewDefaultEncoder returns a new DefaultEncoder using the DefaultSite unless
// overridden using WithEnvelopeSiteName.
func NewDefaultEncoder(opts ...EncoderOption) *DefaultEncoder {
	e := DefaultEncoder{
		site:   DefaultSite,
		uuidFn: uuid.NewRandom,
	}
	for _, opt := range opts {
		opt(&e)
	}
	return &e
}

// The prefix used to generate a proto.Message's Hydro schema definition URL.
var typeURLPrefix = "hydro-schemas.github.net/"

// Encode encodes the proto.Message into a hydro.v1.Envelope that is protobuf
// marshalled to bytes. The returned encoded envelope contains the original
// message protobuf marshalled to bytes and metadata fields. The metadata is
// comprised of the URL to the proto.Message's Hydro schema definition, the
// current timestamp, a generated UUID, and the encoder's site of origin.
//
// It returns any error encountered while marshalling or generating the
// metadata fields.
func (de *DefaultEncoder) Encode(msg proto.Message, createdAt time.Time) ([]byte, error) {
	msgBytes, err := proto.Marshal(msg)
	if err != nil {
		return nil, err
	}

	ptime := timestamppb.New(createdAt)

	uuid, err := de.uuidFn()
	if err != nil {
		return nil, err
	}

	envelope := &hydro_pb.Envelope{
		TypeUrl:   typeURLPrefix + string(proto.MessageName(msg)),
		Message:   msgBytes,
		Id:        uuid.String(),
		Timestamp: ptime,
		SiteName:  de.site,
	}

	return proto.Marshal(envelope)
}
