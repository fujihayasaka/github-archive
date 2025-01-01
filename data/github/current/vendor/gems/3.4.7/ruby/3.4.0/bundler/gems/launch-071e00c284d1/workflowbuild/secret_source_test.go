package workflowbuild

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"

	githubgo "github.com/google/go-github/v25/github"

	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"
)

func TestDetermineSecretSource(t *testing.T) {
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

	var sendSecretForkPolicy = []types.ForkPRWorkflowsPolicy{
		types.ForkPRWorkflowsRunWithSecrets,
		types.ForkPRWorkflowsRunWithTokensAndSecrets,
	}

	var noSendSecretForkPolicy = []types.ForkPRWorkflowsPolicy{
		types.ForkPRWorkflowsRunWithTokens,
		types.ForkPRWorkflowsRunWorkflows,
		types.ForkPRWorkflowsDisabled,
	}

	var allForkPolicies = append(sendSecretForkPolicy, noSendSecretForkPolicy...)

	testCases := []struct {
		name                 string
		eventName            string
		event                flowevents.GitHubEvent
		forkPolicies         []types.ForkPRWorkflowsPolicy
		actor                *metadata.WorkflowMetadataActor
		expectedSecretSource SecretSource
	}{
		{
			"fork PR",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			noSendSecretForkPolicy,
			&metadata.WorkflowMetadataActor{},
			NoSecretSource,
		},
		{
			"fork PR with secrets enabled",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			sendSecretForkPolicy,
			&metadata.WorkflowMetadataActor{},
			ActionsSecretSource,
		},
		{
			"fork PR review comment",
			flowevents.PullRequest,
			&githubgo.PullRequestReviewCommentEvent{PullRequest: forkPR},
			noSendSecretForkPolicy,
			&metadata.WorkflowMetadataActor{},
			NoSecretSource,
		},
		{
			"fork PR review",
			flowevents.PullRequest,
			&githubgo.PullRequestReviewEvent{PullRequest: forkPR},
			noSendSecretForkPolicy,
			&metadata.WorkflowMetadataActor{},
			NoSecretSource,
		},
		{
			"source PR",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: sourcePR},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{},
			ActionsSecretSource,
		},
		{
			"source PR review comment",
			flowevents.PullRequest,
			&githubgo.PullRequestReviewCommentEvent{PullRequest: sourcePR},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{},
			ActionsSecretSource,
		},
		{
			"source PR review",
			flowevents.PullRequest,
			&githubgo.PullRequestReviewEvent{PullRequest: sourcePR},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{},
			ActionsSecretSource,
		},
		{
			"push",
			flowevents.Push,
			&githubgo.PushEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{},
			ActionsSecretSource,
		},
		{
			"unrecognized event",
			"a_new_event",
			&githubgo.PullRequestReviewEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{},
			NoSecretSource,
		},
		{
			"fork PR pull_request_target event",
			flowevents.PullRequestTarget,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{},
			ActionsSecretSource,
		},
		{
			"fork PR pull_request_target event with dependabot",
			flowevents.PullRequestTarget,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{IsDependabot: true},
			ActionsSecretSource,
		},
		{
			"source PR pull_request_target event",
			flowevents.PullRequestTarget,
			&githubgo.PullRequestEvent{PullRequest: sourcePR},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{},
			ActionsSecretSource,
		},
		{
			"dependabot triggered pull_request (non-fork) events can send dependabot secrets regardless of fork policy",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: sourcePR},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{IsDependabot: true},
			DependabotSecretSource,
		},
		{
			"dependabot triggered pull_request (fork) events can send dependabot secrets if fork policy allows it",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			sendSecretForkPolicy,
			&metadata.WorkflowMetadataActor{IsDependabot: true},
			DependabotSecretSource,
		},
		{
			"dependabot triggered pull_request (fork) events can't send dependabot secrets if fork policy does not allow it",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			noSendSecretForkPolicy,
			&metadata.WorkflowMetadataActor{IsDependabot: true},
			NoSecretSource,
		},
		{
			"for dependabot actor: pull_request event",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{IsDependabot: true},
			DependabotSecretSource,
		},
		{
			"for dependabot actor: pull_request_review event",
			flowevents.PullRequestReview,
			&githubgo.PullRequestReviewEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{IsDependabot: true},
			DependabotSecretSource,
		},
		{
			"for dependabot actor: pull_request_review_comment event",
			flowevents.PullRequestReviewComment,
			&githubgo.PullRequestReviewCommentEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{IsDependabot: true},
			DependabotSecretSource,
		},
		{
			"for dependabot actor: push",
			flowevents.Push,
			&githubgo.PushEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{IsDependabot: true},
			DependabotSecretSource,
		},
		{
			"dynamic workflow for non-dependabot actor receive secrets",
			flowevents.Dynamic,
			&flowevents.DynamicEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{},
			ActionsSecretSource,
		},
		{
			"dynamic workflow for dependabot actor does not receive secrets",
			flowevents.Dynamic,
			&flowevents.DynamicEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{IsDependabot: true},
			NoSecretSource,
		},
		{
			"workflow call does not receive secrets",
			flowevents.WorkflowCall,
			&flowevents.WorkflowCallEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{},
			NoSecretSource,
		},
		{
			"create for non-dependabot actor receive secrets",
			flowevents.Create,
			&githubgo.CreateEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{},
			ActionsSecretSource,
		},
		{
			"create for dependabot actor receives Dependabot secrets",
			flowevents.Create,
			&githubgo.CreateEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{IsDependabot: true},
			DependabotSecretSource,
		},
		{
			"workflow_dispatch for dependabot actor receives no secrets",
			flowevents.WorkflowDispatch,
			&githubgo.WorkflowDispatchEvent{},
			allForkPolicies,
			&metadata.WorkflowMetadataActor{IsDependabot: true},
			NoSecretSource,
		},
	}

	for _, tc := range testCases {
		if len(tc.forkPolicies) == 0 {
			panic("One or more fork policies need to be provided")
		}
		for _, forkPolicy := range tc.forkPolicies {
			t.Run(fmt.Sprintf("%v (ForkPolicy: %v)", tc.name, forkPolicy), func(t *testing.T) {
				ctx := context.Background()
				obs := observability.NewNullObservability()

				assert.Equal(t, tc.expectedSecretSource, DetermineSecretSource(ctx, obs, tc.eventName, tc.event, forkPolicy, tc.actor))
			})
		}
	}
}
func TestCanGenerateIDToken(t *testing.T) {
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
	var sendSecretForkPolicies = []types.ForkPRWorkflowsPolicy{
		types.ForkPRWorkflowsRunWithSecrets,
		types.ForkPRWorkflowsRunWithTokensAndSecrets,
	}
	var dontSendSecretForkPolicies = []types.ForkPRWorkflowsPolicy{
		types.ForkPRWorkflowsRunWithTokens,
		types.ForkPRWorkflowsRunWorkflows,
		types.ForkPRWorkflowsDisabled,
	}
	var allForkPolicies = append(sendSecretForkPolicies, dontSendSecretForkPolicies...)

	testCases := []struct {
		name          string
		eventName     string
		event         flowevents.GitHubEvent
		forkPolicies  []types.ForkPRWorkflowsPolicy
		expectedValue bool
	}{
		{
			"fork PR can't generate ID token",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			dontSendSecretForkPolicies,
			false,
		},
		{
			"fork PR with secrets enabled",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: forkPR},
			sendSecretForkPolicies,
			true,
		},
		{
			"source PR can generate ID token",
			flowevents.PullRequest,
			&githubgo.PullRequestEvent{PullRequest: sourcePR},
			allForkPolicies,
			true,
		},
		{
			"push event workflows can generate ID token",
			flowevents.Push,
			&githubgo.PushEvent{},
			allForkPolicies,
			true,
		},
		{
			"dynamic workflow can generate ID token",
			flowevents.Dynamic,
			&flowevents.DynamicEvent{},
			allForkPolicies,
			true,
		},
		{
			"workflow_dispatch can generate ID token",
			flowevents.WorkflowDispatch,
			&githubgo.WorkflowDispatchEvent{},
			allForkPolicies,
			true,
		},
	}

	for _, tc := range testCases {
		if len(tc.forkPolicies) == 0 {
			panic("One or more fork policies need to be provided")
		}
		for _, forkPolicy := range tc.forkPolicies {
			t.Run(fmt.Sprintf("%v (ForkPolicy: %v)", tc.name, forkPolicy), func(t *testing.T) {
				assert.Equal(t, tc.expectedValue, CanGenerateIDToken(tc.eventName, tc.event, forkPolicy))
			})
		}
	}
}
