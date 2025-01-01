package azpclient

import (
	"context"
	"io"
	"net/http"
	"strings"

	"github.com/google/uuid"
	errs "github.com/pkg/errors"

	"github.com/golang/protobuf/ptypes/wrappers"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/types"
)

type LargerRunnersService struct {
	client *Client
	http   *httpclient.Client
}

func (p *LargerRunnersService) ReportRunnerAdminEvent(ctx context.Context, name string, data map[string]string) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.report_admin_event"

	type adminEventRequest struct {
		Name string            `json:"name"`
		Data map[string]string `json:"data"`
	}

	body := &adminEventRequest{
		Name: name,
		Data: data,
	}

	headers := map[string]string{
		"X-TFS-AllowFaultIn": "false",
	}

	reqOpts := []launchhttp.RequestOption{
		launchhttp.WithHeaders(headers),
		launchhttp.WithJSONContentType(),
	}

	err := p.http.Do(
		ctx,
		opname,
		http.MethodPost,
		p.client.url.getRunnerReportAdminEventsURL(),
		body,
		nil,
		p.client.withDefaultOpts(ctx,
			httpclient.WithRequestOptions(reqOpts...),
			httpclient.WithValidator(func(r *http.Response) (bool, error) {
				if r.StatusCode == http.StatusNotFound {
					// Don't treat StatusNotFound as an error because we pass "X-TFS-AllowFaultIn" header
					// Vssf will return 404 if host doesn't exist yet
					return false, nil
				}

				return azp.ResponseValidator()(r)
			}),
		)...,
	)
	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

type listRunnerPoolsResponse struct {
	Count int64             `json:"count"`
	Value []*azp.RunnerPool `json:"value"`
}

func (p *LargerRunnersService) ListRunnerPools(ctx context.Context, entityID, ownerID, planOwnerID types.GlobalID, planOwnerTenant string, planOwnerTenantID string, isPrivateEntity bool, isPublicIPEnabled *wrappers.BoolValue) ([]*azp.RunnerPool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.listpools"

	var resp *listRunnerPoolsResponse
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getListRunnerPoolsURL(entityID, ownerID, planOwnerID, planOwnerTenant, planOwnerTenantID, isPrivateEntity, isPublicIPEnabled),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

func (p *LargerRunnersService) GetRunnerPool(ctx context.Context, poolID int64) (*azp.RunnerPool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.getpool"

	var resp *azp.RunnerPool
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getRunnerPoolURL(poolID),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (p *LargerRunnersService) CreateRunnerPool(ctx context.Context, poolDetails azp.CreatePoolRequest) (*azp.RunnerPool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.createpool"

	body := azp.CreatePoolRequest{
		Name:          poolDetails.Name,
		Platform:      poolDetails.Platform,
		RunnerGroupID: poolDetails.RunnerGroupID,
		Labels:        poolDetails.Labels,
		IsDev:         false,
		Image: azp.ImageKey{
			Source:  poolDetails.Image.Source,
			ID:      poolDetails.Image.ID,
			Version: poolDetails.Image.Version,
		},
		MachineSpecID:     poolDetails.MachineSpecID,
		IsPublicIPEnabled: poolDetails.IsPublicIPEnabled,
		MaximumRunners:    poolDetails.MaximumRunners,
		PersistentOSDisk:  poolDetails.PersistentOSDisk,
	}

	var resp *azp.RunnerPool
	err := p.http.Do(
		ctx,
		opname,
		http.MethodPost,
		p.client.url.getRunnerPoolsURL(),
		body,
		&resp,
		p.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONContentType()))...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (p *LargerRunnersService) UpdateRunnerPool(ctx context.Context, poolID int64, runnerPoolUpdate azp.UpdatePoolRequest) (*azp.RunnerPool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.updatepool"

	body := azp.UpdatePoolRequest{
		Name:              runnerPoolUpdate.Name,
		Platform:          runnerPoolUpdate.Platform,
		RunnerGroupID:     runnerPoolUpdate.RunnerGroupID,
		Labels:            runnerPoolUpdate.Labels,
		IsDev:             false,
		Image:             runnerPoolUpdate.Image,
		MachineSpecID:     runnerPoolUpdate.MachineSpecID,
		IsPublicIPEnabled: runnerPoolUpdate.IsPublicIPEnabled,
		MaximumRunners:    runnerPoolUpdate.MaximumRunners,
	}

	var resp *azp.RunnerPool
	err := p.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		p.client.url.getRunnerPoolURL(poolID),
		body,
		&resp,
		p.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONPatchContentType()))...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (p *LargerRunnersService) DeleteRunnerPool(ctx context.Context, poolID int64) (*azp.RunnerPool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.delete"

	validator := func(r *http.Response) (bool, error) {
		_, err := azp.ResponseValidator()(r)
		if err == nil && r.StatusCode == http.StatusAccepted {
			return false, nil
		}

		// err could still be nil here for 200s that aren't 202
		if err != nil {
			err = errs.Wrapf(err, "the delete runner pool request returned %d status code, expected 202", r.StatusCode)
		}

		retryable := r.StatusCode >= 500
		return retryable, err
	}

	var resp *azp.RunnerPool
	err := p.http.Do(
		ctx,
		opname,
		http.MethodDelete,
		p.client.url.getRunnerPoolURL(poolID),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx,
			httpclient.WithValidator(validator),
		)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (p *LargerRunnersService) CreateImageDefinition(ctx context.Context, osType string, poolName string) (*azp.ImageDefinition, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.createimagedefinition"

	type createImageDefinitionPayload struct {
		Name   string `json:"name"`
		OsType string `json:"osType"`
	}

	// Create Definition
	createBody := createImageDefinitionPayload{
		Name:   poolName + "-image-" + uuid.New().String(),
		OsType: osType,
	}

	var createResp *azp.ImageDefinition
	err := p.http.Do(
		ctx,
		opname,
		http.MethodPost,
		p.client.url.getRunnerCustomImagesURL(),
		createBody,
		&createResp,
		p.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONContentType()))...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "posting image definition"))
	}

	return createResp, nil
}

type listImageDefinitionsResponse struct {
	Count int64                  `json:"count"`
	Value []*azp.ImageDefinition `json:"value"`
}

func (p *LargerRunnersService) ListImageDefinitions(ctx context.Context) ([]*azp.ImageDefinition, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.listimagedefinitions"

	var resp *listImageDefinitionsResponse
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getRunnerCustomImagesURL(),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

func (p *LargerRunnersService) GetImageDefinition(ctx context.Context, imageDefinitionID int64) (*azp.ImageDefinition, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.getimagedefinition"

	var resp *azp.ImageDefinition
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getRunnerCustomImageURL(imageDefinitionID),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

// Delete image definition
func (p *LargerRunnersService) DeleteImageDefinition(ctx context.Context, imageDefinitionID int64) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.deleteimagedefinition"

	validator := func(r *http.Response) (bool, error) {
		_, err := azp.ResponseValidator()(r)
		if err == nil && r.StatusCode == http.StatusAccepted {
			return false, nil
		}

		if err != nil {
			err = errs.Wrapf(err, "the delete image definition request returned %d status code, expected 202", r.StatusCode)
		}

		retryable := r.StatusCode >= 500
		return retryable, err
	}

	err := p.http.Do(
		ctx,
		opname,
		http.MethodDelete,
		p.client.url.getRunnerCustomImageURL(imageDefinitionID),
		nil,
		nil,
		p.client.withDefaultOpts(ctx,
			httpclient.WithValidator(validator),
		)...,
	)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

type createImageVersionPayload struct {
	Version      string `json:"Version"`
	SourceSasURI string `json:"sourceSasUri"`
}

// Create new image version for the pool
func (p *LargerRunnersService) CreateImageVersion(ctx context.Context, imageSasURI string, imageDefinitionID int64) (*azp.ImageVersion, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	versionPayload := createImageVersionPayload{
		SourceSasURI: imageSasURI,
	}
	opname := "runner.createimageversion"

	var versionResponse *azp.ImageVersion
	err := p.http.Do(
		ctx,
		opname,
		http.MethodPost,
		p.client.url.getRunnerCustomImageVersionsURL(imageDefinitionID, nil),
		versionPayload,
		&versionResponse,
		p.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONContentType()))...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "posting image version"))
	}

	return versionResponse, nil
}

// List all image versions for the pool
func (p *LargerRunnersService) ListImageVersions(ctx context.Context, imageDefinitionID int64, pattern *string) ([]*azp.ImageVersion, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.listimageversions"
	url := p.client.url.getRunnerCustomImageVersionsURL(imageDefinitionID, pattern)

	var resp *azp.ImageVersionsList
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		url,
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

// Get exact image version for pool
func (p *LargerRunnersService) GetImageVersion(ctx context.Context, imageDefinitionID int64, version string) (*azp.ImageVersion, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.getimageversion"

	var versionResponse *azp.ImageVersion
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getRunnerCustomImageVersionURL(imageDefinitionID, version),
		nil,
		&versionResponse,
		p.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONContentType()))...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return versionResponse, nil
}

// Delete exact image version for pool
func (p *LargerRunnersService) DeleteImageVersion(ctx context.Context, imageDefinitionID int64, version string) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.deleteimageversion"

	validator := func(r *http.Response) (bool, error) {
		_, err := azp.ResponseValidator()(r)
		if err == nil && r.StatusCode == http.StatusAccepted {
			return false, nil
		}

		if err != nil {
			err = errs.Wrapf(err, "the delete image version request returned %d status code, expected 202", r.StatusCode)
		}

		retryable := r.StatusCode >= 500
		return retryable, err
	}

	err := p.http.Do(
		ctx,
		opname,
		http.MethodDelete,
		p.client.url.getRunnerCustomImageVersionURL(imageDefinitionID, version),
		nil,
		nil,
		p.client.withDefaultOpts(ctx,
			httpclient.WithValidator(validator),
		)...,
	)
	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

func (p *LargerRunnersService) ListPoolAgents(ctx context.Context, poolID int64) ([]*azp.RunnerV2, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.listpoolagents"

	var resp *azp.RunnersListV2
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getRunnerPoolAgentsURL(poolID),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

func (p *LargerRunnersService) ListMachineSpecs(ctx context.Context) ([]*azp.MachineSpec, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.listmachinespecs"

	var resp *azp.MachineSpecsList
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getRunnerMachineSpecsURL(),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

func (p *LargerRunnersService) ListCuratedImages(ctx context.Context) ([]*azp.Image, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.listcuratedimages"

	var resp *azp.ImagesList
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getRunnerCuratedImagesURL(),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

func (p *LargerRunnersService) ListMarketplaceImages(ctx context.Context) ([]*azp.Image, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.listmarketplaceimages"

	var resp *azp.ImagesList
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getRunnerMarketplaceImagesURL(),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

func (p *LargerRunnersService) ListRunnerLabels(ctx context.Context) ([]string, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.listrunnerlabels"

	var resp *azp.RunnerLabelsList
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getRunnerLabelsURL(),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

func (p *LargerRunnersService) GetTenantInfo(ctx context.Context) (*azp.TenantInfo, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if p.client.url.runnersServiceIsDirectScaleUnitURL {
		// Runner scale unit is already backfilled for some Runner hosts
		// Just return direct scale unit url in this case
		return &azp.TenantInfo{
			TenantID:        p.client.url.tenantID,
			RunnerScaleUnit: p.client.url.runnersServiceBaseURL,
		}, nil
	}

	// If runner scale unit is not backfilled yet, we have to perform API request to base runner url to figure out scale unit

	// Use "X-TFS-AllowFaultIn" to avoid host fault-in in case if host doesn't use Runner yet
	headers := map[string]string{
		"X-TFS-AllowFaultIn": "false",
	}

	var resp *azp.RunnerServiceHostInfo
	err := p.http.Do(
		ctx,
		"runner.getscaleunit",
		http.MethodGet,
		p.client.url.getRunnerScaleUnitInfoURL(),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx,
			httpclient.WithRequestOptions(launchhttp.WithJSONContentType(), launchhttp.WithHeaders(headers)),
			httpclient.WithValidator(func(r *http.Response) (bool, error) {
				if r.StatusCode == http.StatusNotFound {
					// Don't treat StatusNotFound as an error because we pass "X-TFS-AllowFaultIn" header
					// Vssf will return 404 if host doesn't exist yet
					r.Body = io.NopCloser(strings.NewReader("{}"))
					return false, nil
				}

				return azp.ResponseValidator()(r)
			}),
		)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	runnerScaleUnitURL := ""
	if resp != nil && resp.DeploymentID != "" {
		if url, ok := scaleUnitMap[resp.DeploymentID]; ok {
			runnerScaleUnitURL = url
		}
	}

	return &azp.TenantInfo{
		TenantID:        p.client.url.tenantID,
		RunnerScaleUnit: runnerScaleUnitURL,
	}, nil
}

func (p *LargerRunnersService) ListBetaFeatures(ctx context.Context) ([]*azp.BetaFeature, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.listbetafeatures"

	var resp *azp.BetaFeaturesList
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getRunnerBetaFeaturesURL(),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

func (p *LargerRunnersService) GetBetaFeature(ctx context.Context, featureName string) (*azp.BetaFeature, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.getbetafeature"

	var resp *azp.BetaFeature
	err := p.http.Do(
		ctx,
		opname,
		http.MethodGet,
		p.client.url.getRunnerBetaFeatureURL(featureName),
		nil,
		&resp,
		p.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (p *LargerRunnersService) SetBetaFeature(ctx context.Context, featureName string, enabled bool) (*azp.BetaFeature, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runner.setbetafeature"

	type setBetaFeaturePayload struct {
		Enabled bool `json:"enabled"`
	}

	// Create Definition
	body := setBetaFeaturePayload{
		Enabled: enabled,
	}

	var resp *azp.BetaFeature
	err := p.http.Do(
		ctx,
		opname,
		http.MethodPost,
		p.client.url.getRunnerBetaFeatureURL(featureName),
		body,
		&resp,
		p.client.withDefaultOpts(ctx, httpclient.WithRequestOptions(launchhttp.WithJSONContentType()))...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}
