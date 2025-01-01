package selfhostedrunners

import (
	context "context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
)

// UpdateAccessPolicy allows users to change their Org self-hosted runners access policy (which repos can use the runners).
func (s *service) UpdateAccessPolicy(ctx context.Context, req *UpdateAccessPolicyRequest) (*GetAccessPolicyResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "updateaccesspolicy")

	globalID := s.getGlobalIDFromUpdateAccessPolicyRequest(ctx, req)
	if globalID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", globalID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, globalID)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Error(ctx, "no backing resources for UpdateAccessPolicy")
			return &GetAccessPolicyResponse{}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	// We need the existing access policy so we can diff the selected_repos
	existingAccessPolicy, err := arc.GetAccessPolicy(ctx)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	permissionOp, addReposOp, removeReposOp := s.createUpdatePayload(ctx, req, existingAccessPolicy)

	accessPolicy, err := arc.UpdateAccessPolicy(ctx, permissionOp, addReposOp, removeReposOp)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	return &GetAccessPolicyResponse{
		PermissionType:       StringToPermissionMap[accessPolicy.PermissionType],
		SelectedRepositories: types.IdentitiesFromGlobalIDs(accessPolicy.SelectedRepositories),
	}, nil
}

func (s *service) getGlobalIDFromUpdateAccessPolicyRequest(ctx context.Context, req *UpdateAccessPolicyRequest) types.GlobalID {
	return types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
}

var permissionToString = map[PermissionType]string{
	PermissionType_ALL_REPOSITORIES:      "allRepos",
	PermissionType_PRIVATE_REPOSITORIES:  "privateRepos",
	PermissionType_SELECTED_REPOSITORIES: "selectedRepos",
}

func (s *service) createUpdatePayload(ctx context.Context, req *UpdateAccessPolicyRequest, existingAccessPolicy *azp.AccessPolicy) (azp.PermissionOp, azp.SelectedReposOp, azp.SelectedReposOp) {
	permissionOp := azp.PermissionOp{
		Op:    "replace",
		Path:  "/permissionType",
		Value: permissionToString[req.PermissionType],
	}

	if req.PermissionType != PermissionType_SELECTED_REPOSITORIES {
		return permissionOp, azp.SelectedReposOp{}, azp.SelectedReposOp{}
	}

	existingSelectedRepos := types.IdentitiesFromGlobalIDs(existingAccessPolicy.SelectedRepositories)
	newSelectedRepos := req.SelectedRepositories

	reposToAdd := difference(newSelectedRepos, existingSelectedRepos)
	reposToRemove := difference(existingSelectedRepos, newSelectedRepos)

	addReposOp := azp.SelectedReposOp{
		Op:    "add",
		Path:  "/selectedRepositories",
		Value: types.GlobalIDsFromIdentities(ctx, reposToAdd),
	}

	removeReposOp := azp.SelectedReposOp{
		Op:    "remove",
		Path:  "/selectedRepositories",
		Value: types.GlobalIDsFromIdentities(ctx, reposToRemove),
	}

	return permissionOp, addReposOp, removeReposOp
}

// difference returns the elements in `a` that aren't in `b`.
func difference(a, b []*pbtypes.Identity) []*pbtypes.Identity {
	mb := make(map[string]struct{}, len(b))
	for _, x := range b {
		mb[x.GetGlobalId()] = struct{}{}
	}
	var diff []*pbtypes.Identity
	for _, x := range a {
		if _, found := mb[x.GetGlobalId()]; !found {
			diff = append(diff, x)
		}
	}
	return diff
}
