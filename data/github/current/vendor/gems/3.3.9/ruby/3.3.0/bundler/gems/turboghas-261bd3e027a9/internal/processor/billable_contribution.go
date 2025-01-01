package processor

import (
	"context"
	"time"

	"github.com/SamuelTissot/sqltime"
	v0 "github.com/github/hydro-schemas-go/hydro/schemas/turboghas/v0"
	"github.com/github/turboghas/internal/data"
	"github.com/pkg/errors"
)

// We can ignore replication lag here because we already waited for it for the PostReceive message
var _ = IgnoreReplicationLagTopic("turboghas.v0.BillableContribution")

func (p *Processor) billableContribution(ctx context.Context, billableContribution *v0.BillableContribution) error {
	var newest time.Time

	// TurboGHAS publishes BillableContribution messages to Hydro when a contribution
	// is processed. We want that data in Hydro so it is persisted into the data warehouse.
	// Here, TurboGHAS also reads from that same topic (at the time of writing, it's the
	// only thing that does) and writes it to the DB. This way, we ensure that data is
	// always in both Hydro _and_ the database, avoiding the risk of inconsistency.
	for _, committer := range billableContribution.Committers {
		err := p.db.UpsertContribution(ctx, data.UpsertContributionArgs{
			RepositoryID: data.RepositoryID(billableContribution.Repository.Id),
			UserID:       committer.UserId,
			PushedAt:     sqltime.Time{Time: billableContribution.PushedAt.AsTime()},
			Email:        committer.Email,
		})
		if err != nil {
			return errors.Wrap(err, "failed to upsert committer")
		}

		if createdAt := committer.CreatedAt.AsTime(); createdAt.After(newest) {
			newest = createdAt
		}
	}

	hasCache, err := p.db.HasContributorsCache(ctx, data.UserID(billableContribution.Owner.Id), &newest)
	if err != nil {
		return errors.Wrap(err, "failed to check if purchaser is recent")
	}

	if !hasCache {
		_, err := p.sync.Entity(ctx, uint64(billableContribution.Owner.Id))
		return err
	}

	return nil
}
