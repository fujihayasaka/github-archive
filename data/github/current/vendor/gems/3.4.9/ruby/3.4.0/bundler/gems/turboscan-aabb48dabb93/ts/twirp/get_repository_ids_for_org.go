package twirp

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/tstypes"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetRepositoryIDsForOrg(ctx context.Context, req *proto.RepositoryIDsForOrgRequest) (*proto.RepositoryIDsResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.repo.ids.excluded", fmt.Sprint(req.ExcludedRepositoryIds)),
	)

	if len(req.OwnerIds) == 0 {
		return nil, o11y.RecordError(span, twerrors.RequiredArgumentError("owner_ids"))
	}

	ownerIds := req.OwnerIds

	filter, _ := tstypes.CreateSearchByOrgsFilter(ownerIds, req.RepositoryIds, req.ExcludedRepositoryIds, req.Filter)

	repositories, err := r.es.SearchOrgRepositoryIDs(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	repositoryIDs := make([]uint64, len(repositories))
	for idx, repository := range repositories {
		repositoryIDs[idx] = repository.RepositoryId
	}

	return &proto.RepositoryIDsResponse{
		Repositories: repositories,
	}, nil
}
