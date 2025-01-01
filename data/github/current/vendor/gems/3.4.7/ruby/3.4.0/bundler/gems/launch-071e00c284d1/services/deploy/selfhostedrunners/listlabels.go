package selfhostedrunners

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
)

// ListLabels returns a list of labels
func (s *service) ListLabels(ctx context.Context, req *ListLabelsRequest) (*ListLabelsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "listlabels")

	oid := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if oid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", oid.String()))

	arc, err := s.getAzureRepositoryClient(ctx, oid)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Debug(ctx, "no backing resources for ListLabels lookup")
			return &ListLabelsResponse{Labels: make([]*Label, 0)}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	labels, err := arc.ListLabels(ctx)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	ls := convertLabelsFromAzp(labels)
	return &ListLabelsResponse{Labels: ls}, nil
}
