package selfhostedrunners

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

// CreateLabel returns a user-defined label that can be used for runners
func (s *service) CreateLabel(ctx context.Context, req *CreateLabelRequest) (*CreateLabelResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "listlabels")

	oid := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if oid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	name := req.GetName()

	ctx = ctxstash.WithFields(
		ctx,
		kvp.String("gh.launch.owner.global_id", oid.String()),
		kvp.String("gh.launch.label.name", name),
	)

	arc, err := s.getAzureRepositoryClient(ctx, oid)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for CreateLabel lookup")
			return &CreateLabelResponse{}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	/*
		Technically, the `type` field can be one of "system" or "user", but in this
		case, we will only ever send "user". This is because "system" labels are
		automatically applied by us (not the user) and typically reflect things like
		the runner's OS and architecture.

		This means that the only externally-managable field for a user-defined label is
		the name.
	*/
	fields := azp.LabelFields{Name: name, Type: "user"}

	al, err := arc.CreateLabel(ctx, fields)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	l := &Label{
		Id:   al.ID,
		Name: al.Name,
		Type: al.Type,
	}
	return &CreateLabelResponse{Label: l}, nil
}
