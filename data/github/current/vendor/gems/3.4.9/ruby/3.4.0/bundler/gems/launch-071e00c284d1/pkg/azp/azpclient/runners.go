package azpclient

import (
	"context"
	"errors"
	"net/http"
	"strconv"

	errs "github.com/pkg/errors"

	"github.com/github/launch/clients/github"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/types"
)

const (
	// For some endpoints the group ID must be provided but it is ignored.
	anyRunnerGroupID = 0
	// For some operations we only want to work against the default group.
	defaultRunnerGroupID = 1
)

type RunnersService struct {
	client *Client
	http   *httpclient.Client
}

func (rs *RunnersService) ListRunnersV2(ctx context.Context, page, perPage int64, includeAssignedRequest bool, poolID int64, runnerName string, excludeElasticRunners bool) ([]*azp.RunnerV2, int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runners.list_v2"

	var paginationTotal int64
	validator := func(r *http.Response) (bool, error) {
		var err error
		if _, ok := r.Header["X-Total-Count"]; ok {
			paginationTotal, err = strconv.ParseInt(r.Header.Get("X-Total-Count"), 10, 64)
			if err != nil {
				return false, errs.Wrap(err, "the list runners v2 response contained a bad x-total-count header")
			}
		}
		return azp.ResponseValidator()(r)
	}

	// There is no poolID/runner group with ID 0, ID 1 is the default group.
	// For `getListRunnersV2URL` 0 for poolID is used as a special ID which includes all groups.
	var resp *azp.RunnersListV2
	err := rs.http.Do(
		ctx,
		opname,
		http.MethodGet,
		rs.client.url.getListRunnersV2URL(poolID, page, perPage, includeAssignedRequest, runnerName, excludeElasticRunners),
		nil,
		&resp,
		rs.client.withDefaultOpts(ctx,
			httpclient.WithValidator(validator),
		)...,
	)
	if err != nil {
		return nil, 0, tracing.RecordError(span, err)
	}

	if paginationTotal == 0 {
		paginationTotal = resp.Count
	}

	return resp.Value, paginationTotal, nil
}

func (rs *RunnersService) UpdateRunners(ctx context.Context, operations []*azp.RunnerOp) ([]*azp.RunnerV2, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runners.update"

	body := operations
	var resp *azp.RunnersListV2
	err := rs.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		rs.client.url.getUpdateRunnersURL(anyRunnerGroupID),
		body,
		&resp,
		rs.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONPatchContentType()))...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "the update runners request cannot be made"))
	}

	return resp.Value, nil
}

func (rs *RunnersService) GetRunner(ctx context.Context, id int64) (*azp.RunnerV2, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runners.get"

	var resp *azp.RunnerV2
	err := rs.http.Do(
		ctx,
		opname,
		http.MethodGet,
		rs.client.url.getRunnerURL(anyRunnerGroupID, id),
		nil,
		&resp,
		rs.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (rs *RunnersService) GetAccessPolicy(ctx context.Context) (*azp.AccessPolicy, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runners.accessPolicy"

	var resp *azp.AccessPolicy
	err := rs.http.Do(
		ctx,
		opname,
		http.MethodGet,
		rs.client.url.getRunnersAccessPolicyURL(defaultRunnerGroupID),
		nil,
		&resp,
		rs.client.withDefaultOpts(ctx)...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

// UpdateAccesPolicy is a JSON API endpoint that takes a list of operations (replace, add or remove).
// The permission field can be Replaced. But the selected_repos field can only have add or remove, which is why those operations are separate.
func (rs *RunnersService) UpdateAccessPolicy(ctx context.Context, permissionOp azp.PermissionOp, addReposOp azp.SelectedReposOp, removeReposOp azp.SelectedReposOp) (*azp.AccessPolicy, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runners.updateAccessPolicy"

	body := []any{permissionOp}

	// If add and remove repos have anything in them, we include in the request.
	if len(addReposOp.Value) > 0 {
		body = append(body, addReposOp)
	}

	if len(removeReposOp.Value) > 0 {
		body = append(body, removeReposOp)
	}

	var resp *azp.AccessPolicy
	err := rs.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		rs.client.url.getRunnersAccessPolicyURL(defaultRunnerGroupID),
		body,
		&resp,
		rs.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONPatchContentType()))...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "the update access policy request cannot be made"))
	}

	return resp, nil
}

func (rs *RunnersService) DeleteRunner(ctx context.Context, id int64) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runners.delete"

	validator := func(r *http.Response) (bool, error) {
		_, err := azp.ResponseValidator()(r)
		if err == nil && r.StatusCode == http.StatusNoContent {
			return false, nil
		}

		// err could still be nil here for 200s that aren't 204
		if err != nil {
			err = errs.Wrapf(err, "runner delete returned %d status code, expected 204", r.StatusCode)
		}

		retryable := r.StatusCode >= 500
		return retryable, err
	}

	err := rs.http.Do(
		ctx,
		opname,
		http.MethodDelete,
		rs.client.url.getDeleteRunnerURL(anyRunnerGroupID, id),
		nil,
		nil,
		rs.client.withDefaultOpts(ctx,
			httpclient.WithValidator(validator),
		)...,
	)
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "the delete runners request cannot be made"))
	}

	return nil
}

func (rs *RunnersService) GenerateJITRunnerConfig(ctx context.Context, settings *azp.JITRunnerSettings) (*azp.JITRunnerConfig, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runners.jitConfig"

	validator := func(r *http.Response) (bool, error) {
		_, err := azp.ResponseValidator()(r)
		if err == nil && r.StatusCode == http.StatusOK {
			return false, nil
		}

		if err != nil {
			err = errs.Wrapf(err, "generate jit runner returned %d status code, expected %d", r.StatusCode, http.StatusOK)
		}

		retryable := r.StatusCode >= 500
		return retryable, err
	}

	var resp *azp.JITRunnerConfig
	err := rs.http.Do(
		ctx,
		opname,
		http.MethodPost,
		rs.client.url.getJITRunnerConfigURL(),
		settings,
		&resp,
		rs.client.withDefaultOpts(
			ctx,
			httpclient.WithValidator(validator),
			httpclient.WithRequestOptions(launchhttp.WithJSONContentType()),
		)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "the generate jit runner request cannot be made"))
	}

	return resp, nil
}

func (rs *RunnersService) GetRunnerRegistrationCredentials(ctx context.Context, ownerID types.GlobalID, billingOwnerID types.GlobalID, tenantSlug string) (*azp.RunnerRegistrationCredentials, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runners.registration"

	metadata := &azp.RunnerAdminTokenMetadata{
		OwnerID:        ownerID.String(),
		BillingOwnerID: billingOwnerID.String(),
	}

	if tenantSlug != "" {
		metadata.TenantSlug = tenantSlug
	}

	var resp *azp.RunnerRegistrationCredentials
	err := rs.http.Do(
		ctx,
		opname,
		http.MethodPost,
		rs.client.url.getRunnerRegistrationURL(),
		metadata,
		&resp,
		rs.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONContentType()))...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "the runner registration request cannot be made"))
	}

	if !resp.IsValid() {
		return nil, tracing.RecordError(span, errors.New("the runner registration response is invalid"))
	}

	if !(rs.client.ghTwirpClient.IsFeatureEnabledForActor(ctx, github.PlumbRunnerHostURL, ownerID)) {
		resp.HostURL = rs.client.url.getExternalOrgServiceBaseURL()
	}

	return resp, nil
}

func (rs *RunnersService) ListDownloads(ctx context.Context) ([]*azp.Download, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runners.listDownloads"

	var resp *azp.DownloadsList
	err := rs.http.Do(
		ctx,
		opname,
		http.MethodGet,
		rs.client.url.getListDownloadsURL(),
		nil,
		&resp,
		rs.client.withDefaultOpts(ctx)...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}
