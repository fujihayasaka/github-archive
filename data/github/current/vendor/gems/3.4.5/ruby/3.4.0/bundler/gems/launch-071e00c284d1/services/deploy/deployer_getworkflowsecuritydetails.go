package deploy

import (
	"context"
	"fmt"

	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/workflowbuild"

	"github.com/pkg/errors"
	errs "github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/services/deploy/workflowinvoker"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
)

func (s *service) GetWorkflowSecurityDetails(ctx context.Context, req *pb.GetWorkflowSecurityDetailsRequest) (*pb.GetWorkflowSecurityDetailsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	workflowID := req.GetWorkflowID()
	if workflowID == "" {
		err := svcerr.NewInvalidArgumentError("Request is not valid")
		s.cfg.Log.Report(ctx, errors.Wrap(err, "GetWorkflowID"), kvp.String("code.function", "GetWorkflowID"))
		return nil, err
	}

	workflowBuild, ok, err := s.cfg.WorkflowBuilds.GetDataForSecurityDetails(ctx, workflowID)
	if err != nil {
		s.cfg.Log.Report(ctx, errors.Wrap(err, "GetDataForSecurityDetails"), kvp.String("code.function", "GetDataForSecurityDetails"))
		return nil, svcerr.NewInternalError("Internal error")
	}
	if !ok {
		return nil, svcerr.NewNotFoundError("no such workflow")
	}

	// GitHubTenantID will be a nil pointer for non-multi-tenant modes.
	if s.IsMultiTenant {
		if workflowBuild.GitHubTenantID == nil {
			return nil, tracing.RecordError(span, errs.New("GitHub tenant id in workflow build security details must not be nil"))
		}

		ctx, err = ghtenant.ContextWithTenantID(ctx, *workflowBuild.GitHubTenantID, s.IsMultiTenant)
		if err != nil {
			return nil, tracing.RecordError(span, errs.Wrap(err, "expected valid GitHub tenant id to be set in workflow build security details"))
		}
	}

	ghe, err := workflowinvoker.EventFromPersistedPayload(workflowBuild.GetEvent(), workflowBuild.GetEventPayload())
	if err != nil {
		s.cfg.Log.Report(ctx, errors.Wrap(err, "ExtractGHE"), kvp.String("code.function", "ExtractGHE"))
		return nil, svcerr.NewInternalError("Internal error")
	}

	repoOwner := workflowBuild.WorkflowMetadata.RepositoryOwner
	ownerID := types.NilGlobalID
	if repoOwner != nil {
		ownerID = types.NewGlobalID(ctx, repoOwner.GlobalRelayID)
	}

	client, err := s.cfg.ClientFactory.NewClientForRepositoryOwner(ctx, workflowBuild.RepositoryID, ownerID)
	if err != nil {
		s.cfg.Log.Report(ctx, fmt.Errorf("failed to create client for repository owner: %w", err), kvp.String("code.function", "NewClientForRepositoryOwner"))
		return nil, svcerr.NewNotFoundError("Could not create a client for this request")
	}

	secretResponse, err := client.GetSecretPolicies(ctx, workflowBuild.RepositoryID)
	if err != nil {
		s.cfg.Log.Report(ctx, errors.Wrap(err, "GetSecretPolicies"), kvp.String("code.function", "GetSecretPolicies"))
		return nil, svcerr.NewNotFoundError("Could not retrieve ForkPRWorkflowsPolicy and CanUseEnvironments from GraphQL")
	}

	// below response to contain secretResponse as well once ff is removed, and secretResponse to be be cleaned up.
	var policiesResponse *github.Policies = &github.Policies{
		PublicForkPRWorkflowsPolicy: types.PublicForkPRWorkflowsInvalidPolicy,
	}

	if s.cfg.GithubTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, github.PublicForkPrWorkflowsPolicyFlag, workflowBuild.RepositoryID) {
		policiesResponse, err = client.GetPolicies(ctx, workflowBuild.RepositoryID)
		if err != nil {
			s.cfg.Log.Report(ctx, errors.Wrap(err, "GetPolicies"), kvp.String("code.function", "GetPolicies"))
			return nil, svcerr.NewNotFoundError("Could not retrieve WorkflowsPolicy from GraphQL")
		}
	}

	var workflowActor *metadata.WorkflowMetadataActor
	if workflowBuild.WorkflowMetadata != nil {
		workflowActor = workflowBuild.WorkflowMetadata.Actor
	}

	areActionsSecretsAllowed := false
	if workflowbuild.ActionsSecretSource == workflowbuild.DetermineSecretSource(ctx, s.cfg.Obs, workflowBuild.Event, ghe, secretResponse.ForkPRWorkflowsPolicy, workflowActor) {
		areActionsSecretsAllowed = true
	}

	areActionsEnvironmentSecretsAllowed := secretResponse.CanUseEnvironments && areActionsSecretsAllowed
	areActionsEnvironmentVariablesAllowed := secretResponse.CanUseEnvironments && workflowinvoker.ShouldSendVariables(workflowBuild.Event, ghe, secretResponse.ForkPRWorkflowsPolicy, policiesResponse.PublicForkPRWorkflowsPolicy)

	isIDTokenGenerationAllowed := workflowbuild.CanGenerateIDToken(workflowBuild.Event, ghe, secretResponse.ForkPRWorkflowsPolicy)

	return &pb.GetWorkflowSecurityDetailsResponse{
		AreActionsSecretsAllowed:              areActionsSecretsAllowed,
		AreActionsEnvironmentSecretsAllowed:   areActionsEnvironmentSecretsAllowed,
		AreActionsEnvironmentVariablesAllowed: areActionsEnvironmentVariablesAllowed,
		IsIDTokenGenerationAllowed:            isIDTokenGenerationAllowed,
	}, nil
}
