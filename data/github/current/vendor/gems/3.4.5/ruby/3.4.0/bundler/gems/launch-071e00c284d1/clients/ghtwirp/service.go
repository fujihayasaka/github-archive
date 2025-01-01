package ghtwirp

import (
	"context"

	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	twirpTrustTiers "github.com/github/monolith-twirp-trusttiers/proto/trusttier/v1"

	ghactions "github.com/github/launch/proto/monolith/core/v1"
)

// ActorsService pares down the ActorsAPI in Twirp so we are only consuming
// methods that we need from it, not everything.
type ActorsService interface {
	GetActorsInfo(context.Context, *ghactions.GetActorsInfoRequest) (*ghactions.GetActorsInfoResponse, error)
}

type ChecksService interface {
	CreateExecution(context.Context, *ghactions.CreateExecutionRequest) (*ghactions.CreateExecutionResponse, error)
	UpdateWorkflowRun(context.Context, *ghactions.UpdateWorkflowRunRequest) (*ghactions.UpdateWorkflowRunResponse, error)
	UpdateWorkflowRunExecution(context.Context, *ghactions.UpdateWorkflowRunExecutionRequest) (*ghactions.UpdateWorkflowRunExecutionResponse, error)
	FindPreviousWorkflowRunToReuse(context.Context, *ghactions.FindPreviousWorkflowRunToReuseRequest) (*ghactions.FindPreviousWorkflowRunToReuseResponse, error)
}

// UsersService pares down the UsersAPI in Twirp so we are only consuming
// methods that we need from it, not everything.
type UsersService interface {
	GetOrganizationOwner(context.Context, *ghactions.GetOrganizationOwnerRequest) (*ghactions.GetOrganizationOwnerResponse, error)
	GetRepositories(context.Context, *ghactions.GetRepositoriesRequest) (*ghactions.GetRepositoriesResponse, error)
	IsVisibleUser(context.Context, *ghactions.IsVisibleUserRequest) (*ghactions.IsVisibleUserResponse, error)
	ShouldPullRequestWorkflowsRunForUser(context.Context, *ghactions.ShouldPullRequestWorkflowsRunForUserRequest) (*ghactions.ShouldPullRequestWorkflowsRunForUserResponse, error)
	GetUserByLogin(context.Context, *ghactions.GetUserByLoginRequest) (*ghactions.GetUserByLoginResponse, error)
}

// ReposService pares down the ReposAPI in Twirp so we are only consuming
// methods that we need from it, not everything.
type ReposService interface {
	CheckRepositoryActionsStatus(context.Context, *ghactions.CheckRepositoryActionsStatusRequest) (*ghactions.CheckRepositoryActionsStatusResponse, error)
	GetRepositoryOwners(context.Context, *ghactions.GetRepositoryOwnersRequest) (*ghactions.GetRepositoryOwnersResponse, error)
	GetCommitMessage(context.Context, *ghactions.GetCommitMessageRequest) (*ghactions.GetCommitMessageResponse, error)
	RetireNamespace(ctx context.Context, request *ghactions.RetireNamespaceRequest) (*ghactions.RetireNamespaceResponse, error)
	FindRepositoriesByName(ctx context.Context, request *ghactions.FindRepositoriesByNameRequest) (*ghactions.FindRepositoriesByNameResponse, error)
	GetAdditionalWorkflows(ctx context.Context, request *ghactions.GetAdditionalWorkflowsRequest) (*ghactions.GetAdditionalWorkflowsResponse, error)
	GetRepositoryEventDetails(ctx context.Context, request *ghactions.GetRepositoryEventDetailsRequest) (*ghactions.GetRepositoryEventDetailsResponse, error)
	GetRepositoryOwnerId(ctx context.Context, request *ghactions.GetRepositoryOwnerIdRequest) (*ghactions.GetRepositoryOwnerIdResponse, error)
	GetRepositoryVisibility(ctx context.Context, request *ghactions.GetRepositoryVisibilityRequest) (*ghactions.GetRepositoryVisibilityResponse, error)
}

// ActionsEnvironmentsService pares down the features ActionsAPI in Twirp for GitHub so we're
// only consuming methods as we need them.
type ActionsEnvironmentsService interface {
	ResolveActionsEnvironment(context.Context, *ghactions.ResolveActionsEnvironmentRequest) (*ghactions.ResolveActionsEnvironmentResponse, error)
	GetEnvironmentRepository(context.Context, *ghactions.GetEnvironmentRepositoryRequest) (*ghactions.GetEnvironmentRepositoryResponse, error)
}

// MonolithFeaturesService has the endpoints for checking features in the monolith
type MonolithFeaturesService interface {
	CheckGlobalFeature(context.Context, *twirpFeatures.CheckGlobalFeatureRequest) (*twirpFeatures.CheckGlobalFeatureResponse, error)
	CheckActorFeature(context.Context, *twirpFeatures.CheckActorFeatureRequest) (*twirpFeatures.CheckActorFeatureResponse, error)
	CheckActorFeatures(context.Context, *twirpFeatures.CheckActorFeaturesRequest) (*twirpFeatures.CheckActorFeaturesResponse, error)
	CheckActorsFeature(context.Context, *twirpFeatures.CheckActorsFeatureRequest) (*twirpFeatures.CheckActorsFeatureResponse, error)
}

// ActionsPoliciesService is an implementation of the Actions Policies API.
type ActionsPoliciesService interface {
	CheckActionsPolicy(context.Context, *ghactions.CheckActionsPolicyRequest) (*ghactions.CheckActionsPolicyResponse, error)
	CheckWorkflowsPolicy(context.Context, *ghactions.CheckWorkflowsPolicyRequest) (*ghactions.CheckWorkflowsPolicyResponse, error)
}

// TrusttiersService is an implementation of the Trust Tiers API.
type TrustTiersService interface {
	GetTrustTier(context.Context, *twirpTrustTiers.GetTrustTierRequest) (*twirpTrustTiers.GetTrustTierResponse, error)
}

// WorkflowDetailsService is an implementation of the Workflow Details API.
type WorkflowDetailsService interface {
	GetBillingDetails(context.Context, *ghactions.GetBillingDetailsRequest) (*ghactions.GetBillingDetailsResponse, error)
	GetBillingDetailsForEntity(context.Context, *ghactions.GetBillingDetailsForEntityRequest) (*ghactions.GetBillingDetailsForEntityResponse, error)
}

// AccountDetailsService is an implementation of the Account Details API.
type AccountDetailsService interface {
	GetAccountDetails(context.Context, *ghactions.GetAccountDetailsRequest) (*ghactions.GetAccountDetailsResponse, error)
	GetAccountDetailsForRepository(context.Context, *ghactions.GetAccountDetailsForRepositoryRequest) (*ghactions.GetAccountDetailsForRepositoryResponse, error)
}

// IntegrationsService is an implementation of the Integrations API.
type IntegrationsService interface {
	GetIntegrationJobSecrets(context.Context, *ghactions.GetIntegrationJobSecretsRequest) (*ghactions.GetIntegrationJobSecretsResponse, error)
}

// RefsService is an implementation of the Refs API.
type RefsService interface {
	IsDependabotAssociatedRef(context.Context, *ghactions.IsDependabotAssociatedRefRequest) (*ghactions.IsDependabotAssociatedRefResponse, error)
}

// GlobalIDService is an implementation of the Global Id API.
type GlobalIDService interface {
	GetNextGlobalId(context.Context, *ghactions.GetNextGlobalIdRequest) (*ghactions.GetNextGlobalIdResponse, error)
}

// ResolveActionsService is an implementation of the Resolve Actions API.
type ResolveActionsService interface {
	ResolveActions(context.Context, *ghactions.ResolveActionsRequest) (*ghactions.ResolveActionsResponse, error)
}

// WorkflowRunExecutionsService is an implementation of the Workflow Run Executions API.
type WorkflowRunExecutionsService interface {
	GetWorkflowRunExecution(context.Context, *ghactions.GetWorkflowRunExecutionRequest) (*ghactions.GetWorkflowRunExecutionResponse, error)
}
