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

func (h *handler) GetEnterpriseUsers(ctx context.Context, req *proto.GetEnterpriseUsersRequest) (resp *proto.GetEnterpriseUsersResponse, err error) {
	if req.BusinessId == 0 {
		return nil, twirp.RequiredArgumentError("business_id")
	}

	fromctx.Logger.Value(ctx).Info("GetEnterpriseUsers",
		kvp.Uint64("gh.turboghas.business_id", req.BusinessId),
		kvp.Uint64("gh.turboghas.offset", req.Cursor.GetOffset()),
	)

	resp = &proto.GetEnterpriseUsersResponse{}

	offset := req.Cursor.GetOffset()
	limit, err := GetLimit(req, 10, 50)
	if err != nil {
		return nil, twirp.InvalidArgumentError("limit", err.Error())
	}

	// go 1.21 might be able to infer this
	orderExpr, err := GetOrder[proto.GetEnterpriseUsersRequest_Column](req.GetColumnOrder(), "unique_committers desc, login asc")
	if err != nil {
		return nil, twirp.InvalidArgumentError("order", err.Error())
	}

	g, ctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		countQuery := SQL(`SELECT COUNT(DISTINCT owner_id) FROM cte_contributions WHERE features_active AND owner_type = 'User' AND user_id IN (?)`, ctes.BillableUsers)

		return errors.WithStack(h.QueryRow(ctx, ctes.WithContributions(ctx, req, countQuery)).Scan(&resp.Count))
	})

	g.Go(func() error {
		userContributions := SQL(`SELECT owner_id, user_id FROM cte_contributions WHERE features_active GROUP BY owner_id, user_id HAVING user_id IN (?)`, ctes.BillableUsers)

		sharedCommitters := SQL(`SELECT user_id, COUNT(DISTINCT owner_id) AS orgs FROM cte_contributions WHERE features_active GROUP BY user_id HAVING user_id IN (?)`, ctes.BillableUsers)

		query := SQL(`SELECT owner_id, owners.login, committers, unique_committers FROM (
	SELECT
	    results.owner_id,
	    COUNT(DISTINCT results.user_id) AS committers,
	    IFNULL(SUM(results.is_unique), 0) AS unique_committers
	FROM (
		SELECT
		    user_contributions.owner_id,
		    user_contributions.user_id,
		    MAX(shared_committers.orgs) = 1 AS 'is_unique'
		FROM (?) AS user_contributions
		LEFT JOIN (?) AS shared_committers
		ON shared_committers.user_id = user_contributions.user_id
		GROUP BY user_contributions.owner_id, user_contributions.user_id
	) AS results
	GROUP BY results.owner_id
) AS grouped
INNER JOIN tg_users owners ON owners.user_id = grouped.owner_id
WHERE owners.type = 'User'
ORDER BY ?
LIMIT ?, ?`, userContributions, sharedCommitters, orderExpr, offset, limit)

		rows, err := h.Query(ctx, ctes.WithContributions(ctx, req, query))
		if err != nil {
			return errors.WithStack(err)
		}

		resp.Users, err = sqlh.Scan(rows, func(user *proto.GetEnterpriseUsersResponse_User, row sqlh.Row) error {
			return row.Scan(&user.Id, &user.Login, &user.ActiveCommitters, &user.UniqueCommitters)
		})

		return errors.WithStack(err)
	})

	if err := g.Wait(); err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	resp.NextCursor = req.Cursor.Next(limit, resp.Count)

	return resp, nil
}
