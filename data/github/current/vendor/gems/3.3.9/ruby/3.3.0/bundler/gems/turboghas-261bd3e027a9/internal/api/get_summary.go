package api

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/internal/api/ctes"
	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/proto"
	"github.com/pkg/errors"
	"github.com/simon-engledew/sqlh"
	"github.com/twitchtv/twirp"
)

func (h *handler) GetSummary(ctx context.Context, req *proto.GetSummaryRequest) (*proto.GetSummaryResponse, error) {
	if req.EntityId == 0 {
		return nil, twirp.RequiredArgumentError("entity_id")
	}

	fromctx.Logger.Value(ctx).Info("GetSummary",
		kvp.Uint64("gh.turboghas.entity_id", req.EntityId),
		kvp.String("gh.turboghas.entity_type", req.EntityType.String()),
	)

	var resp proto.GetSummaryResponse

	repos := ctes.RepositoryIn(req)

	sharedCommitters := SQL(`user_id IN (?)`, ctes.SharedCommitters)
	uniqueCommitters := SQL(`user_id IN (?)`, ctes.UniqueCommitters)

	if req.GetEntityType() == v1.EntityType_ENTITY_TYPE_BUSINESS {
		sharedCommitters = SQL(`1 != 1`)
		uniqueCommitters = SQL(`1 = 1`)
	}

	meteredCommitters := SQL(`0`)

	if req.CustomerId > 0 && len(req.AdditionalUserIds) > 0 {
		meteredCommitters = sqlh.SQL(`user_id IN (?)`, sqlh.SQL(`SELECT actor_id
FROM tg_meter_emissions
WHERE customer_id = ? AND actor_id IN (?)`, req.CustomerId, sqlh.In(req.AdditionalUserIds)))
	}

	query := SQL(`SELECT
	count(1) AS 'maximum_committers',
	IFNULL(sum(is_active), 0) AS 'active_committers',
	count(1) - IFNULL(sum(is_active OR ?), 0) AS 'additional_committers',
	IFNULL(sum(is_unique AND ?), 0) AS 'unique_committers',
	IFNULL(sum(? AND not is_active), 0) AS 'additional_metered_committers'
FROM (
	SELECT
		user_id,
		max(?) AS 'repo_included',
		max(active) AS 'is_active',
		max(active) and min(? or not active) AS 'is_unique'
	FROM cte_contributions
	GROUP BY user_id
	HAVING user_id IN (?)
) AS contributions
WHERE repo_included = 1`, sharedCommitters, uniqueCommitters, meteredCommitters, repos, repos, ctes.BillableUsers)

	if err := h.QueryRow(ctx, ctes.WithContributions(ctx, req, query)).Scan(&resp.MaximumCommitters, &resp.ActiveCommitters, &resp.AdditionalCommitters, &resp.UniqueCommitters, &resp.AdditionalMeteredCommitters); err != nil {
		return nil, twirp.InternalErrorWith(errors.WithStack(err))
	}

	return &resp, nil
}
