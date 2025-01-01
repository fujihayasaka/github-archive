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

func (h *handler) GetRepositories(ctx context.Context, req *proto.GetRepositoriesRequest) (resp *proto.GetRepositoriesResponse, err error) {
	if req.OwnerId == 0 {
		return nil, twirp.RequiredArgumentError("owner_id")
	}

	fromctx.Logger.Value(ctx).Info("GetRepositories",
		kvp.Uint64("gh.turboghas.owner_id", req.OwnerId),
		kvp.Uint64("gh.turboghas.offset", req.Cursor.GetOffset()),
	)

	resp = &proto.GetRepositoriesResponse{}

	offset := req.Cursor.GetOffset()
	limit, err := GetLimit(req, 10, 50)
	if err != nil {
		return nil, twirp.InvalidArgumentError("limit", err.Error())
	}

	// go 1.21 might be able to infer this
	orderExpr, err := GetOrder[proto.GetRepositoriesRequest_Column](req.GetColumnOrder(), "unique_committers desc, name asc")
	if err != nil {
		return nil, twirp.InvalidArgumentError("order", err.Error())
	}

	g, ctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		countQuery := SQL(`SELECT COUNT(DISTINCT repository_id) FROM cte_contributions WHERE features_active AND user_id IN (?)`, ctes.BillableUsers)

		return errors.WithStack(h.QueryRow(ctx, ctes.WithContributions(ctx, req, countQuery)).Scan(&resp.Count))
	})
	g.Go(func() error {
		orgContributions := SQL(`SELECT repository_id, user_id FROM cte_contributions WHERE features_active GROUP BY repository_id, user_id HAVING user_id IN (?)`, ctes.BillableUsers)

		query := SQL(`SELECT grouped.repository_id, tg_repositories.name, committers, unique_committers FROM (
	SELECT
		org_contributions.repository_id,
		COUNT(DISTINCT org_contributions.user_id) AS committers,
		IFNULL(SUM(org_contributions.user_id IN (?)), 0) AS unique_committers
	FROM (?) AS org_contributions
	GROUP BY org_contributions.repository_id
) AS grouped
INNER JOIN tg_repositories ON tg_repositories.repository_id = grouped.repository_id
ORDER BY ?
LIMIT ?, ?`, ctes.UniqueRepositoryCommitters, orgContributions, orderExpr, offset, limit)

		rows, err := h.Query(ctx, ctes.WithContributions(ctx, req, query))
		if err != nil {
			return errors.WithStack(err)
		}

		resp.Repositories, err = sqlh.Scan(rows, func(repository *proto.GetRepositoriesResponse_Repository, row sqlh.Row) error {
			return row.Scan(&repository.Id, &repository.Name, &repository.ActiveCommitters, &repository.UniqueCommitters)
		})

		return errors.WithStack(err)
	})

	if err := g.Wait(); err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	resp.NextCursor = req.Cursor.Next(limit, resp.Count)

	return resp, nil
}
