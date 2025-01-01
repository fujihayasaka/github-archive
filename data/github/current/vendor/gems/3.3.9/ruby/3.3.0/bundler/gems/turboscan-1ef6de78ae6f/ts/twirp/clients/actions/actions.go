// Package actions is the client communication with the Launch service, AKA actions.
package actions

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-twirp/v2/client/auth"
	"github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/services/pbtypes"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/o11y"
)

type DynamicWorkflowRunner interface {
	RunDynamicWorkflow(context.Context, *ts.CodeqlRun) error
}

type LaunchClient struct {
	twirpAddr     string
	client        deploy.LaunchDeploymentService
	logger        log.Logger
	hooks         *twirp.ClientHooks
	requireTenant bool
}

func New(cfg *config.Config, opts ...Option) (*LaunchClient, error) {
	twirpAddr := cfg.LaunchDeployerAddr
	hmacSecret := cfg.LaunchDeployerHMAC

	hmac, err := auth.NewRequestHMACSigner(hmacSecret, http.DefaultClient)
	if err != nil {
		return nil, err
	}

	clientHooks := &twirp.ClientHooks{
		RequestPrepared: func(ctx context.Context, req *http.Request) (context.Context, error) {
			tenant.Forward(req)
			requestid.Forward(req)
			return ctx, nil
		},
	}

	protoClient := deploy.NewLaunchDeploymentServiceProtobufClient(twirpAddr, hmac, twirp.WithClientHooks(clientHooks))

	client := &LaunchClient{
		twirpAddr:     twirpAddr,
		client:        protoClient,
		hooks:         clientHooks,
		requireTenant: cfg.IsProximaEnv(),
	}

	for _, opt := range opts {
		opt(client)
	}

	return client, nil
}

func repoid(in ts.RepositoryGRID) *pbtypes.Identity {
	return &pbtypes.Identity{GlobalId: string(in)}
}

func actorid(in ts.ActorGRID) *pbtypes.Identity {
	return &pbtypes.Identity{GlobalId: string(in)}
}

var ErrMissingTenant = errors.New("tenant not set")

// RunDynamicWorkflow triggers the Actions run. If successful, it updates the run with the
// ExecutionID and WorkflowRunID.
func (c *LaunchClient) RunDynamicWorkflow(ctx context.Context, run *ts.CodeqlRun) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// The tenant information is required in Proxima because Actions needs to callback to gh/gh.
	if c.requireTenant && (tenant.GetTenant(ctx) == "" || tenant.GetTenantID(ctx) == "") {
		return ErrMissingTenant
	}

	// Log this to make sure all our flows are setting this value.
	// Right now it is not a required information, so logging it is enough.
	if c.logger != nil && run.OwnerID == 0 {
		c.logger.Error("RunDynamicWorkflow: OwnerID is 0", kvp.Uint64("gh.turboscan.ma.run_id", uint64(run.ID)), run.RepositoryID.AsKVP())
	}

	inputs := map[string]string{
		// The input `code_scanning_ref` is used to workaround Actions not setting the GITHUB_REF for refs/pull/N/head refs.
		"code_scanning_ref": run.Ref.String(),
		// `code_scanning_run_name` is used to populate the run name of the workflow in the ui
		"code_scanning_run_name": run.RunName(),
		// Set CODE_SCANNING_IS_ANALYZING_DEFAULT_BRANCH
		"code_scanning_is_analyzing_default_branch": fmt.Sprint(run.InDefaultBranch),
	}

	// CODE_SCANNING_WORKFLOW_FILE is used to to expose the WF file to the CodeQLAction so it is able to extract information from it
	workflow, err := run.CompressedWorkflow()
	if err != nil {
		return errors.Wrap(err, "failed to compress workflow")
	}
	inputs["code_scanning_workflow_file"] = workflow

	// CODE_SCANING_CODEQL_PACKS is used to expose the codeql packs to the CodeQLAction
	// so that it can use them to run the analysis
	inputs["code_scanning_codeql_packs"] = run.CodeqlPacks.AsWorkflowString()

	req := newRequest(run, inputs)

	resp, err := c.client.RunDynamicWorkflow(ctx, req)
	if err != nil {
		if strings.Contains(err.Error(), "could not resolve ref for dynamic workflow") {
			return ts.ErrCouldNotResolveRef
		}
		if strings.Contains(err.Error(), "spammy user") {
			return ts.ErrSpammyUser
		}
		return errors.Wrap(err, "failed to run dynamic workflow")
	}

	// Update the run information
	run.ExecutionID = resp.ExecutionId
	run.WorkflowRunID = ts.WorkflowRunEID(resp.WorkflowRunId)
	run.Status = ts.CodeqlRunStatus_INPROGRESS
	return nil
}

func newRequest(run *ts.CodeqlRun, inputs map[string]string) *deploy.RunDynamicWorkflowRequest {
	return &deploy.RunDynamicWorkflowRequest{
		// These parameters are the same across all calls
		IntegrationName: ts.ManagedAnalysisIntegrationName,
		Slug:            ts.ManagedAnalysisActionsSlug,
		Visibility:      deploy.Visibility_VISIBLE,

		// These parameters depend on the run
		RepositoryId: repoid(run.RepositoryGRID),
		ActorId:      actorid(run.ActorGRID),
		ActorLogin:   run.ActorLogin,
		WorkflowName: run.WorkflowName(),
		Workflow:     run.Workflow,
		Ref:          run.Ref.String(),
		Sha:          run.Sha.String(),
		Inputs:       inputs,
		OwnerId:      int64(run.OwnerID),
	}
}
