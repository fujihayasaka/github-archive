// Package deleterepository contains the adapter and handler for the deleterepository job
package deleterepository

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	ghaqueduct "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"

	schema_v1 "github.com/github/notifyd/hydro/schemas/notifyd/v1"
	"github.com/github/notifyd/internal/pkg/aqueduct"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// Adapter is a struct containing dependencies for the adapter
type Adapter struct {
	handler *Handler
	chain   *job.Chain
	clock   clockpkg.Clock
	telem   *telemetry.Provider
	tenant  tenancy.Tenant
}

// NewAdapter creates a new Adapter
func NewAdapter(
	clock clockpkg.Clock,
	telem *telemetry.Provider,
	tenant tenancy.Tenant,
	handler *Handler,
	chain *job.Chain,
) *Adapter {
	return &Adapter{handler: handler, chain: chain, clock: clock, telem: telem, tenant: tenant}
}

// Run runs the adapter
func (a *Adapter) Run(ctx context.Context, rr ghaqueduct.ReceiveResult) error {
	handler := a.chain.Then(job.HandlerFunc(func(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, r job.Request) error {
		ctx, span := tracing.StartSpan(
			otel.GetTextMapPropagator().Extract(ctx, propagation.MapCarrier(rr.Headers)),
			"DeleteRepository aqueduct message received",
			trace.WithSpanKind(trace.SpanKindConsumer),
		)
		defer span.End()

		attrs := []attribute.KeyValue{
			attribute.String("gh.aqueduct.app", rr.App),
			attribute.String("gh.aqueduct.queue.name", rr.Queue),
			attribute.String("gh.aqueduct.job.id", rr.ID),
			attribute.String("gh.request_id", rr.Headers["request_id"]),
		}
		span.SetAttributes(attrs...)

		var msg schema_v1.DeleteRepository
		err := r.UnmarshalMessage(&msg)
		if err != nil {
			return errors.Wrap(err, "unable to unmarshal message")
		}
		return a.handler.Run(ctx, msg.GetRepositoryId())
	}))

	req := aqueduct.NewRequest(a.clock, a.telem, rr)

	return handler.Run(ctx, a.tenant, a.telem.Logger, req)
}
