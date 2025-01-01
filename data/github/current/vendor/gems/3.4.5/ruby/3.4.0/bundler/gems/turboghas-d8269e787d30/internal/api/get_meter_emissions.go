package api

import (
	"context"
	"time"

	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"

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

	if req.Sku == v1.SKU_SKU_INVALID {
		return nil, twirp.RequiredArgumentError("sku")
	}

	var resp proto.GetMeterEmissionsResponse

	defer func() {
		fromctx.Logger.Value(ctx).WithError(err).Info("GetMeterEmissions",
			kvp.Uint64("gh.turboghas.entity_id", req.EntityId),
			kvp.String("gh.turboghas.entity_type", req.EntityType.String()),
			kvp.String("gh.turboghas.sku", req.Sku.String()),
			kvp.Uint64("gh.turboghas.customer_id", req.CustomerId),
			kvp.Time("current_billing_period_started_at", req.CurrentBillingPeriodStartedAt.AsTime()),
			kvp.Int("added", len(resp.Added)),
			kvp.Int("removed", len(resp.Removed)),
		)
	}()

	if fromctx.Env.Value(ctx).IsEnterprise() {
		return &resp, twirp.NewError(twirp.FailedPrecondition, "endpoint not available")
	}

	usersQuery := SQL(`SELECT user_id FROM cte_contributions WHERE features_active HAVING user_id IN (?)`, ctes.BillableUsers)

	// allow dotcom to force users to be contributors via GHES usage
	if len(req.AdditionalUserIds) > 0 {
		usersQuery = SQL(`? UNION ? WHERE user_id IN (?)`, usersQuery, ctes.BillableUsers, sqlh.In(req.AdditionalUserIds))
	}

	if req.Sku != v1.SKU_SKU_GHAS_SEATS {
		if req.CurrentBillingPeriodStartedAt == nil {
			return nil, twirp.RequiredArgumentError("current_billing_period_started_at")
		}

		// find all the emissions we have already made for this customer within the last 24 hours
		todaysEmissionsQuery := SQL(`SELECT actor_id AS user_id
  FROM tg_meter_emissions
 WHERE customer_id = ?
   AND sku = ?
   AND usage_at > ? - INTERVAL 24 HOUR`,
			req.CustomerId,
			req.Sku,
			time.Now(),
		)

		// find any users who we've already seen since this billing period started and need to emit again
		previousEmissionsQuery := SQL(`SELECT actor_id AS user_id
 FROM tg_meter_emissions
WHERE customer_id = ?
  AND sku = ?
  AND usage_at >= ?`,
			req.CustomerId,
			req.Sku,
			req.CurrentBillingPeriodStartedAt.AsTime(),
		)

		// include any users who are currently active, remove any users we have already made an emission for
		query := SQL(`SELECT user_id FROM cte_added WHERE user_id NOT IN (?) ORDER BY user_id ASC`, todaysEmissionsQuery)

		meteredCTEs := append(ctes.ContributionsCTEs(ctx, req),
			SQL("cte_users AS (?)", usersQuery),
			SQL("cte_previous_emissions AS (?)", previousEmissionsQuery),
			SQL("cte_added AS (?)", SQL(`SELECT user_id FROM cte_users UNION SELECT user_id FROM cte_previous_emissions`)),
		)

		resp.Added, err = sqlh.Pluck[uint64](h.Query(ctx, ctes.With(query, meteredCTEs)))
		if err != nil {
			return nil, twirp.InternalErrorWith(errors.WithStack(err))
		}

		if err := h.QueryRow(ctx, ctes.With(SQL(`SELECT count(1) FROM cte_added`), meteredCTEs)).Scan(&resp.Total); err != nil {
			return nil, twirp.InternalErrorWith(errors.WithStack(err))
		}

		return &resp, nil
	}

	emissionsQuery := SQL(`SELECT actor_id AS user_id
 FROM tg_meter_emissions
WHERE customer_id = ?
  AND sku = ?`,
		req.CustomerId,
		req.Sku,
	)

	// todo: switch back to EXCEPT when MySQL is on version 8.0.31
	query := SQL(`SELECT added.user_id, true FROM cte_users AS added
WHERE added.user_id NOT IN ((SELECT user_id FROM cte_emissions))
UNION
SELECT removed.user_id, false FROM cte_emissions AS removed
WHERE removed.user_id NOT IN ((SELECT user_id FROM cte_users))
ORDER BY user_id ASC`)

	rows, err := h.Query(ctx, ctes.With(query, append(ctes.ContributionsCTEs(ctx, req), SQL("cte_users AS (?)", usersQuery), SQL("cte_emissions AS (?)", emissionsQuery))))
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
