package processor

import (
	"context"
	"strconv"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	advancedSecurityBillingv0 "github.com/github/hydro-schemas-go/hydro/schemas/advanced_security_billing/v0"
	"github.com/github/turboghas/internal/fields"
	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("advanced_security_billing.v0.BillingToggled")
var BillingToggledQueue = Queue(&advancedSecurityBillingv0.BillingToggled{})

func (p *Processor) billingToggled(ctx context.Context, billingToggled *advancedSecurityBillingv0.BillingToggled) error {
	// The Aqueduct job will be handled by billingToggledJob, below.
	return errors.Wrap(p.EnqueueJob(ctx, billingToggled, 250), "failed to enqueue BillingToggled job")
}

func toEntity(billingToggled *advancedSecurityBillingv0.BillingToggled) (uint64, v1.EntityType) {
	switch ent := billingToggled.GetBillableEntity().(type) {
	case *advancedSecurityBillingv0.BillingToggled_Business:
		return ent.Business.Id, v1.EntityType_ENTITY_TYPE_BUSINESS
	case *advancedSecurityBillingv0.BillingToggled_Organization:
		return ent.Organization.Id, v1.EntityType_ENTITY_TYPE_USER
	default:
		return 0, v1.EntityType_ENTITY_TYPE_INVALID
	}
}

func (p *Processor) billingToggledJob(ctx context.Context, billingToggled *advancedSecurityBillingv0.BillingToggled) (err error) {
	statter := fromctx.Statter.Value(ctx)

	entityID, entityType := toEntity(billingToggled)
	if entityType == v1.EntityType_ENTITY_TYPE_INVALID {
		return backoff.Permanent(errors.New("failed to process billing_toggled job no entity provided"))
	}

	defer func() {
		err = fields.Error(err,
			kvp.Uint32("gh.turboghas.actor_id", billingToggled.Actor.Id),
			kvp.Any("gh.turboghas.entity_type", entityType),
			kvp.Uint64("gh.turboghas.entity_id", entityID),
			kvp.Bool("billing_toggle_state", billingToggled.ToggleState),
		)
	}()

	statter.Counter("billing_toggled.message", stats.Tags{"entity_type": entityType.String(), "enabled": strconv.FormatBool(billingToggled.ToggleState)}, 1)

	repoIDs, err := p.db.GetEntityRepositories(ctx, entityID, entityType)

	if err != nil {
		return errors.Wrap(err, "failed to get entity repositories")
	}

	statter.Counter("billing_toggled.repositories", stats.Tags{}, int64(len(repoIDs)))

	// batch through in chunks of 80
	for i := 0; i < len(repoIDs); i += 80 {
		end := i + 80
		if end > len(repoIDs) {
			end = len(repoIDs)
		}
		if err := fromctx.Retry(ctx, func() error {
			return p.sync.Repositories(ctx, repoIDs[i:end])
		}, fromctx.DefaultBackOff()); err != nil {
			return errors.Wrap(err, "failed to sync entity repositories")
		}
	}

	return errors.Wrap(err, "failed to get sync entity repositories")
}
