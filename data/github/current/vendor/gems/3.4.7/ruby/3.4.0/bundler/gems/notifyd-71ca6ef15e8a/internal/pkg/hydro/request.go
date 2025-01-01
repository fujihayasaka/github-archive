// Package hydro implements hydro message publishing.
package hydro

import (
	"context"
	"time"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"

	"github.com/github/notifyd/internal/pkg/job"
)

// this is just a helper assignment so if the Request interface changes we
// will get a build error here with a message what to fix
var _ job.Request = &Request{}

// Request implements the Request interface for Hydro messages
type Request struct {
	// Start contains the timestamp in which we started to process this message. Can be used to
	// calculate elapsed time.
	start time.Time
	// Msg is the message itself that needs to be processed.
	msg     hydro.Message
	payload []byte
	clock   clockpkg.Clock
	headers *job.Headers
}

// NewRequest builds a new Request struct with start set to time.Now()
func NewRequest(msg hydro.Message, clock clockpkg.Clock) job.Request {
	return &Request{
		clock:   clock,
		start:   clock.Now(),
		msg:     msg,
		payload: msg.Value,
		headers: job.NewHeaders(job.WithHeadersFromMap(msg.Headers)),
	}
}

// Payload implements the Request interface
func (r *Request) Payload() []byte { return r.payload }

// SetPayload implements the Request interface
func (r *Request) SetPayload(payload []byte) {
	r.payload = payload
}

// HydroOffset implements the Request interface
func (r *Request) HydroOffset(context.Context) int64 { return r.msg.Offset }

// HydroTopic implements the Request interface
func (r *Request) HydroTopic(context.Context) string { return r.msg.Topic }

// HydroPartition implements the Request interface
func (r *Request) HydroPartition(context.Context) int64 { return int64(r.msg.Partition) }

// UnmarshalMessage unmarshals the payload of the hydro message (after removing the envelope header)
// into the supplied proto.Message
func (r *Request) UnmarshalMessage(msg proto.Message) error {
	return UnmarshalBytes(r.msg.Value, msg)
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
