package runnergroups

import (
	context "context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	db "github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

var visibilityToString = map[UpdateVisibility]string{
	UpdateVisibility_UNKNOWN:         "",
	UpdateVisibility_UPDATE_ALL:      "ALL",
	UpdateVisibility_UPDATE_PRIVATE:  "PRIVATE",
	UpdateVisibility_UPDATE_SELECTED: "SELECTED",
}

var allowPublicFromUpdateReq = map[UpdateAllowPublic]azp.AllowPublic{
	UpdateAllowPublic_ALLOW_PUBLIC_UNKNOWN: azp.AllowPublicUnknown,
	UpdateAllowPublic_ALLOW_PUBLIC_ALLOW:   azp.AllowPublicAllow,
	UpdateAllowPublic_ALLOW_PUBLIC_DENY:    azp.AllowPublicDeny,
}

var restrictedToWorkflowsFromUpdateReq = map[UpdateRestrictedToWorkflows]azp.RestrictedToWorkflows{
	UpdateRestrictedToWorkflows_RESTRICTED_TO_WORKFLOWS_UNKNOWN:      azp.RestrictedToWorkflowsUnknown,
	UpdateRestrictedToWorkflows_RESTRICTED_TO_WORKFLOWS_RESTRICTED:   azp.RestrictedToWorkflowsRestricted,
	UpdateRestrictedToWorkflows_RESTRICTED_TO_WORKFLOWS_UNRESTRICTED: azp.RestrictedToWorkflowsUnrestricted,
}

func (s *service) UpdateGroup(ctx context.Context, req *UpdateGroupRequest) (*UpdateGroupResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "updategroup")

	ownerID := types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
	if ownerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("owner id cannot be nil")
	}

	planOwnerID := types.NewGlobalID(ctx, req.GetPlanOwnerId().GetGlobalId())
	if planOwnerID.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("plan owner id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.owner.global_id", ownerID.String()), kvp.String("gh.launch.plan_owner.global_id", planOwnerID.String()))

	arc, err := s.getAzureRepositoryClient(ctx, ownerID)
	if err != nil {
		if _, ok := errors.Cause(err).(*db.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for UpdateGroup lookup")
			return &UpdateGroupResponse{RunnerGroup: nil}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	organizationName, err := s.getPlanOwnerOrganizationName(ctx, planOwnerID)
	if err != nil {
		obs.Log(ctx, "could not get tenant for plan owner")
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	existingGroup, err := arc.GetGroup(ctx, req.GroupId, ownerID, planOwnerID, organizationName, true, false, true, false, false)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	visibility := visibilityToString[req.UpdateVisibility]
	allowPublic := allowPublicFromUpdateReq[req.AllowPublic]
	restrictedToWorkflows := restrictedToWorkflowsFromUpdateReq[req.RestrictedToWorkflows]
	workflowRefOperations := getWorkflowRefOperations(existingGroup, req.SelectedWorkflowRefs)

	if existingGroup.Visibility.WorkflowRestrictionsReadOnly {
		restrictedToWorkflows = uint(UpdateRestrictedToWorkflows_RESTRICTED_TO_WORKFLOWS_UNKNOWN)
		workflowRefOperations = make([]azp.WorkflowRestrictionOp, 0)
	}

	err = arc.UpdateVisibility(ctx, req.GroupId, visibility, req.SelectedTargets, allowPublic, workflowRefOperations, restrictedToWorkflows)

	if err != nil {
		if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
			if report {
				obs.Report(ctx, err)
			}
			return nil, svcerr
		}
	}

	// `UpdateVisibility` does not properly return inherited visibility settings, so we need to get the group again
	existingGroup, err = arc.GetGroup(ctx, req.GroupId, ownerID, planOwnerID, organizationName, true, false, true, false, false)
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	if existingGroup.OwningTenant != types.NilGlobalID {
		// Inherited runner group, skip any further updates
		rg := s.mapRunnerGroup(existingGroup)
		return &UpdateGroupResponse{RunnerGroup: rg}, nil
	}

	// If runnerIDs are passed, we bulk replace them by sending add/remove operations to Service.
	var runnerOperations []azp.RunnerOp
	if len(req.GetRunnerIds()) > 0 {
		runnerOperations = getRunnerOperations(existingGroup, req.GetRunnerIds())
	}

	runtimeRunnerGroup, err := arc.UpdateGroup(ctx, ownerID, req.GroupId, runnerOperations, req.GetName())
	if svcerr, report := azperrors.ToServiceError(err); svcerr != nil {
		if report {
			obs.Report(ctx, err)
		}
		return nil, svcerr
	}

	// unfortunately the `UpdateGroup` call does not return visibility from Actions Service,
	runtimeRunnerGroup.Visibility = existingGroup.Visibility

	rg := s.mapRunnerGroup(runtimeRunnerGroup)
	return &UpdateGroupResponse{RunnerGroup: rg}, nil
}

func getRunnerOperations(existingGroup *azp.RunnerGroup, newRunnerIds []int64) []azp.RunnerOp {
	var runnerOperations []azp.RunnerOp

	existingRunnerIds := convertRunnersToRunnerIDs(existingGroup.Runners)
	runnersToAdd := differenceInRunnerIds(newRunnerIds, existingRunnerIds)
	runnersToRemove := differenceInRunnerIds(existingRunnerIds, newRunnerIds)

	runnerOperations = append(runnerOperations, createRunnerOps(runnersToAdd, runnersToRemove)...)

	return runnerOperations
}

// differenceInRunnerIds returns the runnerIds in `a` that aren't in `b`.
// This allows us to know which runners we need to update
func differenceInRunnerIds(a, b []int64) []int64 {
	mb := make(map[int64]struct{}, len(b))
	for _, x := range b {
		mb[x] = struct{}{}
	}
	var diff []int64
	for _, x := range a {
		if _, found := mb[x]; !found {
			diff = append(diff, x)
		}
	}
	return diff
}

func convertRunnersToRunnerIDs(runners []*azp.RunnerV2) []int64 {
	runnerIDs := make([]int64, len(runners))
	for i, runner := range runners {
		runnerIDs[i] = runner.ID
	}
	return runnerIDs
}

func createRunnerOps(runnersToAdd []int64, runnersToRemove []int64) []azp.RunnerOp {
	var operations []azp.RunnerOp

	if len(runnersToAdd) > 0 {
		addOperation := azp.RunnerOp{
			Op:    "add",
			Path:  "/runners",
			Value: runnersToAdd,
		}

		operations = append(operations, addOperation)
	}

	if len(runnersToRemove) > 0 {
		removeOperation := azp.RunnerOp{
			Op:    "remove",
			Path:  "/runners",
			Value: runnersToRemove,
		}

		operations = append(operations, removeOperation)
	}

	return operations
}

func getWorkflowRefOperations(existingGroup *azp.RunnerGroup, newWorkflowRefs []string) []azp.WorkflowRestrictionOp {
	var operations []azp.WorkflowRestrictionOp

	existingWorkflowRefs := existingGroup.Visibility.SelectedWorkflowRefs
	workflowRefsToAdd := differenceInWorkflowRefs(newWorkflowRefs, existingWorkflowRefs)
	workflowRefsToRemove := differenceInWorkflowRefs(existingWorkflowRefs, newWorkflowRefs)

	operations = append(operations, createWorkflowRefOps(workflowRefsToAdd, workflowRefsToRemove)...)

	return operations
}

// differenceInWorkflowRefs returns the workflowRefs in `a` that aren't in `b`.
// This allows us to know which workflowRefs we need to update
func differenceInWorkflowRefs(a, b []string) []string {
	mb := make(map[string]struct{}, len(b))
	for _, x := range b {
		mb[x] = struct{}{}
	}
	var diff []string
	for _, x := range a {
		if _, found := mb[x]; !found {
			diff = append(diff, x)
		}
	}
	return diff
}

func createWorkflowRefOps(workflowRefsToAdd []string, workflowRefsToRemove []string) []azp.WorkflowRestrictionOp {
	var operations []azp.WorkflowRestrictionOp

	if len(workflowRefsToAdd) > 0 {
		addOperation := azp.WorkflowRestrictionOp{
			Op:    "add",
			Path:  "/selectedWorkflowRefs",
			Value: workflowRefsToAdd,
		}

		operations = append(operations, addOperation)
	}

	if len(workflowRefsToRemove) > 0 {
		removeOperation := azp.WorkflowRestrictionOp{
			Op:    "remove",
			Path:  "/selectedWorkflowRefs",
			Value: workflowRefsToRemove,
		}

		operations = append(operations, removeOperation)
	}

	return operations
}
