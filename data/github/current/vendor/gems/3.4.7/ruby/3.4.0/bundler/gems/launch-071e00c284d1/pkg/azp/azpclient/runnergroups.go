package azpclient

import (
	"context"
	"net/http"

	errs "github.com/pkg/errors"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
)

type RunnerGroupsService struct {
	client *Client
	http   *httpclient.Client
}

func (r *RunnerGroupsService) ListGroups(ctx context.Context, ownerID, planOwnerID types.GlobalID, planOwnerTenant string, includeRunners bool, isEnterpriseOwner bool, excludeHostedRunnerGroups bool, excludeElasticRunners bool, includeRunnerScaleSets bool) ([]*azp.RunnerGroup, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroups.list"

	var resp *runnerGroupsListResponse

	err := r.http.Do(
		ctx,
		opname,
		http.MethodGet,
		r.client.url.getListRunnerGroupsURL(includeRunners,
			ownerID.String(),
			planOwnerID.String(),
			planOwnerTenant,
			isEnterpriseOwner,
			excludeHostedRunnerGroups,
			excludeElasticRunners,
			includeRunnerScaleSets,
		),
		nil,
		&resp,
		r.client.withDefaultOpts(ctx)...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

func (r *RunnerGroupsService) GetGroup(ctx context.Context, groupID int64, ownerID, planOwnerID types.GlobalID, planOwnerTenant string, includeRunners bool, isEnterpriseOwner bool, excludeHostedRunnerGroups bool, excludeElasticRunners bool, includeRunnerScaleSets bool) (*azp.RunnerGroup, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroup.get"

	var resp *azp.RunnerGroup
	err := r.http.Do(
		ctx,
		opname,
		http.MethodGet,
		r.client.url.getRunnerGroupURLbyGroupIDFor(
			groupID,
			ownerID.String(),
			planOwnerID.String(),
			planOwnerTenant,
			includeRunners,
			isEnterpriseOwner,
			excludeHostedRunnerGroups,
			excludeElasticRunners,
			includeRunnerScaleSets,
		),
		nil,
		&resp,
		r.client.withDefaultOpts(ctx)...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (r *RunnerGroupsService) DeleteGroup(ctx context.Context, groupID int64) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroup.delete"

	validator := func(r *http.Response) (bool, error) {
		_, err := azp.ResponseValidator()(r)
		if err == nil && r.StatusCode == http.StatusNoContent {
			return false, nil
		}

		// err could still be nil here for 200s that aren't 204
		if err != nil {
			err = errs.Wrapf(err, "the delete runner group request returned %d status code, expected 204", r.StatusCode)
		}

		retryable := r.StatusCode >= 500
		return retryable, err
	}

	err := r.http.Do(
		ctx,
		opname,
		http.MethodDelete,
		r.client.url.getRunnerGroupURLbyGroupID(groupID),
		nil,
		nil,
		r.client.withDefaultOpts(ctx, httpclient.WithValidator(validator))...,
	)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

func (r *RunnerGroupsService) CreateGroup(ctx context.Context, runnerIDs []int64, name string, selectedTargets []*pbtypes.Identity, visibility string, allowPublic azp.AllowPublic, selectedWorkflowRefs []string, restrictedToWorkflows azp.RestrictedToWorkflows) (*azp.RunnerGroup, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroup.create"

	payload := createGroupPayload{
		Name: name,
		Visibility: visibilityPayload{
			VisibilityType:        visibility,
			SelectedTargets:       types.GlobalIDsFromIdentities(ctx, selectedTargets),
			AllowPublic:           allowPublicMap[allowPublic],
			SelectedWorkflowRefs:  selectedWorkflowRefs,
			RestrictedToWorkflows: restrictedToWorkflowsMap[restrictedToWorkflows],
		},
	}

	var runnerGroup *azp.RunnerGroup
	err := r.http.Do(
		ctx,
		opname,
		http.MethodPost,
		r.client.url.getRunnerGroupsURL(),
		payload,
		&runnerGroup,
		r.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONContentType()))...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	if len(runnerIDs) > 0 {
		// TODO move this to hook:
		// c.obs.Report(ctx, errs.Wrap(err, "failed to update group runners"))
		// Don't return errors here. The group has been created, only adding runners has failed
		_, _ = r.UpdateGroupRunners(ctx, runnerGroup.ID, runnerIDs)
	}

	return runnerGroup, nil
}

func (r *RunnerGroupsService) UpdateGroup(ctx context.Context, _ types.GlobalID, groupID int64, runnerOperations []azp.RunnerOp, name string) (*azp.RunnerGroup, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroup.update"

	body := []any{}

	if len(name) > 0 {
		namePatch := patch{
			Op:    replaceOp,
			Path:  "/name",
			Value: name,
		}
		body = append(body, namePatch)
	}

	// If runnerOperations has anything, add it.
	if len(runnerOperations) > 0 {
		body = append(body, runnerOperations)
	}

	var resp *azp.RunnerGroup
	err := r.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		r.client.url.getRunnerGroupURLbyGroupID(groupID),
		body,
		&resp,
		r.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONPatchContentType()))...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (r *RunnerGroupsService) AddRunners(ctx context.Context, groupID int64, runnerIDs []int64) (*azp.RunnerGroup, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroup.add_runner"

	body := []patch{
		{Op: addOp, Path: runnersPath, Value: runnerIDs},
	}

	var resp *azp.RunnerGroup
	err := r.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		r.client.url.getRunnerGroupURLbyGroupID(groupID),
		body,
		&resp,
		r.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONPatchContentType()))...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (r *RunnerGroupsService) RemoveRunner(ctx context.Context, groupID, runnerID int64) (*azp.RunnerGroup, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroup.remove_runner"

	patches := []patch{
		{Op: removeOp, Path: runnersPath, Value: []int64{runnerID}},
	}

	var runnerGroup *azp.RunnerGroup
	err := r.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		r.client.url.getRunnerGroupURLbyGroupID(groupID),
		patches,
		&runnerGroup,
		r.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONPatchContentType()))...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return runnerGroup, nil
}

func (r *RunnerGroupsService) UpdateGroupRunners(ctx context.Context, groupID int64, runnerIDs []int64) (*azp.RunnerGroup, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroup.update_runners"

	body := []patch{
		{Op: replaceOp, Path: runnersPath, Value: runnerIDs},
	}

	var resp *azp.RunnerGroup
	err := r.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		r.client.url.getRunnerGroupURLbyGroupID(groupID),
		body,
		&resp,
		r.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONPatchContentType()))...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (r *RunnerGroupsService) AddTarget(ctx context.Context, groupID int64, target *pbtypes.Identity) (*azp.Visibility, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroup.add_target"

	body := []patch{
		{Op: addOp, Path: targetPath, Value: []string{target.GetGlobalId()}},
	}

	var resp *azp.Visibility
	err := r.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		r.client.url.getRunnerGroupVisibilityURL(groupID),
		body,
		&resp,
		r.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONPatchContentType()))...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (r *RunnerGroupsService) UpdateVisibility(ctx context.Context, groupID int64, visibilityType string, targets []*pbtypes.Identity, allowPublic azp.AllowPublic, selectedWorkflowOperations []azp.WorkflowRestrictionOp, restrictedToWorkflows azp.RestrictedToWorkflows) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroup.update_visibility"

	var body []patch

	if len(visibilityType) > 0 {
		body = append(body,
			patch{Op: replaceOp, Path: visibilityTypePath, Value: visibilityType},
			patch{Op: replaceOp, Path: targetPath, Value: types.GlobalIDsFromIdentities(ctx, targets)},
		)
	}

	if allowPublicValue, ok := allowPublicMap[allowPublic]; ok {
		body = append(body,
			patch{Op: replaceOp, Path: allowPublicPath, Value: allowPublicValue},
		)
	}

	if len(selectedWorkflowOperations) > 0 {
		body = append(body, convertWorkflowOpsToPatches(selectedWorkflowOperations)...)
	}

	if restrictedToWorkflowsValue, ok := restrictedToWorkflowsMap[restrictedToWorkflows]; ok {
		body = append(body,
			patch{Op: replaceOp, Path: restrictedToWorkflowsPath, Value: restrictedToWorkflowsValue},
		)
	}

	if len(body) == 0 {
		return nil
	}

	return r.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		r.client.url.getRunnerGroupVisibilityURL(groupID),
		body,
		nil,
		r.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONPatchContentType()))...,
	)
}

func (r *RunnerGroupsService) RemoveTarget(ctx context.Context, groupID int64, target *pbtypes.Identity) (*azp.Visibility, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroup.remove_target"

	body := []patch{
		{Op: removeOp, Path: targetPath, Value: []string{target.GetGlobalId()}},
	}

	var resp *azp.Visibility
	err := r.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		r.client.url.getRunnerGroupVisibilityURL(groupID),
		body,
		&resp,
		r.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONPatchContentType()))...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (r *RunnerGroupsService) UpdateGroupTargets(ctx context.Context, groupID int64, targets []*pbtypes.Identity) (*azp.Visibility, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnergroup.update_targets"

	targetIDs := make([]string, len(targets))
	for i, t := range targets {
		targetIDs[i] = t.GlobalId
	}

	body := []patch{
		{Op: replaceOp, Path: targetPath, Value: targetIDs},
	}

	var resp *azp.Visibility
	err := r.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		r.client.url.getRunnerGroupVisibilityURL(groupID),
		body,
		&resp,
		r.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONPatchContentType()))...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}
