package runservice

import (
	"context"
	"fmt"
	"net/http"

	"github.com/twitchtv/twirp"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/go-kvp"

	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/requestid"
	"github.com/github/launch/utils/twirputils"
	"github.com/github/launch/utils/useragent"

	runservice "github.com/github/actions-proto/gen/go/run-service/api/twirp/v1"
	"github.com/github/go-twirp/client/auth"
	twirprequestid "github.com/github/go-twirp/client/requestid"
	"github.com/pkg/errors"

	parser "github.com/github/actions-workflow-parser/go"
	"github.com/github/actions-workflow-parser/go/template"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/wfparser"
	"github.com/github/launch/workflowbuild/build"
)

type Client interface {
	// TODO: Reduce the # of arguments passed in here once we have a better idea of what is required for full plan generation.
	StartPlan(
		ctx context.Context,
		wfb *build.WorkflowBuild,
		md *metadata.WorkflowMetadata,
		css *types.CheckSuiteState,
		receiverURL string,
		receiverPublicUrl string,
		resultsReceiverURL string,
		secretSource string,
		secretsUnencrypted map[string]string,
		variables map[string]string,
		features map[string]bool,
		repoTenantInfo *types.RepositoryTenantInfo,
		coalesceRootFileRef bool,
		parseOptions ...func(*template.ParseOptions),
	) (string, string, error)
}

type client struct {
	runServiceClient runservice.RunService
	ghTwirpClient    ghtwirp.Client
	obs              *observability.Observability
	isMultiTenant    bool
	env              launchconfig.AppEnv
}

func NewClient(env launchconfig.AppEnv, secrets []string, breaker *circuit.Breaker, httpClient *http.Client, obs *observability.Observability, address string, twirpOpts []twirp.ClientOption, ghTwirpClient ghtwirp.Client, isMultiTenant bool) (Client, error) {
	runServiceRetryClient := ahttp.NewRetryClient(breaker, obs.Statter, httpClient, "runservicetwirp")
	runServiceHMAC := secrets[len(secrets)-1]
	signingHTTPClient, err := auth.NewRequestHMACSigner(
		runServiceHMAC,
		runServiceRetryClient,
	)
	if err != nil {
		return nil, errors.Wrap(err, "Could not create twirp HMAC signer for run service")
	}
	runServiceClient := runservice.NewRunServiceProtobufClient(address, twirprequestid.NewForwarder(signingHTTPClient), twirpOpts...)
	return &client{
		runServiceClient: runServiceClient,
		ghTwirpClient:    ghTwirpClient,
		obs:              obs,
		isMultiTenant:    isMultiTenant,
		env:              env,
	}, nil
}

// StartPlan starts a plan and returns the plan ID and run stamp URL, or an error.
func (c *client) StartPlan(
	ctx context.Context,
	wfb *build.WorkflowBuild,
	md *metadata.WorkflowMetadata,
	css *types.CheckSuiteState,
	receiverURL string,
	receiverPublicUrl string,
	resultsReceiverURL string,
	secretSource string,
	secretsUnencrypted map[string]string,
	variables map[string]string,
	features map[string]bool,
	repoTenantInfo *types.RepositoryTenantInfo,
	coalesceRootFileRef bool,
	parseOptions ...func(*template.ParseOptions),
) (string, string, error) {
	ctx, err := ghtenant.ContextWithTwirpTenantHeaders(ctx, c.isMultiTenant, c.obs.Logger)
	if err != nil {
		c.obs.Error(ctx, errors.Wrap(err, "error setting tenant id or tenant slug").Error())
		return "", "", err
	}

	workflowTemplate, err := wfparser.LoadWorkflow(ctx, c.obs, wfb.WorkflowFilePath, wfparser.NewFileProvider(ctx, c.obs, wfb.WorkflowReferencedFiles(coalesceRootFileRef)), wfb.RunEnvironment.DefaultWorkflowPermissions, parseOptions...)
	if err != nil {
		return "", "", fmt.Errorf("failed to load workflow: %w", err)
	}

	// Filter unreferenced secrets before sending to run service
	secretsUnencrypted, err = parser.FilterWorkflowSecrets(workflowTemplate, secretsUnencrypted)
	if err != nil {
		return "", "", fmt.Errorf("failed to filter workflow secrets: %w", err)
	}

	// Filter unreferenced variables before sending to run service
	variables, err = parser.FilterWorkflowVariables(workflowTemplate, variables)
	if err != nil {
		return "", "", fmt.Errorf("failed to filter workflow variables: %w", err)
	}

	err = wfparser.CheckErrors(workflowTemplate)
	if err != nil {
		return "", "", err
	}

	plan, err := buildPlan(ctx, c.obs, workflowTemplate, wfb, md, css, receiverURL, receiverPublicUrl, resultsReceiverURL, secretSource, secretsUnencrypted, variables, features, repoTenantInfo)
	if err != nil {
		return "", "", fmt.Errorf("failed to build plan: %w", err)
	}

	ctx, err = twirputils.ContextWithTwirpHeader(ctx, "User-Agent", useragent.GetUserAgent(c.env.String()))
	if err != nil {
		return "", "", fmt.Errorf("failed to set user agent: %w", err)
	}

	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	// This log can help with understanding any retries that occur
	c.obs.Log(ctx, "Starting plan",
		// Note: gh.launch.workflow_run.id should already be injected into context by build_invoker
		kvp.String("gh.actions.plan_id", plan.PlanId))

	res, err := c.runServiceClient.StartPlan(ctx, plan)
	if err != nil {
		return "", "", fmt.Errorf("failed to start plan: %w", err)
	}

	return res.GetPlanId(), res.GetRunStampUrl(), nil
}
