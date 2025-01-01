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

func (h *handler) GetAdditionalCommittersPerRepository(ctx context.Context, req *proto.GetAdditionalCommittersPerRepositoryRequest) (*proto.GetAdditionalCommittersPerRepositoryResponse, error) {
	if req.EntityId == 0 {
		return nil, twirp.RequiredArgumentError("entity_id")
	}

	if req.EntityType == v1.EntityType_ENTITY_TYPE_INVALID {
		return nil, twirp.RequiredArgumentError("entity_type")
	}

	fromctx.Logger.Value(ctx).Info("GetAdditionalCommittersPerRepository",
		kvp.Uint64("gh.turboghas.entity_id", req.EntityId),
		kvp.String("gh.turboghas.entity_type", req.EntityType.String()),
		kvp.Uint64s("gh.turboghas.repository_ids", req.RepositoryIds),
	)

	var resp proto.GetAdditionalCommittersPerRepositoryResponse

	query := SQL(`SELECT repository_id, SUM(user_id IN (?) AND user_id NOT IN (?)) as additional_committers
FROM cte_contributions
WHERE ? AND NOT features_active
GROUP BY repository_id
HAVING additional_committers > 0
`,
		ctes.BillableUsers,
		ctes.EntityCommitters,
		ctes.RepositoryIn(req),
	)

	rows, err := h.Query(ctx, ctes.WithContributions(ctx, req, query))
	if err != nil {
		return nil, twirp.InternalErrorWith(errors.WithStack(err))
	}

	resp.Repositories, err = sqlh.Scan(rows, func(repository *proto.GetAdditionalCommittersPerRepositoryResponse_Repository, row sqlh.Row) error {
		return row.Scan(
			&repository.Id,
			&repository.AdditionalCommitters,
		)
	})

	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &resp, nil
}
