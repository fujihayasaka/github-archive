package ghtwirp

import (
	"context"

	"github.com/google/uuid"

	ghactions "github.com/github/launch/proto/monolith/core/v1"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/types"
)

var _ Client = (*enterpriseClient)(nil)

type enterpriseClient struct {
	client Client
}

// NewEnterpriseClient wraps a Twirp client implementation to return
// pre-determined responses for certain endpoints.
func NewEnterpriseClient(client Client) *enterpriseClient {
	return &enterpriseClient{
		client: client,
	}
}

// CreateRerunExecution will create a workflow_run_execution in dotcom.
func (c *enterpriseClient) CreateRerunExecution(ctx context.Context, input *RerunExecutionInput) error {
	return c.client.CreateRerunExecution(ctx, input)
}

// IsRepositoryActionsDisabled checks if Actions are disabled for a specific
// repository.
func (c *enterpriseClient) IsRepositoryActionsDisabled(ctx context.Context, repositoryID types.GlobalID) (bool, error) {
	return c.client.IsRepositoryActionsDisabled(ctx, repositoryID)
}

// IsUserSpammy always returns false for Enterprise since we don't do spammy
// checks there.
func (c *enterpriseClient) IsUserSpammy(_ context.Context, _ types.GlobalID) (bool, error) {
	return false, nil
}

// IsUserFromDatabaseIDSpammy always returns false since we don't do spammy
// checks.
func (c *enterpriseClient) IsUserFromDatabaseIDSpammy(_ context.Context, _ int64) (bool, error) {
	return false, nil
}

// IsFeatureEnabledForActor always returns false since feature flags don't exist
// in Enterprise.
func (c *enterpriseClient) IsFeatureEnabledForActor(_ context.Context, _ string, _ types.GlobalID) bool {
	return false
}

// IsFeatureEnabledForActors always returns false since feature flags don't
// exist in Enterprise.
func (c *enterpriseClient) IsFeatureEnabledForActors(_ context.Context, _ string, _ []types.GlobalID) bool {
	return false
}

// IsFeatureEnabledForRepoOrOwners always returns false since feature flags don't
// exist in Enterprise.
func (c *enterpriseClient) IsFeatureEnabledForRepoOrOwners(_ context.Context, _ string, _ types.GlobalID) bool {
	return false
}

// IsFeatureEnabledForRepository always returns false since feature flags don't
// exist in Enterprise.
func (c *enterpriseClient) IsFeatureEnabledForRepository(_ context.Context, _ string, _ int64) bool {
	return false
}

// IsFeatureEnabledGlobally always returns false since feature flags don't exist
// in Enterprise.
func (c *enterpriseClient) IsFeatureEnabledGlobally(_ context.Context, _ string) bool {
	return false
}

// CheckActionsAllowedByPolicy verifies that a list of Actions are allowed to
// be used by a repository based on Policy settings.
func (c *enterpriseClient) CheckActionsAllowedByPolicy(ctx context.Context, repositoryID types.GlobalID, actions []string, includeLocalOnlyActions bool, shouldIgnoreRepoPolicies bool) (*ActionsPolicyInfo, error) {
	return c.client.CheckActionsAllowedByPolicy(ctx, repositoryID, actions, includeLocalOnlyActions, shouldIgnoreRepoPolicies)
}

// CheckWorkflowsAllowedByPolicy verifies that a list of workflows are allowed to
// be used by a repository based on Policy settings.
func (c *enterpriseClient) CheckWorkflowsAllowedByPolicy(ctx context.Context, repositoryID types.GlobalID, workflows []string, shouldIgnoreRepoPolicies bool) (*WorkflowsPolicyInfo, error) {
	return c.client.CheckWorkflowsAllowedByPolicy(ctx, repositoryID, workflows, shouldIgnoreRepoPolicies)
}

// ResolveEnvironment returns an Actions environment for a given name and repository
func (c *enterpriseClient) ResolveEnvironment(ctx context.Context, environment string, repositoryID types.GlobalID) (*Environment, error) {
	return c.client.ResolveEnvironment(ctx, environment, repositoryID)
}

// GetEnvironmentRepository returns the dotcom database id of the repository
// where the given environment is present in.
func (c *enterpriseClient) GetEnvironmentRepository(ctx context.Context, environmentGlobalID types.GlobalID) (int64, error) {
	return c.client.GetEnvironmentRepository(ctx, environmentGlobalID)
}

// ShouldPullRequestWorkflowsRunForUser checks to see if pull request workflows
// should be run for a user
func (c *enterpriseClient) ShouldPullRequestWorkflowsRunForUser(ctx context.Context, repositoryID types.GlobalID, users PullRequestEventUsers) (bool, error) {
	return c.client.ShouldPullRequestWorkflowsRunForUser(ctx, repositoryID, users)
}

func (c *enterpriseClient) GetCommitMessage(ctx context.Context, repoID int64, commitSHA types.CommitSha) (types.CommitMessage, error) {
	return c.client.GetCommitMessage(ctx, repoID, commitSHA)
}

func (c *enterpriseClient) GetActorsInfo(ctx context.Context, actors []types.GlobalID) (*ActorsInfo, error) {
	return c.client.GetActorsInfo(ctx, actors)
}

func (c *enterpriseClient) GetBillingDetails(ctx context.Context, repositoryID types.GlobalID) (*WorkflowBillingDetails, error) {
	return c.client.GetBillingDetails(ctx, repositoryID)
}

func (c *enterpriseClient) GetBillingDetailsForEntity(ctx context.Context, entityID types.GlobalID, productSku string) (*WorkflowBillingDetails, error) {
	return c.client.GetBillingDetailsForEntity(ctx, entityID, productSku)
}

func (c *enterpriseClient) GetAccountDetails(ctx context.Context, entityID types.GlobalID) (*AccountDetails, error) {
	return c.client.GetAccountDetails(ctx, entityID)
}

func (c *enterpriseClient) GetRepositoryOwnersByName(ctx context.Context, nwo string) (*RepositoryOwners, error) {
	return c.client.GetRepositoryOwnersByName(ctx, nwo)
}

func (c *enterpriseClient) GetRepositoryOwners(ctx context.Context, repoID int64) (*RepositoryOwners, error) {
	return c.client.GetRepositoryOwners(ctx, repoID)
}

func (c *enterpriseClient) GetRepositoryOwnerID(ctx context.Context, repoID int64, useCache bool) (int64, error) {
	return c.client.GetRepositoryOwnerID(ctx, repoID, useCache)
}

func (c *enterpriseClient) GetOrganizationOwner(ctx context.Context, orgID int64) (*OrganizationOwner, error) {
	return c.client.GetOrganizationOwner(ctx, orgID)
}

func (c *enterpriseClient) GetRepositories(ctx context.Context, ownerID int64) ([]*ghactions.Repository, error) {
	return c.client.GetRepositories(ctx, ownerID)
}

// trust tier is always 1 (or TRUSTED) within the context of an enterprise instance
func (c *enterpriseClient) GetTrustTier(_ context.Context, _ types.GlobalID) (types.RepositoryTier, error) {
	return types.RepositoryTier1, nil
}

func (c *enterpriseClient) GetUserByLogin(ctx context.Context, login string) (int64, types.GlobalID, error) {
	return c.client.GetUserByLogin(ctx, login)
}

func (c *enterpriseClient) RetireNamespace(ctx context.Context, nwo string) error {
	return c.client.RetireNamespace(ctx, nwo)
}

func (c *enterpriseClient) FindRepositoriesByName(ctx context.Context, nwos []string) (*RepositoriesInfo, error) {
	return c.client.FindRepositoriesByName(ctx, nwos)
}

func (c *enterpriseClient) GetIntegrationJobSecrets(ctx context.Context, integrationName string, repositoryID, workflowRunID int64, bareJobName, environmentName string, isHostedRunner bool, dynamicEvent *flowevents.DynamicEvent) (map[string]string, error) {
	return c.client.GetIntegrationJobSecrets(ctx, integrationName, repositoryID, workflowRunID, bareJobName, environmentName, isHostedRunner, dynamicEvent)
}

func (c *enterpriseClient) IsDependabotAssociatedRef(ctx context.Context, repositoryID int64, ref string) (bool, error) {
	return c.client.IsDependabotAssociatedRef(ctx, repositoryID, ref)
}

// There is no plan to switch the globalID format for enterprise, so skipping client call
func (c *enterpriseClient) GetNextGlobalID(ctx context.Context, legacyGID string) (types.GlobalID, error) {
	return types.NewGlobalID(ctx, legacyGID), nil
}

// There is no plan to switch the globalID format for enterprise, so skipping client calls
func (c *enterpriseClient) GetNextGlobalIDs(ctx context.Context, legacyGIDs []string) (map[string]types.GlobalID, bool, error) {
	nextIDs := make(map[string]types.GlobalID)

	for _, legacyGID := range legacyGIDs {
		nextIDs[legacyGID] = types.NewGlobalID(ctx, legacyGID)
	}

	return nextIDs, true, nil
}

// There is no plan switch globalID format for enterprise, so skipping client call
func (c *enterpriseClient) GetAdditionalWorkflows(ctx context.Context, repoID int64, event EventReference) (*AdditionalWorkflows, error) {
	return c.client.GetAdditionalWorkflows(ctx, repoID, event)
}

func (c *enterpriseClient) UpdateWorkflowRun(ctx context.Context, repoID types.GlobalID, workflowRunID int64, name string) error {
	return c.client.UpdateWorkflowRun(ctx, repoID, workflowRunID, name)
}

func (c *enterpriseClient) UpdateWorkflowRunExecution(ctx context.Context, repoID types.GlobalID, workflowRunID int64, runStampURL string) error {
	return c.client.UpdateWorkflowRunExecution(ctx, repoID, workflowRunID, runStampURL)
}

func (c *enterpriseClient) GetRepositoryEventDetails(ctx context.Context, repoID int64) (string, error) {
	return c.client.GetRepositoryEventDetails(ctx, repoID)
}

func (c *enterpriseClient) FindTreeIDAndPreviousWorkflowRunToReuse(ctx context.Context, repoID types.GlobalID, workflowPath string, eventType string, commitSHA types.CommitSha) (types.CommitSha, *ReusableCheckSuite, error) {
	return c.client.FindTreeIDAndPreviousWorkflowRunToReuse(ctx, repoID, workflowPath, eventType, commitSHA)
}

func (c *enterpriseClient) GetAccountDetailsForRepository(ctx context.Context, repoID types.GlobalID) (*RepositoryAccountDetails, error) {
	return c.client.GetAccountDetailsForRepository(ctx, repoID)
}

func (c *enterpriseClient) ResolveActions(ctx context.Context, actions []*Action, workflowRunID int64, jobID string, workflowRepoID int64, shouldInstrumentRequest bool, isHostedRunner bool) ([]*ResolveActionsResponse, error) {
	return c.client.ResolveActions(ctx, actions, workflowRunID, jobID, workflowRepoID, shouldInstrumentRequest, isHostedRunner)
}

func (c *enterpriseClient) GetWorkflowRunExecution(ctx context.Context, checkSuiteGlobalID types.GlobalID, planID uuid.UUID) (*WorkflowRunExecutionResponse, error) {
	return c.client.GetWorkflowRunExecution(ctx, checkSuiteGlobalID, planID)
}

func (c *enterpriseClient) GetRepositoryVisibility(ctx context.Context, repoID int64) (ghactions.RepositoryVisibility, error) {
	return c.client.GetRepositoryVisibility(ctx, repoID)
}
