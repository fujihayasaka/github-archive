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

	// TODO: make this a required parameter once it is being passed by the frontend
	if req.Sku == v1.SKU_SKU_INVALID {
		req.Sku = v1.SKU_SKU_GHAS_SEATS
	}

	var resp proto.GetSummaryResponse

	defer func() {
		fromctx.Logger.Value(ctx).Info("GetSummary",
			kvp.Uint64("gh.turboghas.entity_id", req.EntityId),
			kvp.String("gh.turboghas.entity_type", req.EntityType.String()),
			kvp.Uint64s("gh.repo_ids", req.RepositoryIds),
			kvp.String("gh.turboghas.sku", req.Sku.String()),
			kvp.Strings("gh.turboghas.features", Map(req.Features, v1.Feature.String)),
			kvp.Uint64("gh.customer_id", req.CustomerId),
			kvp.Uint64s("gh.turboghas.additional_user_ids", req.AdditionalUserIds),
			kvp.Uint64("gh.turboghas.active_committers", resp.ActiveCommitters),
			kvp.Uint64("gh.turboghas.maximum_committers", resp.MaximumCommitters),
			kvp.Uint64("gh.turboghas.unique_committers", resp.UniqueCommitters),
			kvp.Uint64("gh.turboghas.additional_committers", resp.AdditionalCommitters),
			kvp.Uint64("gh.turboghas.additional_metered_committers", resp.AdditionalMeteredCommitters),
		)
	}()

	repos := ctes.RepositoryIn(req)

	sharedCommitters := SQL(`user_id IN (?)`, ctes.EntityCommitters)
	uniqueCommitters := SQL(`user_id IN (?)`, ctes.UniqueCommitters)

	if req.GetEntityType() == v1.EntityType_ENTITY_TYPE_BUSINESS {
		sharedCommitters = SQL(`1 != 1`)
		uniqueCommitters = SQL(`1 = 1`)
	}

	meteredCommitters := SQL(`0`)

	if req.CustomerId > 0 && len(req.AdditionalUserIds) > 0 {
		meteredCommitters = sqlh.SQL(`user_id IN (?)`, sqlh.SQL(`SELECT actor_id
FROM tg_meter_emissions
WHERE customer_id = ? AND actor_id IN (?) AND sku = ?`, req.CustomerId, sqlh.In(req.AdditionalUserIds), req.Sku))
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
		max(features_active) AS 'is_active',
		max(features_active) and min(? or not features_active) AS 'is_unique'
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
