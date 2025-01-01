package api

import (
	"context"

	"golang.org/x/sync/errgroup"

	"github.com/github/turboghas/internal/api/ctes"
	"github.com/pkg/errors"
	"github.com/simon-engledew/sqlh"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/proto"
	"github.com/twitchtv/twirp"
)

func (h *handler) GetEnabledRepositories(ctx context.Context, req *proto.GetEnabledRepositoriesRequest) (*proto.GetEnabledRepositoriesResponse, error) {
	if req.EntityId == 0 {
		return nil, twirp.RequiredArgumentError("entity_id")
	}

	fromctx.Logger.Value(ctx).Info("GetEnabledRepositories",
		kvp.Uint64("gh.turboghas.entity_id", req.EntityId),
		kvp.String("gh.turboghas.entity_type", req.EntityType.String()),
		kvp.Uint64("gh.turboghas.offset", req.Cursor.GetOffset()),
	)

	var resp proto.GetEnabledRepositoriesResponse

	offset := req.Cursor.GetOffset()
	limit, err := GetLimit(req, 5000, 200_000)
	if err != nil {
		return nil, twirp.InvalidArgumentError("limit", err.Error())
	}

	orderExpr, err := GetOrder(req.GetColumnOrder(), "repository_nwo asc")
	if err != nil {
		return nil, twirp.InvalidArgumentError("order", err.Error())
	}

	g, ctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		return errors.WithStack(h.QueryRow(ctx, ctes.With(SQL(`SELECT COUNT(1) FROM cte_enabled_repositories`), ctes.EnabledRepositoriesCTEs(req))).Scan(&resp.Count))
	})
	g.Go(func() error {
		// a limit of 0 can get a count without returning any data
		if limit == 0 {
			return nil
		}
		rows, err := h.Query(ctx, ctes.With(SQL(`SELECT repository_id, repository_nwo FROM cte_enabled_repositories ORDER BY ? LIMIT ?, ?`, orderExpr, offset, limit), ctes.EnabledRepositoriesCTEs(req)))
		if err != nil {
			return errors.WithStack(err)
		}

		resp.Repositories, err = sqlh.Scan(rows, func(repository *proto.GetEnabledRepositoriesResponse_Repository, row sqlh.Row) error {
			return row.Scan(&repository.Id, &repository.Nwo)
		})

		return errors.WithStack(err)
	})

	if err := g.Wait(); err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	if limit > 0 {
		resp.NextCursor = req.Cursor.Next(uint32(limit), resp.Count)
	}

	return &resp, nil
}
