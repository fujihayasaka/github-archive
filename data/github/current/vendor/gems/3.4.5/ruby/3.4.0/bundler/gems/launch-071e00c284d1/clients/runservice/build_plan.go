package runservice

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"

	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/clients/utils"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"

	"github.com/github/actions-expressions/go/data"
	parser "github.com/github/actions-workflow-parser/go"

	runservice "github.com/github/actions-proto/gen/go/run-service/api/twirp/v1"

	"github.com/github/launch/pkg/expressions"
	"github.com/github/launch/receiver"
	"github.com/github/launch/workflowbuild/build"
)

// TODO: Parse down this argument list to only the fields we need once we have fleshed out plan generation more fully
func buildPlan(
	ctx context.Context,
	obs *observability.Observability,
	workflowTemplate *parser.WorkflowTemplate,
	wfb *build.WorkflowBuild,
	md *metadata.WorkflowMetadata,
	css *types.CheckSuiteState,
	receiverURL string,
	receiverPublicURL string,
	resultsReceiverURL string,
	secretSource string,
	secretsUnencrypted map[string]string,
	variables map[string]string,
	features map[string]bool,
	repoTenantInfo *types.RepositoryTenantInfo,
) (*runservice.StartPlanRequest, error) {
	planID := wfb.ExecutionID.String()

	preJobURL, err := receiver.GetPreJobRequestURL(receiverURL, wfb.SigningKey.WorkflowID, wfb.SigningKey.Timestamp)
	if err != nil {
		return nil, fmt.Errorf("failed to build prejob request url: %w", err)
	}

	workflowTemplateBytes, err := json.Marshal(workflowTemplate)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal workflowTemplate: %w", err)
	}

	githubContext, err := expressions.NewGitHubContext(ctx, obs, wfb, secretSource)
	if err != nil {
		return nil, fmt.Errorf("error decoding event for use in build payload: %w", err)
	}

	// We pass true for the allowDynamic parameter here because we do want to allow dynamic workflows to define inputs context
	inputsContext := expressions.NewInputsContext(workflowTemplate.InputTypes, wfb, githubContext, true)

	// Build up the expression context. This does _not_ include:
	// - env - workflow level env comes in from workflowTemplate.Env as template tokens and is evaluated during orchestration. job/step level env are added by the runner
	// - vars - these are passed in separately
	// - job - added by the runner
	// - jobs - outputs of previous reusable jobs, added in orchestration
	// - steps - added by the runner
	// - runner - added by the runner
	// - secrets - these are passed in separately
	// - strategy - added during orchestration from matrix evaluation
	// - matrix - added during orchestration from matrix evaluation
	// - needs - added during orchestration from dependency evaluation
	expressionDataBytes, err := json.Marshal(data.NewDictionary(
		data.Pair{Key: "github", Value: githubContext},
		data.Pair{Key: "inputs", Value: inputsContext},
	))
	if err != nil {
		return nil, fmt.Errorf("failed to marshal expression context: %w", err)
	}

	// This is orchestration context for partial rerun in Run-Service
	var rerunContext *runservice.RerunContext
	if wfb.RerunInfo != nil && len(wfb.RerunInfo.JobIDs) > 0 {
		rerunContext = &runservice.RerunContext{
			PlanId:                     wfb.RerunInfo.PlanID,
			RerunJobUuids:              wfb.RerunInfo.JobIDs,
			RerunOrchestrationContexts: wfb.PreviousOrchContexts,
		}
	}

	billingPlanOwner, err := buildBillingPlanOwnerPayload(wfb.ActionsBillingPlanOwner, md)
	if err != nil {
		return nil, fmt.Errorf("failed to build billing plan owner payload: %w", err)
	}

	// If the public URL (launch.actions.githubusercontent.com) is set, use it (dotcom only for now)
	// Otherwise, use the original URL (launch-receiver.githubapp.com)
	runnerReceiverURL := receiverURL
	if receiverPublicURL != "" {
		runnerReceiverURL = receiverPublicURL
	}

	// This will overwrite the slug in the results receiver URL in multitenant mode, otherwise it will be a no-op
	resultsReceiverURL, err = utils.FormatTenantURL(resultsReceiverURL, wfb.GitHubTenant.Slug)
	if err != nil {
		return nil, fmt.Errorf("failed to format results receiver url: %w", err)
	}

	req := &runservice.StartPlanRequest{
		PlanId: planID,
		Configuration: &runservice.Configuration{
			MainFilePath: wfb.WorkflowFilePath,
			Callbacks: &runservice.Callbacks{
				PreJobUrl:          preJobURL,
				SignatureKey:       base64.StdEncoding.EncodeToString(wfb.SigningKey.Key),
				ReceiverUrl:        runnerReceiverURL,
				ResultsReceiverUrl: resultsReceiverURL,
			},
			OidcConfig: &runservice.OIDCConfig{
				SubClaimCustomizationTemplate: wfb.RunEnvironment.OidcSubClaimCustomizationTemplate,
				CustomizeEnterpriseIssuer:     wfb.RunEnvironment.CustomizeEnterpriseOidcIssuer,
			},
		},
		WorkflowTemplate: string(workflowTemplateBytes),
		ExpressionData:   string(expressionDataBytes),
		Variables:        variables,
		Secrets:          secretsUnencrypted,
		Context: &runservice.Context{
			GithubEventInfo:       buildGitHubEventInfo(wfb),
			Repository:            wfb.RunEnvironment.Repository.String(),
			RepositoryId:          wfb.RunEnvironment.RepositoryID.String(),
			RepositoryDatabaseId:  wfb.RunEnvironment.RepositoryDatabaseID,
			PrivateRepository:     wfb.RunEnvironment.PrivateRepository,
			ForkedRepository:      wfb.RunEnvironment.ForkedRepository,
			OwnerCreatedAt:        wfb.RunEnvironment.OwnerCreatedAt.String(),
			ParentRepositoryOwner: wfb.RunEnvironment.ParentRepository.Owner,
			ParentRepositoryName:  wfb.RunEnvironment.ParentRepository.Name,
			RepositoryTier:        int64(wfb.RunEnvironment.RepositoryTier),
			ForkedPullRequest:     wfb.RunEnvironment.ForkedPullRequest,
			BillingPlanOwner:      billingPlanOwner,
			Properties:            &runservice.Properties{RepoSelfHostedRunnersDisabled: wfb.RunEnvironment.SelfHostedRunnersDisabled},
		},
		RerunContext: rerunContext,
		Features:     features,
	}

	if repoTenantInfo != nil {
		req.Context.RepositoryTenantInfo = repoTenantInfo.RepoTenantInfo
		req.Context.OrganizationTenantInfo = repoTenantInfo.OwnerTenantInfo
		req.Context.EnterpriseTenantInfo = repoTenantInfo.EnterpriseTenantInfo
	}

	// These fields are used for reporting usage (billing) data to Results service
	if md != nil {
		req.Context.GithubEventInfo.InvokingUserId = md.InvokingUser.GlobalRelayID
		req.Context.GithubEventInfo.InvokingUserName = md.InvokingUser.Login
		req.Context.GithubEventInfo.InvokingUserDatabaseId = int64(md.InvokingUser.GetID())
	}

	// These fields are used for reporting usage (billing) data to Results service
	if css != nil {
		req.Context.WorkflowName = css.FlowIdentifier
		req.Context.WorkflowBuildDatabaseId = css.WorkflowBuildDatabaseID
		req.Context.GithubEventInfo.InvokingEventRef = css.EventRef.String()
		req.Context.GithubEventInfo.InvokingEventSha = css.EventSHA.String()
	}

	return req, nil
}

func buildBillingPlanOwnerPayload(actionsBillingPlanOwner build.ActionsBillingPlanOwner, workflowMetadata *metadata.WorkflowMetadata) (*runservice.BillingPlanOwner, error) {
	payload := &runservice.BillingPlanOwner{
		Id:      actionsBillingPlanOwner.ID.String(),
		Name:    actionsBillingPlanOwner.Name,
		PlanSku: actionsBillingPlanOwner.PlanSKU,
		Type:    actionsBillingPlanOwner.Type,
		// TODO Add into proto (https://github.com/github/c2c-actions-experience/issues/7305)
		// TenantID:   actionsBillingPlanOwner.TenantID,
		TenantName: actionsBillingPlanOwner.TenantName,
	}

	// Decode the database ID from the GlobalID of the PlanOwner for audit log.
	_, databaseID, err := actionsBillingPlanOwner.ID.Decode()
	if err != nil {
		return nil, fmt.Errorf("failed to decode billing plan owner id: %w", err)
	}

	payload.DatabaseId = databaseID

	// OrganizationTenantName is only used when PlanOwner is a Business (aka Enterprise account)
	if actionsBillingPlanOwner.Type == "Business" {
		// We know that RepositoryOwner is an Organization, because PlanOwner is a business
		payload.OrganizationId = actionsBillingPlanOwner.RepositoryOwnerID.String()
		payload.OrganizationName = actionsBillingPlanOwner.RepositoryOwnerName
		payload.OrganizationDatabaseId = actionsBillingPlanOwner.RepositoryOwnerDatabaseID
		// TODO Add into proto (https://github.com/github/c2c-actions-experience/issues/7305)
		// payload.OrganizationTenantID = actionsBillingPlanOwner.OrganizationTenantID
		payload.OrganizationTenantName = actionsBillingPlanOwner.OrganizationTenantName
	}

	if workflowMetadata != nil && workflowMetadata.CustomerID != nil {
		// customer_id is used for billing usage data.
		payload.CustomerId = *workflowMetadata.CustomerID
	}

	return payload, nil
}
