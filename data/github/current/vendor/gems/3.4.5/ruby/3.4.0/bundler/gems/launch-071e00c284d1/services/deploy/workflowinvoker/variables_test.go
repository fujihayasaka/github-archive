package workflowinvoker

import (
	"context"
	"encoding/base64"
	"fmt"
	"strconv"
	"testing"

	githubgo "github.com/google/go-github/v25/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"

	varzpb "github.com/github/kredz/services/protobuf/varz"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/clients/varz"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/types"
)

func (s *buildInvokerTest) TestVariblesReplacesOrgVariablesWithRepoVariables() {
	encodedRepoVariable := base64.StdEncoding.EncodeToString([]byte("repo_variable"))
	encodedOrgVariable := base64.StdEncoding.EncodeToString([]byte("org_variable"))

	repositoryVariables := map[string]string{
		"my_variable": encodedRepoVariable,
	}

	organizationVariables := map[string]string{
		"my_variable": encodedOrgVariable,
	}

	variablesForRepository := &varz.RepositoryVariablesResponse{
		RepositoryVariables:   repositoryVariables,
		OrganizationVariables: organizationVariables,
	}

	s.varzClient = &varz.MockClient{}
	s.varzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(variablesForRepository, nil)

	const repoID = types.GlobalID("repo-1")
	const orgID = types.GlobalID("org-1")
	const actionsAppGlobalID = types.GlobalID("actions-app-next-global-id")

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   orgID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "team",
		},
	}

	s.ghtwirp = &ghtwirp.MockClient{}
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(repoID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(orgID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, s.invoker.actionsAppGlobalID).Return(actionsAppGlobalID, nil)

	variablesMap, err := s.invoker.getVariables(context.Background(), s.varzClient, s.ghtwirp, &data, repoID)
	s.NoError(err, "Fetching variables should not error")
	s.NotNil(variablesMap, "Variables map should not be nil")

	variableValue := variablesMap["my_variable"]
	expectedValue := "repo_variable"
	s.Equal(1, len(variablesMap), "Expected %d variable in variables map but found %d", 1, len(variablesMap))
	s.Equal(expectedValue, variableValue, "Expected variable \"%s\" in variables map but found \"%s\"", expectedValue, variableValue)
}

func (s *buildInvokerTest) TestVariblesReplacesOrgVariablesWithRepoVariables_IncreasedLimit() {

	const repoID = types.GlobalID("repo-1")
	const orgID = types.GlobalID("org-1")
	const actionsAppGlobalID = types.GlobalID("actions-app-next-global-id")

	encodedOrgVariable := base64.StdEncoding.EncodeToString([]byte("org_variable"))
	encodedRepoVariable := base64.StdEncoding.EncodeToString([]byte("repo_variable"))

	organizationVariables := map[string]string{
		"my_variable": encodedOrgVariable,
	}
	repoVariables := map[string]string{
		"my_variable": encodedRepoVariable,
	}

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   orgID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "enterprise",
		},
	}

	listVariablesForRepositoryResponse := &varz.RepositoryVariablesResponse{
		RepositoryVariables:                 repoVariables,
		OrganizationVariables:               organizationVariables,
		RemainingRepositoryVariablesNames:   make([]string, 0),
		RemainingOrganizationVariablesNames: make([]string, 0),
	}

	s.ghtwirp = &ghtwirp.MockClient{}
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, repoID.String()).Return(repoID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, orgID.String()).Return(orgID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, s.invoker.actionsAppGlobalID).Return(actionsAppGlobalID, nil)

	s.varzClient = &varz.MockClient{}
	s.varzClient.On("ListVariablesForRepository", mock.Anything, data.Owner, orgID, repoID, false, actionsAppGlobalID, true).Return(listVariablesForRepositoryResponse, nil)

	variablesMap, err := s.invoker.getVariablesIncreasedCount(context.Background(), s.varzClient, s.ghtwirp, &data, repoID)
	s.NoError(err, "Fetching variables should not error")
	s.NotNil(variablesMap, "Variables map should not be nil")

	variableValue := variablesMap["my_variable"]
	expectedValue := "repo_variable"
	s.Equal(1, len(variablesMap), "Expected %d variable in variables map but found %d", 1, len(variablesMap))
	s.Equal(expectedValue, variableValue, "Expected variable \"%s\" in variables map but found \"%s\"", expectedValue, variableValue)
}

func (s *buildInvokerTest) TestVariablesIncludesOrgVariables() {
	encodedOrgVariable := base64.StdEncoding.EncodeToString([]byte("org_variable"))
	organizationVariables := map[string]string{
		"my_variable": encodedOrgVariable,
	}

	variablesForRepository := &varz.RepositoryVariablesResponse{
		OrganizationVariables: organizationVariables,
	}

	s.varzClient = &varz.MockClient{}
	s.varzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(variablesForRepository, nil)

	const repoID = types.GlobalID("repo-1")
	const orgID = types.GlobalID("org-1")
	const actionsAppGlobalID = types.GlobalID("actions-app-next-global-id")

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   orgID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "enterprise",
		},
	}

	s.ghtwirp = &ghtwirp.MockClient{}
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(repoID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(orgID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(actionsAppGlobalID, nil)

	variablesMap, err := s.invoker.getVariables(context.Background(), s.varzClient, s.ghtwirp, &data, repoID)
	s.NoError(err, "Fetching variables should not error")
	s.NotNil(variablesMap, "Variables map should not be nil")

	variableValue := variablesMap["my_variable"]
	expectedValue := "org_variable"
	s.Equal(1, len(variablesMap), "Expected %d variable in variables map but found %d", 1, len(variablesMap))
	s.Equal(expectedValue, variableValue, "Expected variable \"%s\" in variables map but found \"%s\"", expectedValue, variableValue)
}

func (s *buildInvokerTest) TestVariablesIncludesOrgVariables_IncreasedLimit() {

	const repoID = types.GlobalID("repo-1")
	const orgID = types.GlobalID("org-1")
	const actionsAppGlobalID = types.GlobalID("actions-app-next-global-id")

	encodedOrgVariable := base64.StdEncoding.EncodeToString([]byte("org_variable"))
	encodedRepoVariable := base64.StdEncoding.EncodeToString([]byte("repo_variable"))

	organizationVariables := map[string]string{
		"my_variable": encodedOrgVariable,
	}
	repoVariables := map[string]string{
		"my_variable": encodedRepoVariable,
	}

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   orgID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "enterprise",
		},
	}
	repoVariableNames := []string{"var_1", "var_2", "var_3"}
	repoVariablesByNames := map[string]string{
		"var_1": base64.StdEncoding.EncodeToString([]byte("repo_variable_1")),
		"var_2": base64.StdEncoding.EncodeToString([]byte("repo_variable_2")),
		"var_3": base64.StdEncoding.EncodeToString([]byte("repo_variable_3")),
	}
	repoVariablesByNamesResponse := &varz.ListVariablesResponse{
		Variables: repoVariablesByNames,
	}

	orgVariableNames := []string{"var_1", "var_2", "var_3", "var_4"}

	listVariablesForRepositoryResponse := &varz.RepositoryVariablesResponse{
		RepositoryVariables:                 repoVariables,
		OrganizationVariables:               organizationVariables,
		RemainingRepositoryVariablesNames:   repoVariableNames,
		RemainingOrganizationVariablesNames: orgVariableNames,
	}

	// Trimmed response, we don't fetch "var_1", "var_2", "var_3"
	orgVariablesByNames := map[string]string{
		"var_4": base64.StdEncoding.EncodeToString([]byte("org_variable_4")),
	}
	orgVariablesByNamesResponse := &varz.ListVariablesResponse{
		Variables: orgVariablesByNames,
	}
	repoOwner := &varzpb.VariableOwner{
		Owner: &varzpb.VariableOwner_Repository{
			Repository: &varzpb.Repository{
				GlobalId: string(repoID),
			},
		},
	}

	s.varzClient = &varz.MockClient{}
	s.varzClient.On("ListVariablesForRepository", mock.Anything, data.Owner, orgID, repoID, false, actionsAppGlobalID, true).Return(listVariablesForRepositoryResponse, nil)
	s.varzClient.On("ListVariablesByNamesForOwner", mock.Anything, repoOwner, actionsAppGlobalID, repoVariableNames).Return(repoVariablesByNamesResponse, nil)
	s.varzClient.On("ListOrganizationVariablesForRepositoryByNames", mock.Anything, orgID, data.Owner.Type, repoID, false, actionsAppGlobalID, []string{"var_4"}).Return(orgVariablesByNamesResponse, nil)

	s.ghtwirp = &ghtwirp.MockClient{}
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, repoID.String()).Return(repoID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, orgID.String()).Return(orgID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, s.invoker.actionsAppGlobalID).Return(actionsAppGlobalID, nil)

	variablesMap, err := s.invoker.getVariablesIncreasedCount(context.Background(), s.varzClient, s.ghtwirp, &data, repoID)
	s.NoError(err, "Fetching variables should not error")
	s.NotNil(variablesMap, "Variables map should not be nil")

	variableValue := variablesMap["var_4"]
	expectedValue := "org_variable_4"
	s.Equal(5, len(variablesMap), "Expected %d variable in variables map but found %d", 1, len(variablesMap))
	s.Equal(expectedValue, variableValue, "Expected variable \"%s\" in variables map but found \"%s\"", expectedValue, variableValue)
}

func (s *buildInvokerTest) TestVariablesIgnoresOrgVariablesForUsers() {
	encodedUserVariable := base64.StdEncoding.EncodeToString([]byte("user_variable"))
	organizationVariables := map[string]string{
		"my_variable": encodedUserVariable,
	}

	variablesForRepository := &varz.RepositoryVariablesResponse{
		OrganizationVariables: organizationVariables,
	}

	s.varzClient = &varz.MockClient{}
	s.varzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(variablesForRepository, nil)

	const repoID = types.GlobalID("repo-1")
	const ownerID = types.GlobalID("user-1")
	const actionsAppGlobalID = types.GlobalID("actions-app-next-global-id")

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   ownerID,
			DatabaseID: 1,
			Type:       "User",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "pro",
		},
	}

	s.ghtwirp = &ghtwirp.MockClient{}
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(repoID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(ownerID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(actionsAppGlobalID, nil)

	variablesMap, err := s.invoker.getVariables(context.Background(), s.varzClient, s.ghtwirp, &data, repoID)
	s.NoError(err, "Fetching variables should not error")
	s.NotNil(variablesMap, "Variables map should not be nil")
	s.Equal(0, len(variablesMap), "Expected %d variable in variables map but found %d", 0, len(variablesMap))
}

func (s *buildInvokerTest) TestVariablesIgnoresOrgVariablesForUsers_IncreasedLimit() {

	const repoID = types.GlobalID("repo-1")
	const ownerID = types.GlobalID("user-1")
	const actionsAppGlobalID = types.GlobalID("actions-app-next-global-id")

	encodedOrgVariable := base64.StdEncoding.EncodeToString([]byte("org_variable"))
	encodedRepoVariable := base64.StdEncoding.EncodeToString([]byte("repo_variable"))

	organizationVariables := map[string]string{
		"org_variable": encodedOrgVariable,
	}
	repoVariables := map[string]string{
		"repo_variable": encodedRepoVariable,
	}

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   ownerID,
			DatabaseID: 1,
			Type:       "User",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "pro",
		},
	}

	listVariablesForRepositoryResponse := &varz.RepositoryVariablesResponse{
		RepositoryVariables:                 repoVariables,
		OrganizationVariables:               organizationVariables,
		RemainingRepositoryVariablesNames:   make([]string, 0),
		RemainingOrganizationVariablesNames: make([]string, 0),
	}

	s.ghtwirp = &ghtwirp.MockClient{}
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, repoID.String()).Return(repoID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, ownerID.String()).Return(ownerID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, s.invoker.actionsAppGlobalID).Return(actionsAppGlobalID, nil)

	s.varzClient = &varz.MockClient{}
	s.varzClient.On("ListVariablesForRepository", mock.Anything, data.Owner, ownerID, repoID, data.RepoIsPrivate, actionsAppGlobalID, true).Return(listVariablesForRepositoryResponse, nil)

	variablesMap, err := s.invoker.getVariablesIncreasedCount(context.Background(), s.varzClient, s.ghtwirp, &data, repoID)
	s.NoError(err, "Fetching variables should not error")
	s.NotNil(variablesMap, "Variables map should not be nil")
	s.Equal(1, len(variablesMap), "Expected %d variable in variables map but found %d", 1, len(variablesMap))
	_, ok := variablesMap["org_variable"]
	s.Equal(false, ok, "Org variable should not be present")
}

func (s *buildInvokerTest) TestVariablesForDependabot() {
	encodedRepoVariable := base64.StdEncoding.EncodeToString([]byte("repo_variable"))
	encodedOrgVariable := base64.StdEncoding.EncodeToString([]byte("org_variable"))

	repositoryVariables := map[string]string{
		"my_variable": encodedRepoVariable,
	}

	organizationVariables := map[string]string{
		"my_variable": encodedOrgVariable,
	}

	variablesForRepository := &varz.RepositoryVariablesResponse{
		RepositoryVariables:   repositoryVariables,
		OrganizationVariables: organizationVariables,
	}

	s.varzClient = &varz.MockClient{}
	s.varzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(variablesForRepository, nil)

	const repoID = types.GlobalID("repo-1")
	const orgID = types.GlobalID("org-1")
	const actionsAppGlobalID = types.GlobalID("actions-app-next-global-id")

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   orgID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "team",
		},
	}

	dependabotActor := &metadata.WorkflowMetadataActor{
		IsDependabot: true,
		Login:        "dependabot[bot]",
	}

	s.invoker.workflowMetadata.Actor = dependabotActor

	s.ghtwirp = &ghtwirp.MockClient{}
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(repoID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(orgID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, s.invoker.actionsAppGlobalID).Return(actionsAppGlobalID, nil)

	variablesMap, err := s.invoker.getVariables(context.Background(), s.varzClient, s.ghtwirp, &data, repoID)
	s.NotNil(variablesMap, "Variables map should not be nil")
	s.NoError(err, "Fetching variables should not error")
	s.Equal(1, len(variablesMap), "Expected %d variable in variables map but found %d", 1, len(variablesMap))
}

func (s *buildInvokerTest) TestVariablesForDependabot_IncreasedLimit() {
	const repoID = types.GlobalID("repo-1")
	const orgID = types.GlobalID("org-1")
	const actionsAppGlobalID = types.GlobalID("actions-app-next-global-id")

	encodedRepoVariable := base64.StdEncoding.EncodeToString([]byte("repo_variable"))
	encodedOrgVariable := base64.StdEncoding.EncodeToString([]byte("org_variable"))

	repositoryVariables := map[string]string{
		"my_variable": encodedRepoVariable,
	}

	organizationVariables := map[string]string{
		"my_variable": encodedOrgVariable,
	}

	listVariablesForRepositoryResponse := &varz.RepositoryVariablesResponse{
		RepositoryVariables:                 repositoryVariables,
		OrganizationVariables:               organizationVariables,
		RemainingRepositoryVariablesNames:   make([]string, 0),
		RemainingOrganizationVariablesNames: make([]string, 0),
	}

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   orgID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "team",
		},
	}

	dependabotActor := &metadata.WorkflowMetadataActor{
		IsDependabot: true,
		Login:        "dependabot[bot]",
	}

	s.invoker.workflowMetadata.Actor = dependabotActor

	s.varzClient = &varz.MockClient{}
	s.varzClient.On("ListVariablesForRepository", mock.Anything, data.Owner, orgID, repoID, false, actionsAppGlobalID, true).Return(listVariablesForRepositoryResponse, nil)

	s.ghtwirp = &ghtwirp.MockClient{}
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, s.invoker.actionsAppGlobalID).Return(actionsAppGlobalID, nil)

	variablesMap, err := s.invoker.getVariablesIncreasedCount(context.Background(), s.varzClient, s.ghtwirp, &data, repoID)
	s.NotNil(variablesMap, "Variables map should not be nil")
	s.NoError(err, "Fetching variables should not error")
	s.Equal(1, len(variablesMap), "Expected %d variable in variables map but found %d", 1, len(variablesMap))
}

func TestShouldSendVariables(t *testing.T) {
	headID := int64(1)
	baseID := int64(2)
	sourceRepo := &githubgo.Repository{
		ID: &baseID,
	}
	forkRepo := &githubgo.Repository{
		ID: &headID,
	}
	forkPR := &githubgo.PullRequest{
		Head: &githubgo.PullRequestBranch{
			Repo: sourceRepo,
		},
		Base: &githubgo.PullRequestBranch{
			Repo: forkRepo,
		},
	}
	sourcePR := &githubgo.PullRequest{
		Head: &githubgo.PullRequestBranch{
			Repo: sourceRepo,
		},
		Base: &githubgo.PullRequestBranch{
			Repo: sourceRepo,
		},
	}

	var sendSecretAndVariablesForkPolicy = []types.ForkPRWorkflowsPolicy{
		types.ForkPRWorkflowsRunWithSecrets,
		types.ForkPRWorkflowsRunWithTokensAndSecrets,
	}

	var noSendSecretAndVariablesForkPolicy = []types.ForkPRWorkflowsPolicy{
		types.ForkPRWorkflowsRunWithTokens,
		types.ForkPRWorkflowsRunWorkflows,
		types.ForkPRWorkflowsDisabled,
	}

	var publicForkPolicySendVar = []types.PublicForkPRWorkflowsPolicy{
		types.PublicForkPRWorkflowsRunWithVariables,
	}

	var publicForkPolicyDontSendVar = []types.PublicForkPRWorkflowsPolicy{
		types.PublicForkPRWorkflowsInvalidPolicy,
	}

	var allForkPolicies = append(sendSecretAndVariablesForkPolicy, noSendSecretAndVariablesForkPolicy...)

	testCases := []struct {
		name               string
		eventName          string
		event              flowevents.GitHubEvent
		forkPolicies       []types.ForkPRWorkflowsPolicy
		publicForkPolicies []types.PublicForkPRWorkflowsPolicy
		expectedSend       bool
	}{
		{
			"fork PR",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			noSendSecretAndVariablesForkPolicy,
			publicForkPolicyDontSendVar,
			false,
		},
		{
			"fork PR with secrets and variables enabled",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			sendSecretAndVariablesForkPolicy,
			publicForkPolicySendVar,
			true,
		},
		{
			"fork PR review comment",
			flowevents.PullRequest,
			&githubgo.PullRequestReviewCommentEvent{PullRequest: forkPR},
			noSendSecretAndVariablesForkPolicy,
			publicForkPolicyDontSendVar,
			false,
		},
		{
			"fork PR review",
			flowevents.PullRequest,
			&githubgo.PullRequestReviewEvent{PullRequest: forkPR},
			noSendSecretAndVariablesForkPolicy,
			publicForkPolicyDontSendVar,
			false,
		},
		{
			"source PR",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: sourcePR},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
		{
			"source PR review comment",
			flowevents.PullRequest,
			&githubgo.PullRequestReviewCommentEvent{PullRequest: sourcePR},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
		{
			"source PR review",
			flowevents.PullRequest,
			&githubgo.PullRequestReviewEvent{PullRequest: sourcePR},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
		{
			"push",
			flowevents.Push,
			&githubgo.PushEvent{},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
		{
			"unrecognized event",
			"a_new_event",
			&githubgo.PullRequestReviewEvent{},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
		{
			"fork PR pull_request_target event",
			flowevents.PullRequestTarget,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
		{
			"source PR pull_request_target event",
			flowevents.PullRequestTarget,
			&githubgo.PullRequestEvent{PullRequest: sourcePR},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
		{
			"dynamic workflow",
			flowevents.Dynamic,
			&flowevents.DynamicEvent{},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
		{
			"workflow call does receive variables",
			flowevents.WorkflowCall,
			&flowevents.WorkflowCallEvent{},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
		{
			"create",
			flowevents.Create,
			&githubgo.CreateEvent{},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
		{
			"workflow_dispatch",
			flowevents.WorkflowDispatch,
			&githubgo.WorkflowDispatchEvent{},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
		{
			"pull_request run_wf",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			[]types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			publicForkPolicyDontSendVar,
			false,
		},
		{
			"pull_request with secrets",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			[]types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWithSecrets},
			publicForkPolicyDontSendVar,
			true,
		},
		{
			"pull_request public fork",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			allForkPolicies,
			publicForkPolicySendVar,
			true,
		},
	}

	for _, tc := range testCases {
		if len(tc.forkPolicies) == 0 {
			panic("One or more fork policies need to be provided")
		}
		for _, forkPolicy := range tc.forkPolicies {
			for _, publicForkPolicy := range tc.publicForkPolicies {
				t.Run(fmt.Sprintf("%v (ForkPolicy: %v) (PublicForkPolicy:%v)", tc.name, forkPolicy, publicForkPolicy), func(t *testing.T) {
					assert.Equal(t, tc.expectedSend, ShouldSendVariables(tc.eventName, tc.event, forkPolicy, publicForkPolicy))
				})
			}
		}
	}
}

func (s *buildInvokerTest) TestVariablesSkippedAfterRepoThreshold_IncreasedLimit() {

	const repoID = types.GlobalID("repo-1")
	const orgID = types.GlobalID("org-1")
	const actionsAppGlobalID = types.GlobalID("actions-app-next-global-id")

	organizationVariables := generateVariableResponseMap("org_", 10*1024) // 10KB size

	repoVariables := generateVariableResponseMap("repo_", 256*1024) // 256KB size

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   orgID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "enterprise",
		},
	}

	listVariablesForRepositoryResponse := &varz.RepositoryVariablesResponse{
		RepositoryVariables:   repoVariables,
		OrganizationVariables: organizationVariables,
	}

	s.varzClient = &varz.MockClient{}
	s.varzClient.On("ListVariablesForRepository", mock.Anything, data.Owner, orgID, repoID, false, actionsAppGlobalID, true).Return(listVariablesForRepositoryResponse, nil)

	s.ghtwirp = &ghtwirp.MockClient{}
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, repoID.String()).Return(repoID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, orgID.String()).Return(orgID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, s.invoker.actionsAppGlobalID).Return(actionsAppGlobalID, nil)

	variablesMap, err := s.invoker.getVariablesIncreasedCount(context.Background(), s.varzClient, s.ghtwirp, &data, repoID)
	s.Error(err, ErrVariableSizeExceeded)
	s.NotNil(variablesMap, "Variables map should not be nil")
	s.LessOrEqual(len(variablesMap), len(repoVariables))
}

func (s *buildInvokerTest) TestVariablesSkippedAfterOrgThreshold_IncreasedLimit() {

	const repoID = types.GlobalID("repo-1")
	const orgID = types.GlobalID("org-1")
	const actionsAppGlobalID = types.GlobalID("actions-app-next-global-id")

	organizationVariables := generateVariableResponseMap("org_", 100*1024) // 100KB size

	repoVariables := generateVariableResponseMap("repo_", 107*1024) // 107KB size

	organizationVariablesChunk1 := generateVariableResponseMap("org_chunk_1", 49*1024) // 49KB size, 100 vars
	organizationVariablesChunk1Names := generateVariableNames("org_chunk_1", len(organizationVariablesChunk1))

	organizationVariablesChunk2 := generateVariableResponseMap("org_chunk_2", 49*1024) // 49KB size, 100 vars
	organizationVariablesChunk2Names := generateVariableNames("org_chunk_2", len(organizationVariablesChunk2))

	data := types.WorkflowInvocationData{
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   orgID,
			DatabaseID: 1,
			Type:       "Organization",
		},
		RepoIsPrivate: false,
		PlanOwner: types.WorkflowInvocationPlanOwner{
			PlanName: "enterprise",
		},
	}

	listVariablesForRepositoryResponse := &varz.RepositoryVariablesResponse{
		RepositoryVariables:                 repoVariables,
		OrganizationVariables:               organizationVariables,
		RemainingOrganizationVariablesNames: append(organizationVariablesChunk1Names, organizationVariablesChunk2Names...),
	}

	chunk1Resp := &varz.ListVariablesResponse{
		Variables: organizationVariablesChunk1,
	}
	chunk2Resp := &varz.ListVariablesResponse{
		Variables: organizationVariablesChunk2,
	}

	s.varzClient = &varz.MockClient{}
	s.varzClient.On("ListVariablesForRepository", mock.Anything, data.Owner, orgID, repoID, false, actionsAppGlobalID, true).Return(listVariablesForRepositoryResponse, nil)
	s.varzClient.On("ListOrganizationVariablesForRepositoryByNames", mock.Anything, orgID, data.Owner.Type, repoID, false, actionsAppGlobalID, organizationVariablesChunk1Names).Return(chunk1Resp, nil)
	s.varzClient.On("ListOrganizationVariablesForRepositoryByNames", mock.Anything, orgID, data.Owner.Type, repoID, false, actionsAppGlobalID, organizationVariablesChunk2Names).Return(chunk2Resp, nil)

	s.ghtwirp = &ghtwirp.MockClient{}
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, repoID.String()).Return(repoID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, orgID.String()).Return(orgID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, s.invoker.actionsAppGlobalID).Return(actionsAppGlobalID, nil)

	variablesMap, err := s.invoker.getVariablesIncreasedCount(context.Background(), s.varzClient, s.ghtwirp, &data, repoID)
	s.Error(err, ErrVariableSizeExceeded)
	s.NotNil(variablesMap, "Variables map should not be nil")
	s.LessOrEqual(len(variablesMap), len(repoVariables)+len(organizationVariables)+len(organizationVariablesChunk1)) // chunk2 dropped
}

func generateVariableResponseMap(prefix string, size int) map[string]string {
	result := make(map[string]string)
	currentCount := 0
	for currentSize := 0; currentSize < size; {
		varName := prefix + "var_" + strconv.Itoa(currentCount)
		postfix := "___longlonglonglonglongpostfix___longlonglonglonglongpostfix___longlonglonglonglongpostfix___longlonglonglonglongpostfix___longlonglonglonglongpostfix___longlonglonglonglongpostfix___longlonglonglonglongpostfix___longlonglonglonglongpost"
		varVal := prefix + "variable_value_" + strconv.Itoa(currentSize) + postfix + postfix
		encodedVarVal := base64.StdEncoding.EncodeToString([]byte(varVal))
		currentSize = currentSize + len(varVal)
		result[varName] = encodedVarVal
		currentCount += 1
	}
	return result
}

func generateVariableNames(prefix string, count int) []string {
	result := make([]string, 0)
	for currentCount := 0; currentCount < count; currentCount++ {
		varName := prefix + "var_" + strconv.Itoa(currentCount)
		result = append(result, varName)
	}
	return result
}
