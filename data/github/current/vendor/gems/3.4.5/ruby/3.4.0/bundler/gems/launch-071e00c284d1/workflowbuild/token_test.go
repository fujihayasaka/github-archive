package workflowbuild

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/github/go-kvp"

	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchconfig"

	ghtypes "github.com/google/go-github/v25/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/types"
)

type gitHubEventName string

const create gitHubEventName = flowevents.Create
const deployment gitHubEventName = flowevents.Deployment
const deploymentStatus gitHubEventName = flowevents.DeploymentStatus
const dynamic gitHubEventName = flowevents.Dynamic
const push gitHubEventName = flowevents.Push
const pullRequestReviewComment gitHubEventName = flowevents.PullRequestReviewComment
const pullRequestReview gitHubEventName = flowevents.PullRequestReview
const pullRequest gitHubEventName = flowevents.PullRequest
const pullRequestTarget gitHubEventName = flowevents.PullRequestTarget
const workflowDispatch gitHubEventName = flowevents.WorkflowDispatch
const workflowRun gitHubEventName = flowevents.WorkflowRun
const issueComment gitHubEventName = flowevents.IssueComment
const gollum gitHubEventName = flowevents.Gollum
const noEventType gitHubEventName = ""
const unknownEventType gitHubEventName = "unknown_event_type"

// These groupings reflect the logic of clampDependabotDefaultPermissions
var untrustedDependabotEvents = []gitHubEventName{push, pullRequest, pullRequestReview, pullRequestReviewComment, create, deployment, deploymentStatus}
var trustedDependabotEvents = []gitHubEventName{issueComment, gollum, pullRequestTarget}

// Yes, it's just one but it allows us to make the test simpler
var nonDependabotActors = []*metadata.WorkflowMetadataActor{{IsDependabot: false, Login: "hashtagchris"}}

var forkReadPolicies = []types.ForkPRWorkflowsPolicy{
	types.ForkPRWorkflowsRunWorkflows,
	types.ForkPRWorkflowsRunWithSecrets,
}
var forkWritePolicies = []types.ForkPRWorkflowsPolicy{
	types.ForkPRWorkflowsRunWithTokens,
	types.ForkPRWorkflowsRunWithTokensAndSecrets,
}
var allForkPolicies = append(forkReadPolicies, forkWritePolicies...)

var pullRequestEventNames = []gitHubEventName{
	pullRequestReviewComment,
	pullRequestReview,
	pullRequest,
	pullRequestTarget,
}
var dependabotActor = &metadata.WorkflowMetadataActor{
	IsDependabot: true,
}

func TestWorkflowbuild_Token(t *testing.T) {
	suite.Run(t, new(workflowbuildTestSuite))
}

type workflowbuildTestSuite struct {
	suite.Suite
	tokenService *tokens.MockService
	tokenFactory TokenFactory
}

func (t *workflowbuildTestSuite) fakeRepoOrOwnersFFChecker(ctx context.Context, flag string, globalID types.GlobalID) bool {
	return false
}

func (t *workflowbuildTestSuite) SetupSuite() {
	env := launchconfig.AppEnv("test")
	t.tokenService = &tokens.MockService{}
	t.tokenFactory = NewTokenFactory(t.tokenService, t.fakeRepoOrOwnersFFChecker, env)

}

func (t *workflowbuildTestSuite) TestCalculateRunPermissions_ErrorGettingPullRequestNumber() {
	ctx := context.Background()
	obs := observability.NewNullObservability()

	eventName := pullRequest
	ghe := createEvent(eventName, false).(*ghtypes.PullRequestEvent)
	ghe.PullRequest.Number = nil

	for _, actor := range append(nonDependabotActors, dependabotActor) {
		settings, err := t.tokenFactory.CalculateRunPermissions(ctx, obs, string(eventName), ghe, types.WriteWorkflowPermissions, types.ForkPRWorkflowsRunWorkflows, actor)
		t.Assert().Nil(settings)
		t.Assert().Error(err)
	}
}

func (t *workflowbuildTestSuite) TestNewTokenSiteScoped() {
	testPerms := tokens.NewInstallationPermissions(tokens.WritePermissions)
	testCases := []struct {
		name          string
		repoID        types.GlobalID
		perms         *tokens.InstallationPermissions
		extendedPerms *tokens.ExtendedPermissions
		returnError   error
		returnToken   *tokens.AccessToken
	}{
		{
			name:          "return token",
			repoID:        types.GlobalID("repo-123"),
			perms:         testPerms,
			extendedPerms: nil,
			returnError:   nil,
			returnToken: &tokens.AccessToken{
				Token:       "token-123",
				Permissions: *testPerms,
			},
		},
		{
			name:          "return error",
			repoID:        types.GlobalID("repo-123"),
			perms:         testPerms,
			extendedPerms: nil,
			returnError:   errors.New("error"),
			returnToken:   nil,
		},
	}
	for _, c := range testCases {
		t.Run(c.name, func() {
			tokenSvc := tokens.NewMockService(t.T())
			tokenSvc.EXPECT().SiteScopedTokenForRepository(
				mock.Anything,
				c.repoID,
				int64(0),
				false,
				c.perms,
				c.extendedPerms,
			).Return(c.returnToken, c.returnError)

			ffEnabledChecker := func(ctx context.Context, flag string, globalID types.GlobalID) bool {
				return true
			}

			svc := NewTokenFactory(tokenSvc, ffEnabledChecker, launchconfig.LabAppEnv)
			token, err := svc.NewToken(context.Background(), c.repoID, c.perms, c.extendedPerms)

			if c.returnError != nil {
				t.Assert().Error(err)
				t.Assert().Nil(token)
				return
			}

			t.Assert().NoError(err)
			t.Assert().NotNil(token)
		})
	}
}

type calculateRunPermissionsTestCase struct {
	name                            string
	event                           gitHubEventName
	events                          []gitHubEventName
	isFork                          bool
	forkPolicy                      []types.ForkPRWorkflowsPolicy
	defaultWorkflowPermissions      types.DefaultWorkflowPermissions
	actor                           *metadata.WorkflowMetadataActor
	actors                          []*metadata.WorkflowMetadataActor
	expectedDefaultPermissions      tokens.TokenPermissionSet
	expectedInstallationPermissions tokens.TokenPermissionSet
	expectSarifs                    bool
}

func (t *workflowbuildTestSuite) TestCalculateRunPermissions_NoError() {
	testCases := []calculateRunPermissionsTestCase{
		{
			name:                            "Fork PR",
			event:                           pullRequest,
			isFork:                          true,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.ReadPermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Fork PR - PR review and comment events",
			events:                          []gitHubEventName{pullRequestReview, pullRequestReviewComment},
			isFork:                          true,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.ReadPermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "Fork PR - pull_request_target event",
			event:                           pullRequestTarget,
			isFork:                          true,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Fork PR with fork write policy",
			event:                           pullRequest,
			isFork:                          true,
			forkPolicy:                      forkWritePolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Fork PR with fork write policy - PR review events",
			events:                          []gitHubEventName{pullRequestReview, pullRequestReviewComment},
			isFork:                          true,
			forkPolicy:                      forkWritePolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "Fork PR with fork write policy (pull_request_target)",
			event:                           pullRequestTarget,
			isFork:                          true,
			forkPolicy:                      forkWritePolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Fork PR with limited token policy",
			event:                           pullRequest,
			isFork:                          true,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.ReadPermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Fork PR with limited token policy - PR review events",
			events:                          []gitHubEventName{pullRequestReview, pullRequestReviewComment},
			isFork:                          true,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.ReadPermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "Fork PR with limited token policy - pull_request_target event",
			event:                           pullRequestTarget,
			isFork:                          true,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Fork PR with fork write and limited token policy settings",
			event:                           pullRequest,
			isFork:                          true,
			forkPolicy:                      forkWritePolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Fork PR with fork write and limited token policy settings - PR review events",
			events:                          []gitHubEventName{pullRequestReview, pullRequestReviewComment},
			isFork:                          true,
			forkPolicy:                      forkWritePolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "Fork PR with fork write and limited token policy settings - pull_request_target event",
			event:                           pullRequestTarget,
			isFork:                          true,
			forkPolicy:                      forkWritePolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "pull_request event",
			event:                           pullRequest,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "pull_request_review and pull_request_review_comment events",
			events:                          []gitHubEventName{pullRequestReview, pullRequestReviewComment},
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "pull_request_target event",
			event:                           pullRequestTarget,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "pull_request event with limited token policy",
			event:                           pullRequest,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "pull_request_review and pull_request_review_comment events with limited token policy",
			events:                          []gitHubEventName{pullRequestReview, pullRequestReviewComment},
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "pull_request_target event with limited token policy",
			event:                           pullRequestTarget,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Dependabot-triggered PR event",
			event:                           pullRequest,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Dependabot-triggered PR review events",
			events:                          []gitHubEventName{pullRequestReview, pullRequestReviewComment},
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "Dependabot-triggered pull_request_target event",
			event:                           pullRequestTarget,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Dependabot-triggered pull_request event with limited token policy",
			event:                           pullRequest,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Dependabot-triggered pull_request event with limited token policy - PR review events",
			events:                          []gitHubEventName{pullRequestReview, pullRequestReviewComment},
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "Dependabot-triggered pull_request event with limited token policy - pull_request_target event",
			event:                           pullRequestTarget,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},

		// Next three test cases: Documenting new behavior where fork policy does not affect non-fork PR's if the actor is Dependabot
		// See https://github.com/github/c2c-actions-experience/issues/5411 for more info
		{
			name:                            "Dependabot-triggered PR event with fork write policy",
			event:                           pullRequest,
			isFork:                          false,
			forkPolicy:                      allForkPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "Dependabot-triggered PR review events with fork write policy",
			events:                          []gitHubEventName{pullRequestReview, pullRequestReviewComment},
			isFork:                          false,
			forkPolicy:                      append(forkWritePolicies, forkReadPolicies...),
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "Dependabot-triggered pull_request_target event with fork write policy",
			event:                           pullRequestTarget,
			isFork:                          false,
			forkPolicy:                      append(forkWritePolicies, forkReadPolicies...),
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    true,
		},
		{
			name:                            "push event",
			event:                           push,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "push event with limited token policy",
			event:                           push,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "Dependabot-triggered push event",
			event:                           push,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "Dependabot-triggered push event with limited token policy",
			event:                           push,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "dynamic event",
			event:                           dynamic,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "dynamic event queued by dependabot",
			event:                           dynamic,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.ReadPermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "workflow_dispatch event",
			event:                           workflowDispatch,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "workflow_dispatch event triggered by dependabot",
			event:                           workflowDispatch,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.ReadPermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "workflow_dispatch event triggered by dependabot with limited token policy",
			event:                           workflowDispatch,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.ReadPermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "workflow_run event triggered by dependabot",
			event:                           workflowRun,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "workflow_run event triggered by dependabot with limited token policy",
			event:                           workflowRun,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.LimitedReadWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.LimitedReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		// create, deployment and deployment_status events
		{
			name:                            "newly restricted dependabot events, triggered by non-dependabot actors",
			events:                          []gitHubEventName{create, deployment, deploymentStatus},
			isFork:                          false,
			forkPolicy:                      allForkPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "newly restricted dependabot events, triggered by dependabot",
			events:                          []gitHubEventName{create, deployment, deploymentStatus},
			isFork:                          false,
			forkPolicy:                      allForkPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "No event type gets default permissions",
			event:                           noEventType,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "No event type triggered by dependabot gets read-only permissions",
			event:                           noEventType,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.ReadPermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "Unknown event type gets default permissions",
			event:                           unknownEventType,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actors:                          nonDependabotActors,
			expectedDefaultPermissions:      tokens.WritePermissions,
			expectedInstallationPermissions: tokens.WritePermissions,
			expectSarifs:                    false,
		},
		{
			name:                            "Unknown event type triggered by dependabot gets readonly permissions",
			event:                           unknownEventType,
			isFork:                          false,
			forkPolicy:                      forkReadPolicies,
			defaultWorkflowPermissions:      types.WriteWorkflowPermissions,
			actor:                           dependabotActor,
			expectedDefaultPermissions:      tokens.ReadPermissions,
			expectedInstallationPermissions: tokens.ReadPermissions,
			expectSarifs:                    false,
		},
	}

	for _, tc := range testCases {
		if tc.event != "" && len(tc.events) != 0 {
			panic("You can't set both event and events")
		}

		events := tc.events
		if len(events) == 0 {
			events = []gitHubEventName{tc.event}
		}

		if tc.actor != nil && len(tc.actors) != 0 {
			panic("You can't set both actor and actors")
		}

		actors := tc.actors
		if len(actors) == 0 {
			actors = []*metadata.WorkflowMetadataActor{tc.actor}
		}

		if len(tc.forkPolicy) == 0 {
			panic("You must specify at least one fork policy")
		}

		for _, event := range events {
			ghe := createEvent(event, tc.isFork)
			for _, actor := range actors {
				for _, forkPolicy := range tc.forkPolicy {
					t.Run(fmt.Sprintf("%v (event: %v, actor: %v, forkPolicy: %v)", tc.name, event, actor, forkPolicy), func() {
						ctx := context.Background()
						obs := observability.NewNullObservability()

						settings, err := t.tokenFactory.CalculateRunPermissions(
							ctx,
							obs,
							string(event),
							ghe,
							tc.defaultWorkflowPermissions,
							forkPolicy,
							actor)

						t.Assert().NoError(err)
						t.Assert().Equal(tc.expectedDefaultPermissions, settings.DefaultPermissions)
						t.Assert().Equal(tokens.NewInstallationPermissions(tc.expectedInstallationPermissions), &settings.InstallationPermissions)
						if tc.expectSarifs {
							assertSarifs(t.T(), *getPullRequestNumber(event, ghe), settings.ExtendedPermissions, "")
						} else {
							t.Assert().Nil(settings.ExtendedPermissions)
						}
					})
				}
			}
		}
	}
}

type calculateJobPermissionsTestCase struct {
	name                        string
	event                       gitHubEventName
	events                      []gitHubEventName
	settings                    *tokens.PermissionSettings
	userRequestedPerms          map[string]string
	expectedPermissions         func() *tokens.InstallationPermissions
	expectedExtendedPermissions func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions
	workflowRunID               int64
	requestedWorkflowRunPerms   map[string]string
	expectedReportedErrors      int
}

func (t *workflowbuildTestSuite) TestCalculateJobPermissions() {
	testCases := []calculateJobPermissionsTestCase{
		{
			name: "default permissions all scopes",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
				DefaultPermissions:      tokens.WritePermissions,
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				return tokens.NewInstallationPermissions(tokens.WritePermissions)
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name: "default permissions, all scopes, forkPR",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
				DefaultPermissions:      tokens.ReadPermissions,
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				return tokens.NewInstallationPermissions(tokens.ReadPermissions)
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name: "default permissions, limited scopes",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
				DefaultPermissions:      tokens.LimitedReadPermissions,
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := tokens.NewInstallationPermissions(tokens.LimitedReadPermissions)
				err := expected.MergeMinimum(tokens.NewInstallationPermissions(tokens.WritePermissions))
				t.NoError(err)
				return expected
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name: "default permissions, limited scopes, fork PR",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
				DefaultPermissions:      tokens.LimitedReadPermissions,
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := tokens.NewInstallationPermissions(tokens.LimitedReadPermissions)
				err := expected.MergeMinimum(tokens.NewInstallationPermissions(tokens.WritePermissions))
				t.NoError(err)
				return expected
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name: "default permissions, limited by max permissions, write gets lowered to read",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
				DefaultPermissions:      tokens.WritePermissions,
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				return tokens.NewInstallationPermissions(tokens.ReadPermissions)
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name: "default permissions, limited by max permissions, write gets lowered to limited read",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.LimitedReadPermissions),
				DefaultPermissions:      tokens.WritePermissions,
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := tokens.NewInstallationPermissions(tokens.LimitedReadPermissions)
				err := expected.MergeMinimum(tokens.NewInstallationPermissions(tokens.WritePermissions))
				t.NoError(err)
				return expected
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name: "default permissions, limited by max permissions, read gets lowered to limited read",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.LimitedReadPermissions),
				DefaultPermissions:      tokens.ReadPermissions,
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := tokens.NewInstallationPermissions(tokens.LimitedReadPermissions)
				err := expected.MergeMinimum(tokens.NewInstallationPermissions(tokens.WritePermissions))
				t.NoError(err)
				return expected
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name: "user requested, limits by max permissions: max is write",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
				DefaultPermissions:      tokens.LimitedReadPermissions,
			},
			userRequestedPerms: map[string]string{
				"Contents": string(tokens.ReadAccess),
				"Issues":   string(tokens.WriteAccess),
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := &tokens.InstallationPermissions{
					Contents: tokens.ReadAccess,
					Issues:   tokens.WriteAccess,
					Metadata: tokens.ReadAccess,
				}
				err := expected.MergeMinimum(tokens.NewInstallationPermissions(tokens.WritePermissions)) // set all "none" permissions to ""
				t.NoError(err)
				return expected
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name: "user requested, limits by max permissions: max is read",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
				DefaultPermissions:      tokens.LimitedReadPermissions,
			},
			userRequestedPerms: map[string]string{
				"Contents": string(tokens.ReadAccess),
				"Issues":   string(tokens.WriteAccess),
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := &tokens.InstallationPermissions{
					Contents: tokens.ReadAccess,
					Issues:   tokens.ReadAccess,
					Metadata: tokens.ReadAccess,
				}
				err := expected.MergeMinimum(tokens.NewInstallationPermissions(tokens.ReadPermissions)) // set all "none" permissions to ""
				t.NoError(err)
				return expected
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name: "user requested, sets metadata read",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
				DefaultPermissions:      tokens.WritePermissions,
			},
			userRequestedPerms: map[string]string{
				"Contents": string(tokens.ReadAccess),
				"Issues":   string(tokens.WriteAccess),
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := &tokens.InstallationPermissions{
					Contents: tokens.ReadAccess,
					Issues:   tokens.WriteAccess,
					Metadata: tokens.ReadAccess,
				}
				return expected
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name: "workflow run id set, extended permissions for workflow run",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
				DefaultPermissions:      tokens.WritePermissions,
			},
			userRequestedPerms: map[string]string{
				"Contents": string(tokens.ReadAccess),
				"Issues":   string(tokens.WriteAccess),
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := &tokens.InstallationPermissions{
					Contents: tokens.ReadAccess,
					Issues:   tokens.WriteAccess,
					Metadata: tokens.ReadAccess,
				}
				return expected
			},
			workflowRunID: 124,
			requestedWorkflowRunPerms: map[string]string{
				"codespaces_prebuild": string(tokens.WriteAccess),
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return &tokens.ExtendedPermissions{
					PerWorkflowRunPermissions: &tokens.PerWorkflowRunPermissions{
						ID: 124,
						Permissions: &tokens.WorkflowRunInstallationPermissions{
							CodespacesPrebuild: tokens.WriteAccess,
						},
					},
				}
			},
		},
		{
			name: "bogus workflow run permissions are ignored",
			settings: &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
				DefaultPermissions:      tokens.WritePermissions,
			},
			userRequestedPerms: map[string]string{
				"Contents": string(tokens.ReadAccess),
				"Issues":   string(tokens.WriteAccess),
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := &tokens.InstallationPermissions{
					Contents: tokens.ReadAccess,
					Issues:   tokens.WriteAccess,
					Metadata: tokens.ReadAccess,
				}
				return expected
			},
			workflowRunID: 124,
			requestedWorkflowRunPerms: map[string]string{
				"bogus":               string(tokens.ReadAccess),
				"codespaces_prebuild": "bogus",
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
			expectedReportedErrors: 1,
		},
	}

	errReporter := &mockErrorReporter{}

	for _, tc := range testCases {
		t.Run(tc.name, func() {
			perms, extendedPerms, err := t.tokenFactory.CalculateJobPermissions(
				context.Background(), errReporter, tc.settings, tc.userRequestedPerms, tc.workflowRunID, tc.requestedWorkflowRunPerms,
			)
			t.Assert().NoError(err)
			t.Assert().Equal(tc.expectedPermissions(), perms)
			t.Assert().Equal(tc.expectedExtendedPermissions(tc.settings), extendedPerms)
			t.Assert().Equal(tc.expectedReportedErrors, len(errReporter.reportedErrors))
		})
	}
}

type mockErrorReporter struct {
	reportedErrors []string
}

func (m *mockErrorReporter) Report(ctx context.Context, err error, fields ...kvp.Field) {
	m.reportedErrors = append(m.reportedErrors, fmt.Sprintf("%v: %v", err, fields))
}

func (t *workflowbuildTestSuite) TestCalculateJobPermissions_Dependabot() {
	testCases := []calculateJobPermissionsTestCase{
		{
			name:   "workflow requested read permissions in YAML",
			events: append(untrustedDependabotEvents, trustedDependabotEvents...),
			userRequestedPerms: map[string]string{
				"Contents": string(tokens.ReadAccess),
				"Issues":   string(tokens.ReadAccess),
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := &tokens.InstallationPermissions{
					Contents: tokens.ReadAccess,
					Issues:   tokens.ReadAccess,
					Metadata: tokens.ReadAccess,
				}
				return expected
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name:  "workflow requested write permissions in YAML, dynamic",
			event: dynamic,
			userRequestedPerms: map[string]string{
				"Contents": string(tokens.WriteAccess),
				"Issues":   string(tokens.WriteAccess),
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := &tokens.InstallationPermissions{
					Contents: tokens.ReadAccess,
					Issues:   tokens.ReadAccess,
					Metadata: tokens.ReadAccess,
				}
				return expected
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name:  "workflow requested write permissions in YAML, workflow_dispatch",
			event: workflowDispatch,
			userRequestedPerms: map[string]string{
				"Contents": string(tokens.WriteAccess),
				"Issues":   string(tokens.WriteAccess),
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := &tokens.InstallationPermissions{
					Contents: tokens.ReadAccess,
					Issues:   tokens.ReadAccess,
					Metadata: tokens.ReadAccess,
				}
				return expected
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name:   "workflow requested write permissions in YAML, trusted and untrusted events",
			events: append(trustedDependabotEvents, untrustedDependabotEvents...),
			userRequestedPerms: map[string]string{
				"Contents": string(tokens.WriteAccess),
				"Issues":   string(tokens.WriteAccess),
			},
			expectedPermissions: func() *tokens.InstallationPermissions {
				expected := &tokens.InstallationPermissions{
					Contents: tokens.WriteAccess,
					Issues:   tokens.WriteAccess,
					Metadata: tokens.ReadAccess,
				}
				return expected
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name:  "workflow requested no permissions in YAML, dynamic",
			event: dynamic,
			expectedPermissions: func() *tokens.InstallationPermissions {
				return tokens.NewInstallationPermissions(tokens.ReadPermissions)
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name:  "workflow requested no permissions in YAML, workflow_dispatch",
			event: workflowDispatch,
			expectedPermissions: func() *tokens.InstallationPermissions {
				return tokens.NewInstallationPermissions(tokens.ReadPermissions)
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name:   "workflow requested no permissions in YAML, trusted event",
			events: trustedDependabotEvents,
			expectedPermissions: func() *tokens.InstallationPermissions {
				return tokens.NewInstallationPermissions(tokens.WritePermissions)
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
		{
			name:   "workflow requested no permissions in YAML, untrusted events",
			events: untrustedDependabotEvents,
			expectedPermissions: func() *tokens.InstallationPermissions {
				return tokens.NewInstallationPermissions(tokens.ReadPermissions)
			},
			expectedExtendedPermissions: func(settings *tokens.PermissionSettings) *tokens.ExtendedPermissions {
				return settings.ExtendedPermissions
			},
		},
	}

	errReporter := &mockErrorReporter{}
	for _, tc := range testCases {
		if tc.event != "" && len(tc.events) != 0 {
			panic("You can't set both event and events")
		}

		events := tc.events
		if len(events) == 0 {
			events = []gitHubEventName{tc.event}
		}

		for _, event := range events {
			t.Run(fmt.Sprintf("%v (actor: %v, event: %v):", tc.name, dependabotActor, event), func() {
				permissionSettings := t.getDependabotPermissionSettingsForEvent(dependabotActor, event)
				perms, extendedPerms, err := t.tokenFactory.CalculateJobPermissions(
					context.Background(), errReporter, permissionSettings, tc.userRequestedPerms, tc.workflowRunID, tc.requestedWorkflowRunPerms,
				)
				t.Assert().NoError(err)
				t.Assert().Equal(tc.expectedPermissions(), perms)
				t.Assert().Equal(tc.expectedExtendedPermissions(permissionSettings), extendedPerms)
			})
		}
	}
}

func (t *workflowbuildTestSuite) TestCalculateJobPermissionsPreservesExistingPermissionsWithWorkflowRunPermissions() {
	settings := &tokens.PermissionSettings{
		DefaultPermissions: tokens.ReadPermissions,
		ExtendedPermissions: &tokens.ExtendedPermissions{
			PerPullRequestPermissions: &tokens.PerPullRequestPermissions{
				Number: 1,
				Permissions: tokens.PullRequestInstallationPermissions{
					Sarifs: tokens.WriteAccess,
				},
			},
		},
	}

	_, extendedPerms, err := t.tokenFactory.CalculateJobPermissions(context.Background(), nil, settings, nil, 1, map[string]string{"codespaces_prebuild": "write"})
	t.Assert().NoError(err)
	t.Assert().Equal(extendedPerms, &tokens.ExtendedPermissions{
		PerPullRequestPermissions: &tokens.PerPullRequestPermissions{
			Number: 1,
			Permissions: tokens.PullRequestInstallationPermissions{
				Sarifs: tokens.WriteAccess,
			},
		},
		PerWorkflowRunPermissions: &tokens.PerWorkflowRunPermissions{
			ID: 1,
			Permissions: &tokens.WorkflowRunInstallationPermissions{
				CodespacesPrebuild: tokens.WriteAccess,
			},
		},
	})
}

func (t *workflowbuildTestSuite) TestCalculateJobPermissionsPreservesExistingPermissionsWithNoWorkflowRunPermissions() {
	settings := &tokens.PermissionSettings{
		DefaultPermissions: tokens.ReadPermissions,
		ExtendedPermissions: &tokens.ExtendedPermissions{
			PerPullRequestPermissions: &tokens.PerPullRequestPermissions{
				Number: 1,
				Permissions: tokens.PullRequestInstallationPermissions{
					Sarifs: tokens.WriteAccess,
				},
			},
		},
	}

	_, extendedPerms, err := t.tokenFactory.CalculateJobPermissions(context.Background(), nil, settings, nil, 1, nil)
	t.Assert().NoError(err)
	t.Assert().Equal(extendedPerms, &tokens.ExtendedPermissions{
		PerPullRequestPermissions: &tokens.PerPullRequestPermissions{
			Number: 1,
			Permissions: tokens.PullRequestInstallationPermissions{
				Sarifs: tokens.WriteAccess,
			},
		},
	})
}

func (t *workflowbuildTestSuite) getDependabotPermissionSettingsForEvent(actor *metadata.WorkflowMetadataActor, eventName gitHubEventName) *tokens.PermissionSettings {
	ctx := context.Background()
	obs := observability.NewNullObservability()

	if !flowevents.IsDependabotActor(actor) {
		t.Fail("only accepts dependabot actor")
	}
	ghe := createEvent(eventName, false)
	settings, err := t.tokenFactory.CalculateRunPermissions(ctx, obs, string(eventName), ghe, types.WriteWorkflowPermissions, types.ForkPRWorkflowsRunWorkflows, actor)
	t.NoError(err)
	return settings
}

func createEvent(eventName gitHubEventName, isFork bool) flowevents.GitHubEvent {
	prNumber := 4
	baseRepoID := int64(5)
	var headRepoID int64
	if isFork {
		headRepoID = int64(6)
	} else {
		headRepoID = baseRepoID
	}
	pr := &ghtypes.PullRequest{
		Number: &prNumber,
		Base: &ghtypes.PullRequestBranch{
			Repo: &ghtypes.Repository{
				ID: &baseRepoID,
			},
		},
		Head: &ghtypes.PullRequestBranch{
			Repo: &ghtypes.Repository{
				ID: &headRepoID,
			},
		},
	}

	switch eventName {
	case create:
		return &ghtypes.CreateEvent{}
	case deployment:
		return &ghtypes.DeploymentEvent{}
	case deploymentStatus:
		return &ghtypes.DeploymentStatusEvent{}
	case dynamic:
		return &flowevents.DynamicEvent{}
	case pullRequestReviewComment:
		return &ghtypes.PullRequestReviewCommentEvent{
			PullRequest: pr,
		}
	case pullRequestReview:
		return &ghtypes.PullRequestReviewEvent{
			PullRequest: pr,
		}
	case pullRequest, pullRequestTarget:
		return &ghtypes.PullRequestEvent{
			PullRequest: pr,
		}
	case push:
		return &ghtypes.PushEvent{}
	case workflowDispatch:
		return &ghtypes.WorkflowDispatchEvent{}
	case issueComment:
		return &ghtypes.IssueCommentEvent{}
	case workflowRun:
		return &ghtypes.WorkflowRunEvent{}
	case gollum:
		return &ghtypes.GollumEvent{}
	case noEventType:
		return struct{}{}
	case unknownEventType:
		return struct{}{}
	}

	panic(fmt.Sprintf("Unexpected event name '%s'", eventName))
}

func getPullRequestNumber(eventName gitHubEventName, ghe flowevents.GitHubEvent) *int {
	var number *int
	var pullRequest *ghtypes.PullRequest
	switch eventName {
	case flowevents.PullRequestReview:
		pullRequest = ghe.(*ghtypes.PullRequestReviewEvent).PullRequest
	case flowevents.PullRequestReviewComment:
		pullRequest = ghe.(*ghtypes.PullRequestReviewCommentEvent).PullRequest
	case flowevents.PullRequest, flowevents.PullRequestTarget:
		pullRequest = ghe.(*ghtypes.PullRequestEvent).PullRequest
	}

	if pullRequest != nil {
		number = pullRequest.Number
	}
	return number
}

func assertSarifs(t *testing.T, prNumber int, extendedPerms *tokens.ExtendedPermissions, message string) {
	var expected = &tokens.ExtendedPermissions{
		PerPullRequestPermissions: &tokens.PerPullRequestPermissions{
			Number: prNumber,
			Permissions: tokens.PullRequestInstallationPermissions{
				Sarifs: tokens.WriteAccess,
			},
		},
	}
	assert.Equal(t, expected, extendedPerms, message)
}
