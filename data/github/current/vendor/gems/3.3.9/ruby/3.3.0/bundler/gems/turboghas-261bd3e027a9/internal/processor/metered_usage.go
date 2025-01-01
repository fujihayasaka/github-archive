package processor

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	billingplatformv1 "github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fromctx"
)

// We can ignore replication lag here because we only use the contents of the message and do not reach out for external state.
var _ = IgnoreReplicationLagTopic("billingplatform.v1.Usage")

func (p *Processor) meteredUsage(ctx context.Context, usage *billingplatformv1.Usage) error {
	if fromctx.Env.Value(ctx).IsEnterprise() {
		return nil
	}

	if usage.Sku == "ghas_seats" && usage.Entity != nil && usage.Entity.ActorId != 0 {
		switch usage.Quantity {
		case 1.0:
			return p.db.UpsertMeterEmission(ctx, data.UpsertMeterEmissionArgs{
				CustomerID: uint64(usage.Entity.CustomerId),
				ActorID:    uint64(usage.Entity.ActorId),
			})
		case -1.0:
			return p.db.DeleteMeterEmission(ctx, data.UpsertMeterEmissionArgs{
				CustomerID: uint64(usage.Entity.CustomerId),
				ActorID:    uint64(usage.Entity.ActorId),
			})
		default:
			fromctx.Logger.Value(ctx).Warn("ignoring billingplatformv1.Usage event",
				kvp.Float64("gh.turboghas.quantity", usage.Quantity),
				kvp.Int64("gh.turboghas.customer_id", usage.Entity.CustomerId),
				kvp.Int64("gh.turboghas.actor_id", usage.Entity.ActorId),
			)
		}
	}
	return nil
}
