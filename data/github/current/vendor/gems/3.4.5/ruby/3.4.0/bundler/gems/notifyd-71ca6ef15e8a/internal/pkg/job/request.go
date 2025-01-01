// Package job implements message processing.
package job

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/log"
	"google.golang.org/protobuf/proto"

	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// Handler defines the interface for a hydro handler
type Handler interface {
	Run(context.Context, tenancy.Tenant, log.Logger, Request) error
}

// HandlerFunc describes the type for handling a Request
type HandlerFunc func(context.Context, tenancy.Tenant, log.Logger, Request) error

// Request is the interface for work requests coming into notifyd. Usually
// this is either Hydro or Aqueduct. It holds the working state of the
// handlers that process a message, including the message itself.
type Request interface {
	o11y.HydroRequestInfo

	UnmarshalMessage(proto.Message) error
	Elapsed() time.Duration
	Payload() []byte
	SetPayload([]byte)
	Headers() *Headers
}

// Run is a wrapper around running the HandlerFunc with different parameterrs
func (f HandlerFunc) Run(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req Request) error {
	return f(ctx, tenant, logger, req)
}
