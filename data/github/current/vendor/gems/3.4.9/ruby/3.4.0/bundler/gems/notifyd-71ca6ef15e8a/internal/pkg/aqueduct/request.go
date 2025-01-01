package aqueduct

import (
	"context"
	"strconv"
	"time"

	clockpkg "github.com/benbjohnson/clock"
	aqclient "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/telemetry"
	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"google.golang.org/protobuf/proto"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/job"
)

// this is just a helper assignment so if the Request interface changes we
// will get a build error here with a message what to fix
var _ job.Request = &Request{}

// Request implements the Request interface for Hydro messages
type Request struct {
	// start contains the timestamp in which we started to process this message. Can be used to
	// calculate elapsed time.
	start   time.Time
	payload []byte
	clock   clockpkg.Clock
	telem   *telemetry.Provider
	headers *job.Headers
}

// NewRequest builds a new Request struct with start set to time.Now()
func NewRequest(clock clockpkg.Clock, telem *telemetry.Provider, r aqclient.ReceiveResult) job.Request {
	return &Request{
		start:   clock.Now(),
		clock:   clock,
		telem:   telem,
		headers: job.NewHeaders(job.WithHeadersFromMap(r.Headers)),
		payload: r.Payload,
	}
}

// Payload implements the job.Request interface
func (r *Request) Payload() []byte { return r.payload }

// SetPayload implements the job.Request interface
func (r *Request) SetPayload(payload []byte) {
	r.payload = payload
}

// HydroOffset implements the Request interface
func (r *Request) HydroOffset(ctx context.Context) int64 {
	offset, ok := r.headers.Get("offset")
	if !ok {
		r.telem.Logger.WithContext(ctx).Info("offset header undefined")
		return 0
	}
	n, err := strconv.ParseInt(offset, 10, 64)
	if err != nil {
		r.telem.Logger.WithContext(ctx).Info("unable to parse offset into int64")
	}
	return n
}

// HydroTopic implements the Request interface
func (r *Request) HydroTopic(context.Context) string {
	topic, _ := r.headers.Get("topic")
	return topic
}

// HydroPartition implements the Request interface
func (r *Request) HydroPartition(ctx context.Context) int64 {
	partition, ok := r.headers.Get("partition")
	if !ok {
		r.telem.Logger.WithContext(ctx).Info("partition header undefined")
		return 0
	}
	n, err := strconv.ParseInt(partition, 10, 32)
	if err != nil {
		r.telem.Logger.WithContext(ctx).Info("unable to parse partition into int64")
	}
	return n
}

// UnmarshalMessage unmarshals the payload of the hydro message (after removing the envelope header)
// into the supplied proto.Message
func (r *Request) UnmarshalMessage(msg proto.Message) error {
	var envelope schemas.Envelope
	if err := proto.Unmarshal(r.payload, &envelope); err != nil {
		return errors.Wrap(err, "unmarshalling hydro envelope")
	}
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		return errors.Wrap(err, "unmarshalling message from hydro envelope")
	}

	return nil
}

// Elapsed returns the duration since the Request was created, which is mean to represent how long a
// message has been processing.
func (r *Request) Elapsed() time.Duration {
	return r.clock.Since(r.start)
}

// Headers returns the message headers
func (r *Request) Headers() *job.Headers {
	return r.headers
}
