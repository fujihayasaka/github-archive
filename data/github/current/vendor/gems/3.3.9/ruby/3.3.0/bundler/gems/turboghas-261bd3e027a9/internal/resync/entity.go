package resync

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fields"
	"github.com/github/turboghas/internal/fromctx"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/twirperr"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
)

func (p *Sync) Entity(ctx context.Context, ownerID uint64) (ok bool, err error) {
	defer func() {
		err = fields.Error(err, kvp.Uint64("gh.org.id", ownerID))
	}()

	resp, err := p.githubAPI.GetBillableUsers(ctx, &twirpTurboghas.GetBillableUsersRequest{
		OwnerId: ownerID,
	})
	if err != nil {
		if twirperr.IsTwirpError(err, twirp.FailedPrecondition, twirp.NotFound) {
			if err := p.db.DeleteUser(ctx, data.UserID(ownerID)); err != nil {
				return false, err
			}
			return false, p.db.DeletePurchaser(ctx, data.UserID(ownerID))
		}
		return false, errors.Wrap(err, "failed to get user information")
	}

	defer func() {
		err = fields.Error(err,
			kvp.Uint64("gh.turboghas.entity_id", resp.BillableEntityId),
			kvp.String("gh.turboghas.entity_type", resp.BillableEntityType.String()),
		)
	}()

	logger := fromctx.Logger.Value(ctx).WithFields(
		kvp.Uint64("gh.org.id", ownerID),
		kvp.Uint64("gh.turboghas.entity_id", resp.BillableEntityId),
		kvp.String("gh.turboghas.entity_type", resp.BillableEntityType.String()),
	)

	if len(resp.UserIds) == 0 {
		logger.Warn("organization has no contributors")
	}

	if len(resp.UserIds) > 50*1000 {
		logger.Warn("organization has large number of contributors", kvp.Int("contributors", len(resp.UserIds)))
	}

	if upsertErr := p.db.UpsertPurchaser(ctx, data.UpsertPurchaserArgs{
		OwnerID:    data.UserID(ownerID),
		EntityType: resp.BillableEntityType,
		EntityID:   resp.BillableEntityId,
	}); upsertErr != nil {
		return false, errors.Wrap(upsertErr, "failed to update purchaser")
	}

	if upsertErr := p.db.UpsertEntity(ctx, data.UpsertEntityArgs{
		EntityType: resp.BillableEntityType,
		EntityID:   resp.BillableEntityId,
		UserIDs:    resp.UserIds,
	}); upsertErr != nil {
		return false, errors.Wrap(upsertErr, "failed to update entity")
	}

	return true, nil
}
