package selfhostedrunners

import (
	context "context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
)

// GetAccessPolicy returns the policy that determines which repositories can use self-hosted runners.
func (s *service) GetAccessPolicy(ctx context.Context, req *GetAccessPolicyRequest) (*GetAccessPolicyResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "getaccesspolicy")

	globalID := s.getGlobalIDFromGetAccessPolicyRequest(ctx, req)
	if globalID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", globalID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, globalID)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Error(ctx, "no backing resources for GetAccessPolicy")
			return &GetAccessPolicyResponse{}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	accessPolicy, err := arc.GetAccessPolicy(ctx)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	return &GetAccessPolicyResponse{
		PermissionType:       StringToPermissionMap[accessPolicy.PermissionType],
		SelectedRepositories: types.IdentitiesFromGlobalIDs(accessPolicy.SelectedRepositories),
	}, nil
}

var StringToPermissionMap = map[string]PermissionType{
	"allRepos":      PermissionType_ALL_REPOSITORIES,
	"privateRepos":  PermissionType_PRIVATE_REPOSITORIES,
	"selectedRepos": PermissionType_SELECTED_REPOSITORIES,
}

func (s *service) getGlobalIDFromGetAccessPolicyRequest(ctx context.Context, req *GetAccessPolicyRequest) types.GlobalID {
	return types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
}
