package api

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/internal/api/ctes"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/proto"
	"github.com/pkg/errors"
	"github.com/simon-engledew/sqlh"
	"github.com/twitchtv/twirp"
)

func (h *handler) GetMeterEmissions(ctx context.Context, req *proto.GetMeterEmissionsRequest) (_ *proto.GetMeterEmissionsResponse, err error) {
	if req.EntityId == 0 {
		return nil, twirp.RequiredArgumentError("entity_id")
	}

	if req.CustomerId == 0 {
		return nil, twirp.RequiredArgumentError("customer_id")
	}

	var resp proto.GetMeterEmissionsResponse

	defer func() {
		fromctx.Logger.Value(ctx).WithError(err).Info("GetMeterEmissions",
			kvp.Uint64("gh.turboghas.entity_id", req.EntityId),
			kvp.String("gh.turboghas.entity_type", req.EntityType.String()),
			kvp.Uint64("gh.turboghas.customer_id", req.CustomerId),
			kvp.Int("added", len(resp.Added)),
			kvp.Int("removed", len(resp.Removed)),
		)
	}()

	if fromctx.Env.Value(ctx).IsEnterprise() {
		return &resp, twirp.NewError(twirp.FailedPrecondition, "endpoint not available")
	}

	usersQuery := SQL(`SELECT user_id FROM cte_contributions WHERE active HAVING user_id IN (?)`, ctes.BillableUsers)

	// allow dotcom to force users to be contributors via GHES usage
	if len(req.AdditionalUserIds) > 0 {
		usersQuery = SQL(`? UNION ? WHERE user_id IN (?)`, usersQuery, ctes.BillableUsers, sqlh.In(req.AdditionalUserIds))
	}

	emissionsQuery := SQL(`SELECT tg_meter_emissions.actor_id AS user_id
FROM tg_meter_emissions
WHERE tg_meter_emissions.customer_id = ?`,
		req.CustomerId,
	)

	// todo: switch back to EXCEPT when MySQL is on version 8.0.31
	query := SQL(`SELECT added.user_id, true FROM cte_users AS added
WHERE added.user_id NOT IN ((SELECT user_id FROM cte_emissions))
UNION
SELECT removed.user_id, false FROM cte_emissions AS removed
WHERE removed.user_id NOT IN ((SELECT user_id FROM cte_users))
ORDER BY user_id ASC`)

	rows, err := h.Query(ctx, ctes.WithContributions(ctx, req, query, SQL("cte_users AS (?)", usersQuery), SQL("cte_emissions AS (?)", emissionsQuery)))
	if err != nil {
		return nil, twirp.InternalErrorWith(errors.WithStack(err))
	}

	data, err := sqlh.ScanV(rows, func(d *struct {
		UserID uint64
		Added  bool
	}, row sqlh.Row) error {
		return row.Scan(
			&d.UserID,
			&d.Added,
		)
	})
	if err != nil {
		return nil, twirp.InternalErrorWith(errors.WithStack(err))
	}

	for _, d := range data {
		if d.Added {
			resp.Added = append(resp.Added, d.UserID)
		} else {
			resp.Removed = append(resp.Removed, d.UserID)
		}
	}

	return &resp, nil
}
