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
	"golang.org/x/sync/errgroup"
)

func (h *handler) GetOrganizations(ctx context.Context, req *proto.GetOrganizationsRequest) (resp *proto.GetOrganizationsResponse, err error) {
	if req.BusinessId == 0 {
		return nil, twirp.RequiredArgumentError("business_id")
	}

	fromctx.Logger.Value(ctx).Info("GetOrganizations",
		kvp.Uint64("gh.turboghas.business_id", req.BusinessId),
		kvp.Uint64("gh.turboghas.offset", req.Cursor.GetOffset()),
	)

	resp = &proto.GetOrganizationsResponse{}

	offset := req.Cursor.GetOffset()
	limit, err := GetLimit(req, 10, 50)
	if err != nil {
		return nil, twirp.InvalidArgumentError("limit", err.Error())
	}

	// go 1.21 might be able to infer this
	orderExpr, err := GetOrder[proto.GetOrganizationsRequest_Column](req.GetColumnOrder(), "unique_committers desc, login asc")
	if err != nil {
		return nil, twirp.InvalidArgumentError("order", err.Error())
	}

	g, ctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		countQuery := SQL(`SELECT COUNT(DISTINCT owner_id) FROM cte_contributions WHERE active AND owner_type = 'Organization' AND user_id IN (?)`, ctes.BillableUsers)

		return errors.WithStack(h.QueryRow(ctx, ctes.WithContributions(ctx, req, countQuery)).Scan(&resp.Count))
	})
	g.Go(func() error {
		orgContributions := SQL(`SELECT owner_id, user_id FROM cte_contributions WHERE active GROUP BY owner_id, user_id HAVING user_id IN (?)`, ctes.BillableUsers)

		query := SQL(`SELECT owner_id, owners.login, committers, unique_committers FROM (
	SELECT
		org_contributions.owner_id,
		COUNT(DISTINCT org_contributions.user_id) AS committers,
		IFNULL(SUM(org_contributions.user_id IN (?)), 0) AS unique_committers
	FROM (?) AS org_contributions
	GROUP BY org_contributions.owner_id
) AS grouped
INNER JOIN tg_users owners ON owners.user_id = grouped.owner_id
WHERE owners.type = 'Organization'
ORDER BY ?
LIMIT ?, ?`, ctes.UniqueCommitters, orgContributions, orderExpr, offset, limit)

		rows, err := h.Query(ctx, ctes.WithContributions(ctx, req, query))
		if err != nil {
			return errors.WithStack(err)
		}

		resp.Organizations, err = sqlh.Scan(rows, func(organization *proto.GetOrganizationsResponse_Organization, row sqlh.Row) error {
			return row.Scan(&organization.Id, &organization.Login, &organization.ActiveCommitters, &organization.UniqueCommitters)
		})

		return errors.WithStack(err)
	})

	if err := g.Wait(); err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	resp.NextCursor = req.Cursor.Next(limit, resp.Count)

	return resp, nil
}
