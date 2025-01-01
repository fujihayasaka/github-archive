package api

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/internal/api/ctes"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/proto"
	"github.com/pkg/errors"
	"github.com/simon-engledew/sqlh"
	"github.com/twitchtv/twirp"
	"golang.org/x/sync/errgroup"
)

func (h *handler) GetCommittersForBusiness(ctx context.Context, req *proto.GetCommittersForBusinessRequest) (*proto.GetCommittersResponse, error) {
	if req.BusinessId == 0 {
		return nil, twirp.RequiredArgumentError("entity_id")
	}

	fromctx.Logger.Value(ctx).Info("GetCommittersForBusiness",
		kvp.Uint64("gh.turboghas.business_id", req.BusinessId),
		kvp.Uint64s("gh.turboghas.repository_ids", req.RepositoryIds),
		kvp.String("gh.turboghas.committer_type", req.CommitterType.String()),
		kvp.Uint64("gh.turboghas.offset", req.Cursor.GetOffset()),
	)

	var resp proto.GetCommittersResponse

	offset := req.Cursor.GetOffset()
	limit, err := GetLimit(req, 25, 200000)
	if err != nil {
		return nil, twirp.InvalidArgumentError("limit", err.Error())
	}

	filter := ctes.RepositoryIn(req)
	if req.GetCommitterType() == proto.CommitterType_ACTIVE_COMMITTERS {
		filter = SQL(`? AND active`, filter)
	}

	g, ctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		countQuery := SQL(`SELECT COUNT(1) FROM (SELECT 1 FROM cte_contributions WHERE ? GROUP BY repository_id, user_id HAVING user_id IN (?) AND user_id NOT IN (?)) AS grouped`, filter, ctes.BillableUsers, ctes.AdditionalCommitters(req.GetCommitterType()))

		return errors.WithStack(h.QueryRow(ctx, ctes.WithContributions(ctx, req, countQuery)).Scan(&resp.Count))
	})
	g.Go(func() error {
		groupedQuery := SQL(`SELECT MAX(id) AS id, user_id, repository_id FROM cte_contributions WHERE ? GROUP BY user_id, repository_id HAVING user_id IN (?) AND user_id NOT IN (?)`, filter, ctes.BillableUsers, ctes.AdditionalCommitters(req.GetCommitterType()))

		query := SQL(`SELECT grouped.user_id, tg_users.login, grouped.repository_id, concat(owners.login, '/', tg_repositories.name) as repository_nwo, tg_contributions.pushed_at, tg_contributions.email
FROM (?) AS grouped
INNER JOIN tg_repositories USING (repository_id)
INNER JOIN tg_users USING (user_id)
INNER JOIN tg_users owners ON tg_repositories.owner_id = owners.user_id
INNER JOIN tg_contributions ON tg_contributions.id = grouped.id
ORDER BY owners.login, tg_repositories.name, tg_contributions.pushed_at DESC, tg_users.login ASC
LIMIT ?, ?`, groupedQuery, offset, limit)

		rows, err := h.Query(ctx, ctes.WithContributions(ctx, req, query))
		if err != nil {
			return errors.WithStack(err)
		}

		resp.Committers, err = sqlh.Scan(rows, func(activeCommitter *proto.GetCommittersResponse_Committer, row sqlh.Row) error {
			return row.Scan(
				&activeCommitter.Id,
				&activeCommitter.Login,
				&activeCommitter.RepositoryId,
				&activeCommitter.RepositoryNwo,
				data.Timestamp(&activeCommitter.PushedAt),
				&activeCommitter.Email,
			)
		})

		return errors.WithStack(err)
	})

	if err := g.Wait(); err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	resp.NextCursor = req.Cursor.Next(limit, resp.Count)

	return &resp, nil
}
