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
	"golang.org/x/exp/slices"
)

func Map[T, V any](items []T, fn func(T) V) []V {
	if items == nil {
		return nil
	}
	out := make([]V, 0, len(items))
	for _, item := range items {
		out = append(out, fn(item))
	}
	return out
}

func (h *handler) GetActiveCommitters(ctx context.Context, req *proto.GetActiveCommittersRequest) (*proto.GetActiveCommittersResponse, error) {
	if req.EntityId == 0 {
		return nil, twirp.RequiredArgumentError("entity_id")
	}

	fromctx.Logger.Value(ctx).Info("GetActiveCommitters",
		kvp.Uint64("gh.turboghas.entity_id", req.EntityId),
		kvp.String("gh.turboghas.entity_type", req.EntityType.String()),
	)

	var resp proto.GetActiveCommittersResponse

	query := SQL(`SELECT DISTINCT user_id FROM cte_contributions WHERE features_active HAVING user_id IN (?)`, ctes.BillableUsers)

	userIDs, err := sqlh.Pluck[uint64](h.Query(ctx, ctes.WithContributions(ctx, req, query)))
	if err != nil {
		return nil, twirp.InternalErrorWith(errors.WithStack(err))
	}

	slices.Sort(userIDs)

	resp.Users = Map(userIDs, func(id uint64) *proto.GetActiveCommittersResponse_User {
		return &proto.GetActiveCommittersResponse_User{
			Id: id,
		}
	})

	return &resp, nil
}
