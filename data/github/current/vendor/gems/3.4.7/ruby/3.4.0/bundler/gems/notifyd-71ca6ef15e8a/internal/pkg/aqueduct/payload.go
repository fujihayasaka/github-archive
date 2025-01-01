package aqueduct

import (
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"

	"github.com/github/notifyd/internal/pkg/compress"
	"github.com/github/notifyd/internal/pkg/errors"
)

// PayloadSizeToCompress is the size over which we compress the payload
const PayloadSizeToCompress = 1000 // 1KiB

// Payload represent the bytes send to an Aqueduct job
type Payload struct {
	content  []byte
	encoding string
}

// PayloadProcessor is a function that processes a Payload
type PayloadProcessor func(*Payload) (*Payload, error)

// NewPayloadFromProtobuf creates a new Payload from a protobuf message
func NewPayloadFromProtobuf(msg proto.Message, processors ...PayloadProcessor) (*Payload, error) {
	encoder := hydro.NewDefaultEncoder()
	content, err := encoder.Encode(msg.ProtoReflect().Interface(), time.Now())
	if err != nil {
		return nil, errors.Wrap(err, "error creating payload from protobuf")
	}

	return NewPayloadFromBytes(content, processors...)
}

// NewPayloadFromBytes creates a new Payload from a byte slice
func NewPayloadFromBytes(content []byte, processors ...PayloadProcessor) (*Payload, error) {
	payload := &Payload{content: content}

	var err error
	for _, processor := range processors {
		payload, err = processor(payload)
		if err != nil {
			return nil, errors.Wrap(err, "error post-processing payload")
		}
	}

	return payload, nil
}

// Content returns the payload content
func (p *Payload) Content() []byte {
	return p.content
}

// Len returns the length of the payload
func (p *Payload) Len() int {
	return len(p.content)
}

// Encoding returns the encoding of the payload
func (p *Payload) Encoding() string {
	return p.encoding
}

// WithCompressedPayload returns a PayloadProcessor that compresses the payload
func WithCompressedPayload(encoding compress.Encoding, logger log.Logger) PayloadProcessor {
	return func(payload *Payload) (*Payload, error) {
		// Only compress big payloads
		if payload.Len() < PayloadSizeToCompress {
			return payload, nil
		}

		start := time.Now()
		deflated, err := compress.Compress(encoding, payload.Content())
		if err != nil {
			logger.WithError(err).Info("using uncompressed payload due to an error compressing it")
			return payload, nil
		}
		duration := time.Since(start)
		logger.WithFields(
			kvp.Duration("gh.duration_ms", duration),
			kvp.String("gh.notifyd.encoding", string(encoding)),
		).Info("compressed payload")

		return &Payload{content: deflated, encoding: string(encoding)}, nil
	}
}
