package workflowinvoker

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	gogithub "github.com/google/go-github/v25/github"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"github.com/shurcooL/githubv4"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/clients/runservice"
	"github.com/github/launch/config/customerlabels"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/clock"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/secureref"
	"github.com/github/launch/workflowbuild/build"
)

const (
	repoID             = types.GlobalID("R_kgDNA-c")
	repoDatabaseID     = int64(135493233)
	commitSha          = types.CommitSha("d6fde92930d4715a2b49857d24b940956b26d2d3")
	commitMessage      = types.CommitMessage("test-e2e commit from build version 2a9c2286514691322691606c3c24a45c5b4136db")
	actorID            = types.GlobalID("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
	actorLogin         = "octocat"
	nextRepoID         = types.GlobalID("R_kgAD=")
	nextRepoDatabaseID = int64(3)
	nextActorID        = types.GlobalID("U_kgDOAAjmPw")
	nextOwnerID        = types.GlobalID("U_kgDOAP3FAg")
	ownerDatabaseID    = int64(2)
)

var (
	checkSuiteID        = int64(12345)
	checkSuiteNodeID    = "check-suite-1234"
	checkSuiteAction    = "rerequested"
	forkRepoNodeID      = "MDEwOlJlcG9zaXRvcnkxMjM0NTY3ODk="
	forkRepoName        = "launch"
	forkRepoOwner       = "octocat"
	forkRepoOwnerNodeID = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
	forkedRef           = "changes"
	baseRef             = "main"
	defaultGitHubTenant = ghtenant.GitHubTenant{}
)

var stubEvent flowevents.GitHubEvent = map[string]any{}

var stubCheckSuiteEvent = &gogithub.CheckSuiteEvent{
	Action: &checkSuiteAction,
	CheckSuite: &gogithub.CheckSuite{
		ID:     &checkSuiteID,
		NodeID: &checkSuiteNodeID,
	},
}
var stubPullRequestEvent = &gogithub.PullRequestEvent{
	PullRequest: &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Ref: &forkedRef,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
				Name:   &forkRepoName,
				Owner: &gogithub.User{
					Login:  &forkRepoOwner,
					NodeID: &forkRepoOwnerNodeID,
				},
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseRef,
		},
	},
}
var actor = NewActor(
	actorID,
	actorLogin,
)
var actorNext = NewActor(
	nextActorID,
	actorLogin,
)

var pushTarget = NewTarget(
	repoID,
	repoDatabaseID,
	WorkflowSelector{
		EventName: "push",
	},
	nextOwnerID,
	ownerDatabaseID,
	defaultGitHubTenant,
)

var pushNextTarget = NewTarget(
	nextRepoID,
	nextRepoDatabaseID,
	WorkflowSelector{
		EventName: "push",
	},
	nextOwnerID,
	0,
	defaultGitHubTenant,
)

var eventOriginTime = time.Now()

var webhookDeliveryID = uuid.New().String()
var pushEvent = NewEvent(
	&webhookDeliveryID,
	types.DefaultBranch,
	commitSha,
	commitMessage,
	"push",
	"",
	nil,
	time.Time{},
	eventOriginTime,
	stubEvent,
)

var pushInvocation = NewInvocation(pushEvent, actor, actor, pushTarget)
var pushNextInvocation = NewInvocation(pushEvent, actorNext, actorNext, pushNextTarget)

type stringTestingFunc func(string)

type InvokerTestSuite struct {
	suite.Suite

	invoker *invoker

	mockErrorHandler     *MockWorkflowStartErrHandler
	mockWorkflowInvoker  *MockWorkflowInvoker
	mockTwirpClient      *ghtwirp.MockClient
	mockClient           *github.MockClient
	mockClock            *clock.Mock
	isUserSpammy         bool
	isRepoDisabled       bool
	mockRunServiceClient *runservice.MockClient
	mockResultsClient    *results.MockClient
}

func fixture(t *testing.T, name string) []byte {
	data, err := os.ReadFile(filepath.Join("fixtures", name))
	require.NoError(t, err, "Reading %s fixture should not error", name)
	return data
}

func (s *InvokerTestSuite) SetupTest() {
	mockClientFactory := github.NewMockClientFactory()
	mockClient := &github.MockClient{}
	mockClientFactory.ByRepositoryID[nextRepoID] = mockClient
	mockClientFactory.ByRepositoryOwnerID[nextOwnerID] = mockClient
	mockClientFactory.ByRepositoryOwnerDatabaseID[2] = mockClient

	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	masterRef := types.NewBranchRef("master")

	mockClient.On("ResolveDefaultBranch", mock.Anything, repoID).Return(commitSha, masterRef, nil)
	mockClient.On("ResolveRef", mock.Anything, repoID, masterRef).Return(commitSha, masterRef, nil)
	mockClient.On("ResolveDefaultBranch", mock.Anything, nextRepoID).Return(commitSha, masterRef, nil)
	mockClient.On("ResolveRef", mock.Anything, nextRepoID, masterRef).Return(commitSha, masterRef, nil)
	s.mockClient = mockClient

	mockBuildsRepo := &deployer.MockWorkflowBuildsRepository{}

	ghTwirpClient := &ghtwirp.MockClient{}
	ghTwirpClient.On("IsUserSpammy", mock.Anything, mock.Anything).Return(func(ctx context.Context, id types.GlobalID) bool {
		return s.isUserSpammy
	}, nil)
	ghTwirpClient.On("IsRepositoryActionsDisabled", mock.Anything, mock.Anything).Return(func(ctx context.Context, id types.GlobalID) bool {
		return s.isRepoDisabled
	}, nil)
	s.mockTwirpClient = ghTwirpClient

	s.mockWorkflowInvoker = &MockWorkflowInvoker{}
	mockWorkflowInvokerFactory := &MockWorkflowInvokerFactory{}
	mockWorkflowInvokerFactory.On("Build", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(s.mockWorkflowInvoker)

	s.mockErrorHandler = &MockWorkflowStartErrHandler{}
	s.mockErrorHandler.On("CreateErrorCheckSuite", mock.Anything, mock.Anything)
	mockErrorHandlerFactory := &MockWorkflowStartErrHandlerFactory{}
	mockErrorHandlerFactory.EXPECT().Build(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, false, false).Return(s.mockErrorHandler)

	s.mockClock = clock.NewMock(1000)

	s.mockRunServiceClient = &runservice.MockClient{}
	s.mockResultsClient = &results.MockClient{}

	s.invoker = &invoker{
		errorHandlerFactory:    mockErrorHandlerFactory,
		workflowInvokerFactory: mockWorkflowInvokerFactory,
		ghClientFactory:        mockClientFactory,
		ghTwirpClient:          s.mockTwirpClient,
		repo:                   mockBuildsRepo,
		env:                    launchconfig.ProductionAppEnv,
		clock:                  s.mockClock,
		backoffTimer:           NewTestBackoffTimer(s.mockClock),
		runServiceClient:       s.mockRunServiceClient,
		resultsClient:          s.mockResultsClient,
	}
}

func (s *InvokerTestSuite) TestInvokerStartErrorHandlingWithFinalAttemptCreatesCheckSuite() {
	ctx := newTestContext()

	s.mockClient.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)
	s.mockClient.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      false,
			Closed:      false,
			Mergeable:   githubv4.MergeableStateMergeable,
			MergeCommit: "test",
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				"parent-sha",
			},
		}, nil)
	s.mockClient.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.isUserSpammy = false
	s.isRepoDisabled = false

	s.mockWorkflowInvoker.On("Start", mock.Anything, mock.Anything, mock.Anything).Return(&WorkflowStartErr{
		stepErr:   errors.New("some error"),
		retryable: true,
	})
	isFinalAttempt := true
	err := s.invoker.Start(ctx, observability.NewNullObservability(), pushInvocation, isFinalAttempt, customerlabels.NewNoopCustomerLabeler())
	s.mockWorkflowInvoker.AssertNumberOfCalls(s.T(), "Start", 1)
	s.mockErrorHandler.AssertNumberOfCalls(s.T(), "CreateErrorCheckSuite", 1)
	s.Require().Error(err)
	s.True(terrors.IsRetryable(err))
}

func (s *InvokerTestSuite) TestInvokerStartInternalError() {
	ctx := newTestContext()

	s.mockClient.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)
	s.mockClient.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      false,
			Closed:      false,
			Mergeable:   githubv4.MergeableStateMergeable,
			MergeCommit: "test",
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				"parent-sha",
			},
		}, nil)
	s.mockClient.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.isUserSpammy = false
	s.isRepoDisabled = false

	s.mockWorkflowInvoker.On("Start", mock.Anything, mock.Anything, mock.Anything).Return(&WorkflowStartErr{
		stepErr:   terrors.NewInternalError(errors.New("some internal error")),
		retryable: false,
	})
	isFinalAttempt := false
	err := s.invoker.Start(ctx, observability.NewNullObservability(), pushInvocation, isFinalAttempt, customerlabels.NewNoopCustomerLabeler())
	s.mockWorkflowInvoker.AssertNumberOfCalls(s.T(), "Start", 1)
	s.mockErrorHandler.AssertNumberOfCalls(s.T(), "CreateErrorCheckSuite", 1)
	s.Require().Error(err)
	s.False(terrors.IsRetryable(err))
}

func (s *InvokerTestSuite) TestInvokerErrorHandlerCreatesCheckSuiteWithNotRetryableError() {
	ctx := newTestContext()

	s.mockClient.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)
	s.mockClient.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      false,
			Closed:      false,
			Mergeable:   githubv4.MergeableStateMergeable,
			MergeCommit: "test",
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				"parent-sha",
			},
		}, nil)
	s.mockClient.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.isUserSpammy = false

	s.mockWorkflowInvoker.On("Start", mock.Anything, mock.Anything, mock.Anything).Return(&WorkflowStartErr{
		stepErr:   errors.New("some error"),
		retryable: false,
	})
	isFinalAttempt := false
	err := s.invoker.Start(ctx, observability.NewNullObservability(), pushInvocation, isFinalAttempt, customerlabels.NewNoopCustomerLabeler())
	s.mockWorkflowInvoker.AssertNumberOfCalls(s.T(), "Start", 1)
	s.mockErrorHandler.AssertNumberOfCalls(s.T(), "CreateErrorCheckSuite", 1)
	s.Require().Error(err)
	s.False(terrors.IsRetryable(err))
}

func (s *InvokerTestSuite) TestInvokerErrorHandlerReturnsErrorForQueueAndRetryableErrors() {
	ctx := newTestContext()

	s.mockClient.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)
	s.mockClient.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      false,
			Closed:      false,
			Mergeable:   githubv4.MergeableStateMergeable,
			MergeCommit: "test",
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				"parent-sha",
			},
		}, nil)
	s.mockClient.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.isUserSpammy = false

	s.mockWorkflowInvoker.On("Start", mock.Anything, mock.Anything, mock.Anything).Return(&WorkflowStartErr{
		stepErr:   errors.New("some error"),
		retryable: true,
	})
	isFinalAttempt := false
	err := s.invoker.Start(ctx, observability.NewNullObservability(), pushInvocation, isFinalAttempt, customerlabels.NewNoopCustomerLabeler())
	s.mockWorkflowInvoker.AssertNumberOfCalls(s.T(), "Start", 1)
	s.mockErrorHandler.AssertNumberOfCalls(s.T(), "CreateErrorCheckSuite", 0)
	s.Require().Error(err)
	s.True(terrors.IsRetryable(err))
}

func (s *InvokerTestSuite) TestInvokerRetriesForMergeCommitTimeouts() {
	ctx := newTestContext()

	s.mockClient.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(nil, ErrMergeableCommitTimeout)
	s.mockClient.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      false,
			Closed:      false,
			Mergeable:   githubv4.MergeableStateMergeable,
			MergeCommit: "test",
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				"parent-sha",
			},
		}, ErrMergeableCommitTimeout).Maybe()
	s.mockClient.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.isUserSpammy = false

	err := s.invoker.Start(ctx, observability.NewNullObservability(), pushInvocation, false, customerlabels.NewNoopCustomerLabeler())
	s.mockWorkflowInvoker.AssertNumberOfCalls(s.T(), "Start", 0)
	s.mockErrorHandler.AssertNumberOfCalls(s.T(), "CreateErrorCheckSuite", 0)
	s.Require().Error(err)
	s.True(terrors.IsRetryable(err))
}

func (s *InvokerTestSuite) TestInvokerSpammyUser() {
	s.isUserSpammy = true

	ctx := newTestContext()
	err := s.invoker.Start(ctx, observability.NewNullObservability(), pushInvocation, true, customerlabels.NewNoopCustomerLabeler())
	s.Require().NoError(err)
	s.mockWorkflowInvoker.AssertNotCalled(s.T(), "Start")
}

func (s *InvokerTestSuite) TestInvokerSpammyRepositoryWithGraphQLNotFound() {
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	mergeCommitSha := types.CommitSha("merge-commit-sha")

	webhookDeliveryID := uuid.New().String()
	var pullRequestEvent = NewEvent(
		&webhookDeliveryID,
		types.DefaultBranch,
		commitSha,
		"",
		"pull_request",
		"",
		nil,
		time.Time{},
		eventOriginTime,
		stubPullRequestEvent,
	)
	var pullRequestTarget = NewTarget(
		repoID,
		repoDatabaseID,
		WorkflowSelector{
			EventName: "pull_request",
		},
		nextOwnerID,
		ownerDatabaseID,
		defaultGitHubTenant,
	)
	prInvocation := NewInvocation(pullRequestEvent, actor, actor, pullRequestTarget)

	s.isRepoDisabled = true

	s.mockClient.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      false,
			Closed:      false,
			Mergeable:   githubv4.MergeableStateMergeable,
			MergeCommit: mergeCommitSha,
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				commitSha,
			},
		}, nil)
	s.mockClient.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(
		nil,
		terrors.NewGraphQLError(errors.New("Not Found")),
	)
	s.mockClient.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	ctx := newTestContext()
	err := s.invoker.Start(ctx, observability.NewNullObservability(), prInvocation, true, customerlabels.NewNoopCustomerLabeler())
	s.Require().NoError(err)
	s.mockWorkflowInvoker.AssertNotCalled(s.T(), "Start")
	s.mockTwirpClient.AssertNumberOfCalls(s.T(), "IsRepositoryActionsDisabled", 1)
	s.mockTwirpClient.AssertNumberOfCalls(s.T(), "IsUserSpammy", 1)
}

func (s *InvokerTestSuite) TestInvokerPushEventCommitWithSkipCINotInvoked() {
	afterSha := "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	commitMessage := types.CommitMessage("this commit should [skip ci]")

	ghe := &gogithub.PushEvent{
		After: &afterSha,
	}

	webhookDeliveryID := uuid.New().String()
	pushEvent := NewEvent(
		&webhookDeliveryID,
		types.DefaultBranch,
		commitSha,
		commitMessage,
		"push",
		"",
		nil,
		time.Time{},
		eventOriginTime,
		ghe,
	)
	pushTarget := NewTarget(
		repoID,
		repoDatabaseID,
		WorkflowSelector{
			EventName: "push",
		},
		nextOwnerID,
		ownerDatabaseID,
		defaultGitHubTenant,
	)
	pushInvocation := NewInvocation(pushEvent, actor, actor, pushTarget)

	ctx := newTestContext()

	s.mockClient.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)
	s.mockClient.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      true,
			Closed:      true,
			Mergeable:   githubv4.MergeableStateMergeable,
			MergeCommit: "test",
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				"parent-sha",
			},
		}, nil)
	s.mockClient.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	noInvokerCalls := 0 // shouldn't have invoked the build, since the commit has a skip-ci

	s.mockWorkflowInvoker.On("Start", mock.Anything, mock.Anything, mock.Anything).Return(nil)
	isFinalAttempt := true
	err := s.invoker.Start(ctx, observability.NewNullObservability(), pushInvocation, isFinalAttempt, customerlabels.NewNoopCustomerLabeler())
	s.mockWorkflowInvoker.AssertNumberOfCalls(s.T(), "Start", noInvokerCalls)
	s.Require().NoError(err)
}

func (s *InvokerTestSuite) TestInvokerPullRequestEventCommitWithSkipCINotInvoked() {
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")

	ghe := &gogithub.PullRequestEvent{}

	webhookDeliveryID := uuid.New().String()
	pullRequestEvent := NewEvent(
		&webhookDeliveryID,
		types.DefaultBranch,
		commitSha,
		types.CommitMessageZeroValue, // we'll expect a call to `github.GetCommitMessage`
		"pull_request",
		"",
		nil,
		time.Time{},
		eventOriginTime,
		ghe,
	)
	pullRequestTarget := NewTarget(
		repoID,
		repoDatabaseID,
		WorkflowSelector{
			EventName: "pull_request",
		},
		nextOwnerID,
		ownerDatabaseID,
		defaultGitHubTenant,
	)
	pullRequestInvocation := NewInvocation(pullRequestEvent, actor, actor, pullRequestTarget)

	ctx := newTestContext()

	s.mockClient.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{
			FeatureFlags: types.InvokerFeatureFlags{},
		}, nil)
	s.mockClient.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      true,
			Closed:      true,
			Mergeable:   githubv4.MergeableStateMergeable,
			MergeCommit: "test",
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				"parent-sha",
			},
		}, nil)
	s.mockClient.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.mockTwirpClient.On("GetCommitMessage", mock.Anything, mustIntID(repoID), commitSha).Return(
		// return a commit message with `[skip ci]`
		types.CommitMessage("please [skip ci] on this one"),
		nil,
	)

	noInvokerCalls := 0 // shouldn't have invoked the build, since the commit has a skip-ci

	s.mockWorkflowInvoker.On("Start", mock.Anything, mock.Anything, mock.Anything).Return(nil)
	isFinalAttempt := true
	err := s.invoker.Start(ctx, observability.NewNullObservability(), pullRequestInvocation, isFinalAttempt, customerlabels.NewNoopCustomerLabeler())
	s.mockWorkflowInvoker.AssertNumberOfCalls(s.T(), "Start", noInvokerCalls)
	s.Require().NoError(err)
}

func (s *InvokerTestSuite) TestInvokerPullRequestTargetSkipCINotApplied() {
	sha := "c8cfbd75232e224c14ca613ff7d48c3499a1b1be"
	commitSha := types.CommitSha(sha)
	latestBaseSha := commitSha
	topicRefName := "refs/heads/topic-one"
	baseRefName := types.GitRef("refs/heads/master")
	baseBranch := "master"
	merged := true
	ghe := &gogithub.PullRequestEvent{
		PullRequest: &gogithub.PullRequest{
			Merged: &merged,
			Head: &gogithub.PullRequestBranch{
				Ref: &topicRefName,
				Repo: &gogithub.Repository{
					NodeID: &forkRepoNodeID,
				},
			},
			Base: &gogithub.PullRequestBranch{
				Ref: &baseBranch,
				SHA: &sha,
			},
		},
	}

	webhookDeliveryID := uuid.New().String()
	pullRequestEvent := NewEvent(
		&webhookDeliveryID,
		baseRefName,
		commitSha,
		types.CommitMessageZeroValue,
		"pull_request_target",
		"",
		nil,
		time.Time{},
		eventOriginTime,
		ghe,
	)
	pullRequestTarget := NewTarget(
		repoID,
		repoDatabaseID,
		WorkflowSelector{
			EventName: "pull_request_target",
		},
		nextOwnerID,
		ownerDatabaseID,
		defaultGitHubTenant,
	)
	pullRequestInvocation := NewInvocation(pullRequestEvent, actor, actor, pullRequestTarget)

	ctx := newTestContext()

	s.mockClient.On("ResolveRef", mock.Anything, repoID, types.GitRef(baseBranch)).Return(latestBaseSha, types.NewBranchRef(baseBranch), nil)
	s.mockClient.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{
			FeatureFlags: types.InvokerFeatureFlags{},
		}, nil)
	s.mockClient.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.mockWorkflowInvoker.On("Start", mock.Anything, mock.Anything, mock.Anything).Return(nil)
	isFinalAttempt := true
	err := s.invoker.Start(ctx, observability.NewNullObservability(), pullRequestInvocation, isFinalAttempt, customerlabels.NewNoopCustomerLabeler())
	s.mockWorkflowInvoker.AssertNumberOfCalls(s.T(), "Start", 1)
	s.Require().NoError(err)
}

func (s *InvokerTestSuite) TestExtractPRDataReturnsHeadRepositoryInformationFromPullRequestEvent() {
	ctx := newTestContext()
	webhookDeliveryID := uuid.New().String()
	var pullRequestEvent = NewEvent(
		&webhookDeliveryID,
		types.DefaultBranch,
		commitSha,
		"",
		"pull_request",
		"",
		nil,
		time.Time{},
		eventOriginTime,
		stubPullRequestEvent,
	)
	var pullRequestTarget = NewTarget(
		repoID,
		repoDatabaseID,
		WorkflowSelector{
			EventName: "pull_request",
		},
		nextOwnerID,
		ownerDatabaseID,
		defaultGitHubTenant,
	)
	env := build.RunEnvironment{}

	env, headRepositoryID := extractPRData(ctx, env, &pullRequestEvent, &pullRequestTarget)
	s.Equal(types.GlobalID(forkRepoNodeID), headRepositoryID)
	s.Equal(types.GitRef("main"), env.BaseRef)
	s.Equal(types.GitRef("changes"), env.HeadRef)

	s.True(env.ForkedPullRequest)
	headRepositoryName := types.RepositoryFullName{
		Owner: forkRepoOwner,
		Name:  forkRepoName,
	}
	s.Equal(headRepositoryName, env.HeadRepository)
	s.Equal(types.GlobalID(forkRepoNodeID), env.HeadRepositoryID)
	s.Equal(types.GlobalID(forkRepoOwnerNodeID), env.HeadRepositoryOwnerID)
}

func (s *InvokerTestSuite) TestExtractPRDataReturnsHeadRepositoryIDFromNonPullRequestEvent() {
	ctx := newTestContext()
	env := build.RunEnvironment{
		BaseRef: "master",
		HeadRef: "master",
	}

	env, headRepositoryID := extractPRData(ctx, env, &pushEvent, &pushTarget)
	s.Equal(repoID, headRepositoryID)
	s.Equal(types.GitRef("master"), env.BaseRef)
	s.Equal(types.GitRef("master"), env.HeadRef)
	s.False(env.ForkedPullRequest)
}

func newTestContext() context.Context {
	return context.WithValue(context.Background(), reqmeta.RMDContextKey, reqmeta.NewRequestMetadata())
}

func (s *InvokerTestSuite) Test_resolveCommitAndRef() {
	ctx := context.Background()

	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	masterRef := types.NewBranchRef("master")
	unresolvedMaster := types.GitRef("master")
	tagRef := types.NewTagRef("v1.0.0")

	defaultBranchMock := func(c *github.MockClient) {
		c.On("ResolveDefaultBranch", ctx, repoID).Return(commitSha, masterRef, nil)
	}

	resolveRefMock := func(c *github.MockClient) {
		c.On("ResolveRef", ctx, repoID, unresolvedMaster).Return(commitSha, masterRef, nil)
	}

	resolveCommitRefMock := func(c *github.MockClient) {
		c.On("ResolveRef", ctx, repoID, masterRef).Return(commitSha, masterRef, nil)
	}

	resolveTagRefMock := func(c *github.MockClient) {
		c.On("ResolveRef", ctx, repoID, tagRef).Return(commitSha, tagRef, nil)
	}

	nothingMocked := func(c *github.MockClient) {}

	cases := []struct {
		commit types.CommitSha
		ref    types.GitRef

		expectedCommit types.CommitSha
		expectedRef    types.GitRef

		clientMock func(*github.MockClient)
	}{
		{commitSha, tagRef, commitSha, tagRef, nothingMocked},
		{commitSha, masterRef, commitSha, masterRef, nothingMocked},
		{commitSha, types.GitRefZeroValue, commitSha, types.GitRefZeroValue, nothingMocked},
		{types.CommitShaZeroValue, types.DefaultBranch, commitSha, masterRef, defaultBranchMock},
		{types.CommitShaZeroValue, masterRef, commitSha, masterRef, resolveCommitRefMock},
		{types.CommitShaZeroValue, unresolvedMaster, commitSha, masterRef, resolveRefMock},
		{types.CommitShaZeroValue, tagRef, commitSha, tagRef, resolveTagRefMock},
	}

	for _, tc := range cases {
		client := new(github.MockClient)
		tc.clientMock(client)

		invocation := Invocation{
			Target: invocationTarget{
				RepositoryID: repoID,
			},
			Event: InvokingEvent{
				Commit: tc.commit,
				Ref:    tc.ref,
			},
		}
		c, r, err := s.invoker.resolveCommitAndRef(ctx, NewNullObservability(), client, invocation)

		s.Require().NoError(err)
		s.Require().Equal(tc.expectedCommit, c)
		s.Require().Equal(tc.expectedRef, r)
		mock.AssertExpectationsForObjects(s.T(), client)
	}
}

func (s *InvokerTestSuite) Test_resolveCommitAndRef_AllNils() {
	ctx := context.Background()
	invocation := Invocation{
		Target: invocationTarget{RepositoryID: repoID},
	}
	_, _, err := s.invoker.resolveCommitAndRef(ctx, NewNullObservability(), nil, invocation)
	s.Assert().Error(err)
}

func (s *InvokerTestSuite) Test_resolveCommitAndRef_RerunInvalidRefs() {
	ctx := context.Background()
	client := &github.MockClient{}

	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	topicRefName := "main"

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: commitSha,
			Ref:    types.GitRef(topicRefName),
			Name:   "release",
		},
		ExistingCheckSuite: &types.CheckSuiteState{},
	}
	client.On("ResolveRef", ctx, repoID, types.GitRef(topicRefName)).Return(
		types.CommitShaZeroValue,
		types.GitRefZeroValue,
		errors.New("ref not found"))

	c, r, err := s.invoker.resolveCommitAndRef(ctx, NewNullObservability(), client, invocation)
	s.Assert().NoError(err)
	s.Require().Equal(commitSha, c)
	s.Require().Equal(types.GitRefZeroValue, r)
	mock.AssertExpectationsForObjects(s.T(), client)
}

func (s *InvokerTestSuite) Test_resolveCommitAndRef_DynamicEvent() {
	ctx := context.Background()

	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	featureRef := types.NewBranchRef("feature")
	pullHeadRef := types.GitRef("refs/pull/1/head")

	resolveEmptyRefMock := func(c *github.MockClient) {
		c.On("ResolveRef", ctx, repoID, mock.Anything).Return(commitSha, types.GitRefZeroValue, nil)
	}

	nothingMocked := func(c *github.MockClient) {}

	cases := []struct {
		name string

		commit types.CommitSha
		ref    types.GitRef

		expectedCommit types.CommitSha
		expectedRef    types.GitRef

		eventName string

		clientMock func(*github.MockClient)
	}{
		{
			name:           "Dynamic event, pull head ref",
			commit:         commitSha,
			ref:            pullHeadRef,
			expectedCommit: commitSha,
			expectedRef:    pullHeadRef,
			clientMock:     nothingMocked,
			eventName:      flowevents.Dynamic,
		},
		{
			name:           "Dynamic event, head ref (branch)",
			commit:         commitSha,
			ref:            featureRef,
			expectedCommit: commitSha,
			expectedRef:    featureRef,
			clientMock:     nothingMocked,
			eventName:      flowevents.Dynamic,
		},
		{
			name:           "Other event, pull head ref",
			commit:         commitSha,
			ref:            pullHeadRef,
			expectedCommit: commitSha,
			expectedRef:    types.GitRefZeroValue,
			clientMock:     resolveEmptyRefMock,
			eventName:      flowevents.PullRequest,
		},
	}

	for _, tc := range cases {
		client := new(github.MockClient)
		tc.clientMock(client)

		invocation := Invocation{
			Target: invocationTarget{
				RepositoryID: repoID,
			},
			Event: InvokingEvent{
				Commit: tc.commit,
				Ref:    tc.ref,
				Name:   tc.eventName,
			},
		}
		c, r, err := s.invoker.resolveCommitAndRef(ctx, NewNullObservability(), client, invocation)

		s.Require().NoError(err)
		s.Require().Equal(tc.expectedCommit, c)
		s.Require().Equal(tc.expectedRef, r)
		mock.AssertExpectationsForObjects(s.T(), client)
	}
}

func (s *InvokerTestSuite) Test_resolveCheckoutCommitAndRef() {
	ctx := context.Background()

	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	mainRef := types.NewBranchRef("main")

	mergeCommitShaString := "98296e6f91253a31164f1d440d5364e14a1cd1ac"
	baseRefShaString := "2444871a92a74514f80832d27b1b6b61304478af"
	mergeCommitSha := types.CommitSha(mergeCommitShaString)
	baseRefSha := types.CommitSha(baseRefShaString)

	topicRefName := "refs/heads/topic-one"
	baseRefName := "refs/heads/base-one"
	pullRefString := "refs/pull/24"

	baseRefShaShortString := "2444871"
	shortRefString := "244"
	gitDescribeString := "branch-123-g12345abc"

	mergeable := true
	prNum := 24
	var pr = &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseRefName,
			SHA: &baseRefShaString,
		},
		Mergeable:      &mergeable,
		MergeCommitSHA: &mergeCommitShaString,
		Number:         &prNum,
	}
	prFlowEvent := &gogithub.PullRequestEvent{PullRequest: pr}
	prRef := types.GitRef(fmt.Sprintf("refs/pull/%d/merge", prNum))

	// Invalid as PR Base Ref is a SHA
	var shaPr = &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseRefShaString,
			SHA: &baseRefShaString,
		},
		Mergeable:      &mergeable,
		MergeCommitSHA: &mergeCommitShaString,
		Number:         &prNum,
	}

	// Invalid as PR Base Ref is a short SHA
	var shortShaPr = &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseRefShaShortString,
			SHA: &baseRefShaString,
		},
		Mergeable:      &mergeable,
		MergeCommitSHA: &mergeCommitShaString,
		Number:         &prNum,
	}

	var pullRefPr = &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &pullRefString,
			SHA: &baseRefShaString,
		},
		Mergeable:      &mergeable,
		MergeCommitSHA: &mergeCommitShaString,
		Number:         &prNum,
	}

	var shortRefPr = &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &shortRefString,
			SHA: &baseRefShaString,
		},
		Mergeable:      &mergeable,
		MergeCommitSHA: &mergeCommitShaString,
		Number:         &prNum,
	}

	var gitDescribePr = &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &gitDescribeString,
			SHA: &baseRefShaString,
		},
		Mergeable:      &mergeable,
		MergeCommitSHA: &mergeCommitShaString,
		Number:         &prNum,
	}

	shaPrFlowEvent := &gogithub.PullRequestEvent{PullRequest: shaPr}
	shortShaPrFlowEvent := &gogithub.PullRequestEvent{PullRequest: shortShaPr}
	pullRefPrFlowEvent := &gogithub.PullRequestEvent{PullRequest: pullRefPr}
	shortRefPrFlowEvent := &gogithub.PullRequestEvent{PullRequest: shortRefPr}
	gitDescribePrFlowEvent := &gogithub.PullRequestEvent{PullRequest: gitDescribePr}

	client := &github.MockClient{}

	client.On("ResolveRef", mock.Anything, repoID, mock.Anything).Return(baseRefSha, types.NewBranchRef(baseRefName), nil)

	cases := []struct {
		eventName string
		event     flowevents.GitHubEvent

		eventCommitSha types.CommitSha
		eventCommitRef types.GitRef

		expectedCommitSha types.CommitSha
		expectedRef       types.GitRef
		expectedErr       error
	}{
		{flowevents.Push, nil, commitSha, mainRef, commitSha, mainRef, nil},                                                                                                 // Regular event returns event commit/ref
		{flowevents.PullRequest, prFlowEvent, commitSha, mainRef, mergeCommitSha, prRef, nil},                                                                               // Pull Request event returns merge commit sha and ref
		{flowevents.PullRequestTarget, prFlowEvent, commitSha, mainRef, baseRefSha, types.NewBranchRef(baseRefName), nil},                                                   // PR Target event returns base sha and ref
		{flowevents.PullRequest, shaPrFlowEvent, commitSha, mainRef, mergeCommitSha, prRef, nil},                                                                            // Pull Request events can use a SHA for base ref
		{flowevents.PullRequestTarget, shaPrFlowEvent, commitSha, mainRef, types.CommitShaZeroValue, types.GitRefZeroValue, secureref.ErrInvalidBaseRefSha},                 // PR Target events can't use a SHA as the base ref
		{flowevents.PullRequestTarget, shortShaPrFlowEvent, commitSha, mainRef, types.CommitShaZeroValue, types.GitRefZeroValue, secureref.ErrInvalidBaseRefSha},            // PR Target events can't use a short SHA as the base ref
		{flowevents.PullRequestTarget, shortRefPrFlowEvent, commitSha, mainRef, baseRefSha, types.NewBranchRef(baseRefName), nil},                                           // PR Target event with a ref that isn't long enough to be a short SHA
		{flowevents.PullRequestTarget, pullRefPrFlowEvent, commitSha, mainRef, types.CommitShaZeroValue, types.GitRefZeroValue, secureref.ErrInvalidBaseRefPR},              // PR Target events can't use a pull request ref as the base ref
		{flowevents.PullRequestTarget, gitDescribePrFlowEvent, commitSha, mainRef, types.CommitShaZeroValue, types.GitRefZeroValue, secureref.ErrInvalidBaseRefGitDescribe}, // PR Target events can't use a ref that has a git describe suffix
	}

	for _, tc := range cases {
		invocation := Invocation{
			Target: invocationTarget{
				RepositoryID: repoID,
			},
			Event: InvokingEvent{
				Commit: tc.eventCommitSha,
				Ref:    tc.eventCommitRef,
				Name:   tc.eventName,
				Ghe:    tc.event,
			},
		}

		c, r, err := s.invoker.resolveCheckoutCommitAndRef(ctx, NewNullObservability(), client, invocation, tc.eventCommitSha, tc.eventCommitRef)

		if tc.expectedErr == nil {
			s.Require().NoError(err)
		} else {
			s.Require().Equal(tc.expectedErr, err)
		}

		s.Require().Equal(tc.expectedCommitSha, c)
		s.Require().Equal(tc.expectedRef, r)
	}
}

func (s *InvokerTestSuite) Test_FullyQualifiedBaseRefFeatureFlagOn() {
	ctx := context.Background()

	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	mainRef := types.NewBranchRef("main")

	mergeCommitShaString := "98296e6f91253a31164f1d440d5364e14a1cd1ac"
	baseRefShaString := "2444871a92a74514f80832d27b1b6b61304478af"
	baseRefSha := types.CommitSha(baseRefShaString)

	baseRefName := "refs/heads/base-one"
	shortBaseRefName := "base-one"

	client := &github.MockClient{}

	mergeable := true
	prNum := 24
	var pr = &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseRefName,
			SHA: &baseRefShaString,
		},
		Mergeable:      &mergeable,
		MergeCommitSHA: &mergeCommitShaString,
		Number:         &prNum,
	}
	prFlowEvent := &gogithub.PullRequestEvent{PullRequest: pr}

	client.On("ResolveRef", mock.Anything, repoID, types.NewBranchRef(shortBaseRefName)).Return(baseRefSha, types.NewBranchRef(shortBaseRefName), nil)
	client.On("ResolveRef", mock.Anything, repoID, types.GitRef(shortBaseRefName)).Return(baseRefSha, types.NewBranchRef(shortBaseRefName), nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: commitSha,
			Ref:    mainRef,
			Name:   flowevents.PullRequestTarget,
			Ghe:    prFlowEvent,
		},
	}

	commitShaRes, refRes, err := s.invoker.resolveCheckoutCommitAndRef(ctx, NewNullObservability(), client, invocation, commitSha, mainRef)

	s.Require().NoError(err)
	s.Require().Equal(baseRefSha, commitShaRes)
	s.Require().Equal(types.NewBranchRef(shortBaseRefName), refRes)
}

func (s *InvokerTestSuite) Test_GetInvocationData_LooksUpWorkflowFilesUsingMergeCommitForPRRelatedEventsForUnmergedPR() {
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	mergeCommitSha := types.CommitSha("merge-commit-sha")
	topicRefName := "refs/heads/topic-one"
	baseRefName := "refs/heads/base-one"

	var pr = &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseRefName,
		},
	}

	events := []flowevents.HasPullRequest{
		&gogithub.PullRequestEvent{PullRequest: pr},
		&gogithub.PullRequestReviewEvent{PullRequest: pr},
		&gogithub.PullRequestReviewCommentEvent{PullRequest: pr},
	}

	client := &github.MockClient{}
	client.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      false,
			Closed:      false,
			Mergeable:   githubv4.MergeableStateMergeable,
			MergeCommit: mergeCommitSha,
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				commitSha,
			},
		}, nil)

	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mergeCommitSha, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)

	mergeRef := fmt.Sprintf("refs/pull/%d/merge", pr.GetNumber())

	client.On("IsRefProtected", mock.Anything, mock.Anything, types.GitRef(mergeRef)).
		Return(false, nil)
	for _, e := range events {
		invocation := Invocation{
			Target: invocationTarget{
				RepositoryID: repoID,
			},
			Event: InvokingEvent{
				Commit: commitSha,
				Ref:    types.GitRef(topicRefName),
				Ghe:    e,
			},
			ExecutingActor: InvokingActor{
				ID: actorID,
			},
			TriggeringActor: InvokingActor{
				ID: actorID,
			},
		}
		data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
		s.Require().NoError(err)
		s.Require().Equal(data.References.CheckoutCommit, types.NewWorkflowInvocationReference(mergeCommitSha, types.GitRef(mergeRef)))
	}
}

func (s *InvokerTestSuite) Test_GetInvocationData_LooksUpWorkflowFilesUsingMergeCommitForPRRelatedEventsForMergedPR() {
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	mergeCommitSha := types.CommitSha("merge-commit-sha")
	topicRefName := "refs/heads/topic-one"
	baseRefName := "refs/heads/base-one"
	baseBranchName := "base-one"

	merged := true
	var pr = &gogithub.PullRequest{
		Merged: &merged,
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseBranchName,
		},
	}

	events := []flowevents.HasPullRequest{
		&gogithub.PullRequestEvent{PullRequest: pr},
		&gogithub.PullRequestReviewEvent{PullRequest: pr},
		&gogithub.PullRequestReviewCommentEvent{PullRequest: pr},
	}

	client := &github.MockClient{}
	client.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      true,
			Closed:      true,
			Mergeable:   githubv4.MergeableStateUnknown,
			MergeCommit: mergeCommitSha,
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				commitSha,
			},
		}, nil)

	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mergeCommitSha, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)

	client.On("IsRefProtected", mock.Anything, mock.Anything, types.GitRef(baseRefName)).
		Return(false, nil)

	for _, e := range events {
		invocation := Invocation{
			Target: invocationTarget{
				RepositoryID: repoID,
			},
			Event: InvokingEvent{
				Commit: commitSha,
				Ref:    types.GitRef(topicRefName),
				Ghe:    e,
			},
			ExecutingActor: InvokingActor{
				ID: actorID,
			},
			TriggeringActor: InvokingActor{
				ID: actorID,
			},
		}
		data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
		s.Require().NoError(err)
		s.Require().Equal(data.References.CheckoutCommit, types.NewWorkflowInvocationReference(mergeCommitSha, types.GitRef(baseRefName)))
	}
}

func (s *InvokerTestSuite) Test_GetInvocationData_LooksUpWorkflowFilesUsingEventCommitForNonPRs() {
	expectedCommitSHA := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	baseRef := types.GitRef("refs/heads/topic")

	client := &github.MockClient{}
	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, expectedCommitSHA, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)
	client.On("IsRefProtected", mock.Anything, mock.Anything, baseRef).
		Return(false, nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: expectedCommitSHA,
			Ref:    baseRef,
			Ghe:    stubCheckSuiteEvent,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(data.References.CheckoutCommit, types.NewWorkflowInvocationReference(expectedCommitSHA, baseRef))
	// GetMergeStatusForPullRequest should only be called for PR related events.
	client.AssertNumberOfCalls(s.T(), "GetMergeStatusForPullRequest", 0)
}

func (s *InvokerTestSuite) Test_GetInvocationData_LooksUpWorkflowFilesUsingCheckoutCommitForRerun() {
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	previousRunSha := types.CommitSha("previous-run-commit-sha")
	previousRunRef := "refs/pulls/merge/123"
	topicRefName := "refs/heads/topic-one"

	client := &github.MockClient{}
	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, previousRunSha, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)
	client.On("IsRefProtected", mock.Anything, mock.Anything, types.GitRef(previousRunRef)).
		Return(false, nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: commitSha,
			Ref:    types.GitRef(topicRefName),
			Ghe:    &pushEvent,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
		ExistingCheckSuite: &types.CheckSuiteState{
			CheckoutSHA: previousRunSha,
			CheckoutRef: types.GitRef(previousRunRef),
		},
	}
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(types.NewWorkflowInvocationReference(previousRunSha, types.GitRef(previousRunRef)), data.References.CheckoutCommit)
}

func (s *InvokerTestSuite) Test_GetInvocationData_LooksUpWorkflowFilesUsingCheckoutCommitForRerunPRs() {
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	mergeCommitSha := types.CommitSha("merge-commit-sha")
	topicRefName := "refs/heads/topic-one"
	baseRefName := "refs/heads/base-one"

	merged := true
	var pr = &gogithub.PullRequest{
		Merged: &merged,
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseRefName,
		},
	}

	client := &github.MockClient{}
	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mergeCommitSha, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)
	client.On("IsRefProtected", mock.Anything, mock.Anything, types.GitRef(topicRefName)).
		Return(false, nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: commitSha,
			Ref:    types.GitRef(topicRefName),
			Ghe:    &gogithub.PullRequestEvent{PullRequest: pr},
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
		ExistingCheckSuite: &types.CheckSuiteState{
			CheckoutSHA: mergeCommitSha,
			CheckoutRef: types.GitRef(topicRefName),
		},
	}
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(types.NewWorkflowInvocationReference(mergeCommitSha, types.GitRef(topicRefName)), data.References.CheckoutCommit)
}

func (s *InvokerTestSuite) Test_GetInvocationData_LooksUpWorkflowFilesUsingBaseBranchCommitForPRsOnPullRequestTargetEvent() {
	sha := "c8cfbd75232e224c14ca613ff7d48c3499a1b1be"
	baseSha := types.CommitSha(sha)
	latestBaseSha := commitSha
	topicRefName := "refs/heads/topic-one"
	baseRefName := "refs/heads/master"
	baseBranch := "master"
	merged := true
	var pr = &gogithub.PullRequest{
		Merged: &merged,
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseBranch,
			SHA: &sha,
		},
	}

	e := &gogithub.PullRequestEvent{PullRequest: pr}

	client := &github.MockClient{}
	client.On("ResolveRef", mock.Anything, repoID, types.GitRef(baseRefName)).Return(latestBaseSha, types.NewBranchRef(baseBranch), nil)
	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, latestBaseSha, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)
	client.On("IsRefProtected", mock.Anything, mock.Anything, types.GitRef(baseRefName)).
		Return(false, nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Name:   "pull_request_target",
			Commit: baseSha,
			Ref:    types.GitRef(baseRefName),
			Ghe:    e,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(data.References.CheckoutCommit, types.NewWorkflowInvocationReference(latestBaseSha, types.GitRef(baseRefName)))
	// We don't need the merge commit for the pull_request_target trigger.
	client.AssertNumberOfCalls(s.T(), "GetMergeStatusForPullRequest", 0)
}

func (s *InvokerTestSuite) Test_GetInvocationData_TimesoutIfPRMergeCommitHasWrongParent() {
	// the PR commit for the event we're processing.
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	// another commit pushed to the PR branch before or after the event commit above
	differentCommitSha := types.CommitSha("different-commit-sha")
	// the merge commit for that other commit
	mergeCommitSha := types.CommitSha("different-merge-commit-sha")
	topicRefName := "refs/heads/topic-one"
	baseRefName := "refs/heads/base-one"

	var pr = &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseRefName,
		},
	}

	event := &gogithub.PullRequestEvent{PullRequest: pr}

	client := &github.MockClient{}
	client.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      false,
			Closed:      false,
			Mergeable:   githubv4.MergeableStateMergeable,
			MergeCommit: mergeCommitSha,
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				differentCommitSha,
			},
			PRHeadCommit: commitSha,
		}, nil).Times(20) // Checking more than 20 times in one minute is excessive.

	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mergeCommitSha, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{}, nil)
	client.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).
		Return(false, nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: commitSha,
			Ref:    types.GitRef(topicRefName),
			Ghe:    event,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}

	_, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().Error(err)
	s.Require().Equal(ErrMergeableCommitTimeout, err)
}

func (s *InvokerTestSuite) Test_GetInvocationData_StopsPollingAndErrorsIfPREventCommitDoesntMatchHead() {
	// the PR commit for the event we're processing.
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	// another commit pushed to the PR branch after the event commit above
	headCommitSha := types.CommitSha("pr-branch-head-commit-sha")
	topicRefName := "refs/heads/topic-one"
	baseRefName := "refs/heads/base-one"

	cases := []struct {
		name               string
		mergeable          githubv4.MergeableState
		mergeCommit        types.CommitSha
		mergeCommitParents [2]types.CommitSha
	}{
		{
			name:      "No merge commit",
			mergeable: githubv4.MergeableStateUnknown,
		},
		{
			"Merge commit with wrong parents",
			githubv4.MergeableStateMergeable,
			types.CommitSha("different-merge-commit-sha"),
			[2]types.CommitSha{
				types.CommitSha("base-sha"),
				headCommitSha,
			},
		},
	}

	for _, tc := range cases {
		s.Run(tc.name, func() {
			var pr = &gogithub.PullRequest{
				Head: &gogithub.PullRequestBranch{
					Ref: &topicRefName,
					Repo: &gogithub.Repository{
						NodeID: &forkRepoNodeID,
					},
				},
				Base: &gogithub.PullRequestBranch{
					Ref: &baseRefName,
				},
			}

			event := &gogithub.PullRequestEvent{PullRequest: pr}

			client := &github.MockClient{}
			client.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
				Return(&github.PullRequestMergeState{
					Merged:             false,
					Closed:             false,
					Mergeable:          tc.mergeable,
					MergeCommit:        tc.mergeCommit,
					MergeCommitParents: tc.mergeCommitParents,
					PRHeadCommit:       headCommitSha,
				}, nil)
			client.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).
				Return(false, nil)

			invocation := Invocation{
				Target: invocationTarget{
					RepositoryID: repoID,
				},
				Event: InvokingEvent{
					Commit: commitSha,
					Ref:    types.GitRef(topicRefName),
					Ghe:    event,
				},
				ExecutingActor: InvokingActor{
					ID: actorID,
				},
				TriggeringActor: InvokingActor{
					ID: actorID,
				},
			}

			_, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
			s.Require().Error(err)
			s.Require().Equal(ErrOldPullRequestCommit, err)
			// Polling should cease after detecting the event commit is older and doesn't match the PR head branch ref.
			client.AssertNumberOfCalls(s.T(), "GetMergeStatusForPullRequest", 1)
		})
	}
}

func (s *InvokerTestSuite) Test_GetInvocationData_ClosedPRs() {
	// the PR commit for the event we're processing.
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	topicRefName := "refs/heads/topic-one"
	baseRefName := "refs/heads/base-one"

	type graphqlResponse struct {
		closed             bool
		merged             bool
		mergeable          githubv4.MergeableState
		mergeCommit        types.CommitSha
		mergeCommitParents [2]types.CommitSha
		prHeadCommit       types.CommitSha
		repeatResponse     bool
	}

	cases := []struct {
		name                string
		responses           []graphqlResponse
		expectedMergeCommit types.CommitSha
		expectedError       error
		expectedCallCount   int
	}{
		{
			name: "PR merged - two merge commit parents",
			responses: []graphqlResponse{
				{
					closed: true,
					merged: true,
					// For merged PRs, mergeable is typically `UNKNOWN` even though there's a merge commit.
					mergeable:   githubv4.MergeableStateUnknown,
					mergeCommit: types.CommitSha("merge-commit-sha"),
					mergeCommitParents: [2]types.CommitSha{
						types.CommitSha("base-sha"),
						commitSha,
					},
					prHeadCommit: commitSha,
				},
			},
			expectedMergeCommit: types.CommitSha("merge-commit-sha"),
		},
		{
			name: "PR merged - one merge commit parent",
			responses: []graphqlResponse{
				{
					closed:      true,
					merged:      true,
					mergeable:   githubv4.MergeableStateUnknown,
					mergeCommit: types.CommitSha("merge-commit-sha"),
					mergeCommitParents: [2]types.CommitSha{
						types.CommitSha("base-sha"),
						types.CommitShaZeroValue,
					},
					prHeadCommit: commitSha,
				},
			},
			expectedMergeCommit: types.CommitSha("merge-commit-sha"),
		},
		{
			name: "PR merged - different merge commit parent and head commit",
			responses: []graphqlResponse{
				{
					closed:      true,
					merged:      true,
					mergeable:   githubv4.MergeableStateUnknown,
					mergeCommit: types.CommitSha("merge-commit-sha"),
					mergeCommitParents: [2]types.CommitSha{
						types.CommitSha("base-sha"),
						types.CommitSha("different-commit-sha"),
					},
					prHeadCommit: types.CommitSha("different-commit-sha"),
				},
			},
			// At this time we don't check the merge commit parent(s) or head commit for merged PRs.
			expectedMergeCommit: types.CommitSha("merge-commit-sha"),
		},
		{
			name: "PR merged - pr head commit not found",
			responses: []graphqlResponse{
				{
					closed:      true,
					merged:      true,
					mergeable:   githubv4.MergeableStateUnknown,
					mergeCommit: types.CommitSha("merge-commit-sha"),
					mergeCommitParents: [2]types.CommitSha{
						types.CommitSha("base-sha"),
						types.CommitShaZeroValue,
					},
					prHeadCommit: types.CommitShaZeroValue,
				},
			},
			// It's fine that the head commit wasn't found. The PR branch may have been deleted, or Launch may not have access to a fork PR head repo.
			expectedMergeCommit: types.CommitSha("merge-commit-sha"),
		},
		{
			name: "PR merged, but mergeable state is CONFLICTING",
			responses: []graphqlResponse{
				{
					closed:      true,
					merged:      true,
					mergeable:   githubv4.MergeableStateConflicting,
					mergeCommit: types.CommitSha("merge-commit-sha"),
					mergeCommitParents: [2]types.CommitSha{
						types.CommitSha("base-sha"),
						types.CommitShaZeroValue,
					},
					prHeadCommit: types.CommitShaZeroValue,
				},
			},
			// If the PR is merged, it doesn't matter that there were previously conflicts that prevented merging it.
			// This is likely a replication lag issue we're working around; see https://github.com/github/coding/issues/2856#issuecomment-967380846.
			// When a PR is merged, mergeCommit is set to the actual merge commit, not a test merge commit.
			expectedMergeCommit: types.CommitSha("merge-commit-sha"),
		},
		{
			name: "PR merged, but initial graphql response doesn't reflect that",
			responses: []graphqlResponse{
				// We see this sometimes when we process a pull_request event_action=closed webhook.
				{
					closed:    false,
					merged:    false,
					mergeable: githubv4.MergeableStateUnknown,
					// The PR head branch has been deleted (or Launch doesn't have access to a fork PR head repo).
					prHeadCommit: types.CommitShaZeroValue,
				},
				{
					// No changes from previous response.
					closed:       false,
					merged:       false,
					mergeable:    githubv4.MergeableStateUnknown,
					prHeadCommit: types.CommitShaZeroValue,
				},
				{
					// Now the response reflects that the PR has been merged, and includes the merge commit.
					closed:      true,
					merged:      true,
					mergeable:   githubv4.MergeableStateUnknown,
					mergeCommit: types.CommitSha("merge-commit-sha"),
					mergeCommitParents: [2]types.CommitSha{
						types.CommitSha("base-sha"),
						types.CommitShaZeroValue,
					},
					prHeadCommit: types.CommitShaZeroValue,
				},
			},
			expectedMergeCommit: types.CommitSha("merge-commit-sha"),
		},
		{
			name: "PR merged, but initial graphql response says it's only closed",
			responses: []graphqlResponse{
				{
					// See https://github.com/github/coding/issues/2856
					closed:       true,
					merged:       false,
					mergeable:    githubv4.MergeableStateUnknown,
					prHeadCommit: types.CommitShaZeroValue,
				},
				{
					// Now the response reflects that the PR has been merged, and includes the merge commit.
					closed:      true,
					merged:      true,
					mergeable:   githubv4.MergeableStateUnknown,
					mergeCommit: types.CommitSha("merge-commit-sha"),
					mergeCommitParents: [2]types.CommitSha{
						types.CommitSha("base-sha"),
						types.CommitShaZeroValue,
					},
					prHeadCommit: types.CommitShaZeroValue,
				},
			},
			expectedMergeCommit: types.CommitSha("merge-commit-sha"),
		},
		{
			name: "PR merged, but has no merge commit",
			responses: []graphqlResponse{
				{
					// Splunk shows we get this occasionally. index=prod-launch pr_merged=true pr_merge_commit=NULL
					closed:         true,
					merged:         true,
					mergeable:      githubv4.MergeableStateUnknown,
					prHeadCommit:   types.CommitShaZeroValue,
					repeatResponse: true,
				},
			},
			expectedError: ErrMergeableCommitTimeout,
		},
		{
			name: "PR closed without merging - test merge commit available",
			responses: []graphqlResponse{
				{
					closed:      true,
					merged:      false,
					mergeable:   githubv4.MergeableStateMergeable,
					mergeCommit: types.CommitSha("merge-commit-sha"),
					mergeCommitParents: [2]types.CommitSha{
						types.CommitSha("base-sha"),
						commitSha,
					},
					prHeadCommit: commitSha,
				},
			},
			expectedMergeCommit: types.CommitSha("merge-commit-sha"),
		},
		{
			name: "PR closed without merging - test merge commit has wrong parent",
			responses: []graphqlResponse{
				{
					closed:      true,
					merged:      false,
					mergeable:   githubv4.MergeableStateMergeable,
					mergeCommit: types.CommitSha("merge-commit-sha"),
					mergeCommitParents: [2]types.CommitSha{
						types.CommitSha("base-sha"),
						types.CommitSha("different-commit-sha"),
					},
					prHeadCommit:   commitSha,
					repeatResponse: true,
				},
			},
			expectedError: ErrPullRequestClosedWithoutMerging,
		},
		{
			name: "PR closed without merging - no test merge commit",
			responses: []graphqlResponse{
				{
					closed:         true,
					merged:         false,
					mergeable:      githubv4.MergeableStateUnknown,
					prHeadCommit:   commitSha,
					repeatResponse: true,
				},
			},
			expectedError: ErrPullRequestClosedWithoutMerging,
		},
		{
			name: "PR closed without merging - no test merge commit, head commit not found",
			responses: []graphqlResponse{
				{
					closed:         true,
					merged:         false,
					mergeable:      githubv4.MergeableStateUnknown,
					prHeadCommit:   types.CommitShaZeroValue,
					repeatResponse: true,
				},
			},
			expectedError: ErrPullRequestClosedWithoutMerging,
		},
		{
			name: "PR reopened, but initial graphql response says it's closed",
			responses: []graphqlResponse{
				{
					// We see this sometimes when process pull_request:reopened webhooks.
					closed:       true,
					merged:       false,
					mergeable:    githubv4.MergeableStateUnknown,
					prHeadCommit: types.CommitShaZeroValue,
				},
				{
					// Now the response reflects that the PR has been reopened.
					closed:       false,
					merged:       false,
					mergeable:    githubv4.MergeableStateUnknown,
					prHeadCommit: types.CommitShaZeroValue,
				},
				{
					// And now the test merge commit is available
					closed:      false,
					merged:      false,
					mergeable:   githubv4.MergeableStateMergeable,
					mergeCommit: types.CommitSha("merge-commit-sha"),
					mergeCommitParents: [2]types.CommitSha{
						types.CommitSha("base-sha"),
						commitSha,
					},
					prHeadCommit: types.CommitShaZeroValue,
				},
			},
			expectedMergeCommit: types.CommitSha("merge-commit-sha"),
		},
	}

	for _, tc := range cases {
		s.Run(tc.name, func() {
			var pr = &gogithub.PullRequest{
				Head: &gogithub.PullRequestBranch{
					Ref: &topicRefName,
					Repo: &gogithub.Repository{
						NodeID: &forkRepoNodeID,
					},
				},
				Base: &gogithub.PullRequestBranch{
					Ref: &baseRefName,
				},
			}

			event := &gogithub.PullRequestEvent{PullRequest: pr}
			client := &github.MockClient{}

			mockRepeated := false
			for _, tcr := range tc.responses {
				mockCall := client.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(&github.PullRequestMergeState{
						Closed:             tcr.closed,
						Merged:             tcr.merged,
						Mergeable:          tcr.mergeable,
						MergeCommit:        tcr.mergeCommit,
						MergeCommitParents: tcr.mergeCommitParents,
						PRHeadCommit:       tcr.prHeadCommit,
					}, nil)

				if tcr.repeatResponse {
					mockRepeated = true
				} else {
					mockCall.Once()
				}
			}

			client.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).
				Return(false, nil)

			if tc.expectedError == nil {
				client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
					Return(&types.WorkflowInvocationData{}, nil)
			}

			invocation := Invocation{
				Target: invocationTarget{
					RepositoryID: repoID,
				},
				Event: InvokingEvent{
					Commit: commitSha,
					Ref:    types.GitRef(topicRefName),
					Ghe:    event,
				},
				ExecutingActor: InvokingActor{
					ID: actorID,
				},
				TriggeringActor: InvokingActor{
					ID: actorID,
				},
			}

			d, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
			if tc.expectedError != nil {
				s.Require().Error(err)
				s.Require().Equal(tc.expectedError, err)
			} else {
				s.Require().NoError(err)
				s.Require().Equal(tc.expectedMergeCommit, d.References.CheckoutCommit.CommitSHA)
			}

			if !mockRepeated {
				client.AssertNumberOfCalls(s.T(), "GetMergeStatusForPullRequest", len(tc.responses))
			}
		})
	}
}

func (s *InvokerTestSuite) Test_GetInvocationData_StopsPollingAndErrorsIfOpenPRHasMergeConflicts() {
	// the PR commit for the event we're processing.
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	topicRefName := "refs/heads/topic-one"
	baseRefName := "refs/heads/base-one"

	var pr = &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseRefName,
		},
	}

	event := &gogithub.PullRequestEvent{PullRequest: pr}

	client := &github.MockClient{}
	client.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:       false,
			Closed:       false,
			Mergeable:    githubv4.MergeableStateConflicting,
			PRHeadCommit: commitSha,
		}, nil)
	client.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).
		Return(false, nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: commitSha,
			Ref:    types.GitRef(topicRefName),
			Ghe:    event,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}

	_, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().Error(err)
	s.Require().Equal(ErrMergeConflicts, err)

	// Once we detect the PR has merge conflicts, we should stop polling
	client.AssertNumberOfCalls(s.T(), "GetMergeStatusForPullRequest", 1)
}

func (s *InvokerTestSuite) Test_GetInvocationData_QueryRefProtected() {
	expectedCommitSHA := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	baseRef := types.GitRef("refs/heads/topic")

	client := &github.MockClient{}
	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, expectedCommitSHA, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{
			WorkflowFeatureFlags: types.WorkflowFeatureFlags{}}, nil)

	client.On("IsRefProtected", mock.Anything, mock.Anything, baseRef).
		Return(true, nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: expectedCommitSHA,
			Ref:    baseRef,
			Ghe:    stubCheckSuiteEvent,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(data.References.CheckoutCommit, types.NewWorkflowInvocationReference(expectedCommitSHA, baseRef))
	s.Require().Equal(data.References.CheckoutRefProtected, true)
	// GetMergeStatusForPullRequest should only be called for PR related events.
	client.AssertNumberOfCalls(s.T(), "GetMergeStatusForPullRequest", 0)

	client.AssertNumberOfCalls(s.T(), "IsRefProtected", 1)
}

func (s *InvokerTestSuite) Test_GetInvocationData_NotQueryRefProtectedEventRefIsEmtpy() {
	expectedCommitSHA := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")

	client := &github.MockClient{}
	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, expectedCommitSHA, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{
			WorkflowFeatureFlags: types.WorkflowFeatureFlags{}}, nil)

	client.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).
		Return(true, nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: expectedCommitSHA,
			Ref:    types.GitRefZeroValue,
			Ghe:    stubCheckSuiteEvent,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(data.References.CheckoutCommit, types.NewWorkflowInvocationReference(expectedCommitSHA, types.GitRefZeroValue))
	s.Require().Equal(data.References.CheckoutRefProtected, false)
	// GetMergeStatusForPullRequest should only be called for PR related events.
	client.AssertNumberOfCalls(s.T(), "GetMergeStatusForPullRequest", 0)

	client.AssertNumberOfCalls(s.T(), "IsRefProtected", 0)
}

func (s *InvokerTestSuite) Test_GetInvocationData_NotQueryRefProtectedEventRefIsTag() {
	expectedCommitSHA := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	tagRef := types.GitRef("refs/tags/v1")

	client := &github.MockClient{}
	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, expectedCommitSHA, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{
			WorkflowFeatureFlags: types.WorkflowFeatureFlags{}}, nil)

	client.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).
		Return(true, nil)

	client.On("ResolveRef", mock.Anything, repoID, tagRef).Return(expectedCommitSHA, tagRef, nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: expectedCommitSHA,
			Ref:    tagRef,
			Ghe:    stubCheckSuiteEvent,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(data.References.CheckoutCommit, types.NewWorkflowInvocationReference(expectedCommitSHA, tagRef))
	s.Require().Equal(data.References.CheckoutRefProtected, false)
	// GetMergeStatusForPullRequest should only be called for PR related events.
	client.AssertNumberOfCalls(s.T(), "GetMergeStatusForPullRequest", 0)

	client.AssertNumberOfCalls(s.T(), "IsRefProtected", 0)
}

func (s *InvokerTestSuite) Test_GetInvocationData_QueryRefProtectedErrors() {
	expectedCommitSHA := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	baseRef := types.GitRef("refs/heads/topic")

	client := &github.MockClient{}
	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, expectedCommitSHA, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{
			WorkflowFeatureFlags: types.WorkflowFeatureFlags{}}, nil)

	client.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).
		Return(false, errors.New("failed"))

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: expectedCommitSHA,
			Ref:    baseRef,
			Ghe:    stubCheckSuiteEvent,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(data.References.CheckoutCommit, types.NewWorkflowInvocationReference(expectedCommitSHA, baseRef))
	s.Require().Equal(data.References.CheckoutRefProtected, false)
	// GetMergeStatusForPullRequest should only be called for PR related events.
	client.AssertNumberOfCalls(s.T(), "GetMergeStatusForPullRequest", 0)

	client.AssertNumberOfCalls(s.T(), "IsRefProtected", 1)
}

func (s *InvokerTestSuite) Test_GetInvocationData_QueryRefProtectedForRerun() {
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	previousRunSha := types.CommitSha("previous-run-commit-sha")
	previousRunRef := "refs/heads/topic-one"
	topicRefName := "refs/heads/topic-one"

	client := &github.MockClient{}
	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, previousRunSha, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{
			WorkflowFeatureFlags: types.WorkflowFeatureFlags{}}, nil)

	client.On("IsRefProtected", mock.Anything, mock.Anything, types.GitRef(previousRunRef)).
		Return(true, nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: commitSha,
			Ref:    types.GitRef(topicRefName),
			Ghe:    &pushEvent,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
		ExistingCheckSuite: &types.CheckSuiteState{
			CheckoutSHA: previousRunSha,
			CheckoutRef: types.GitRef(previousRunRef),
		},
	}
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(types.NewWorkflowInvocationReference(previousRunSha, types.GitRef(previousRunRef)), data.References.CheckoutCommit)
	s.Require().Equal(data.References.CheckoutRefProtected, true)

	client.AssertNumberOfCalls(s.T(), "IsRefProtected", 1)
}

func (s *InvokerTestSuite) Test_GetInvocationData_QueryRefProtectedForPullRequestTarget() {
	sha := "c8cfbd75232e224c14ca613ff7d48c3499a1b1be"
	baseSha := types.CommitSha(sha)
	latestBaseSha := commitSha
	topicRefName := "refs/heads/topic-one"
	baseRefName := "refs/heads/master"
	baseBranch := "master"
	merged := true
	var pr = &gogithub.PullRequest{
		Merged: &merged,
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseBranch,
			SHA: &sha,
		},
	}

	e := &gogithub.PullRequestEvent{PullRequest: pr}
	client := &github.MockClient{}
	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, latestBaseSha, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{
			WorkflowFeatureFlags: types.WorkflowFeatureFlags{}}, nil)

	client.On("IsRefProtected", mock.Anything, mock.Anything, types.GitRef(baseRefName)).
		Return(true, nil)

	client.On("ResolveRef", mock.Anything, repoID, types.NewBranchRef(baseBranch)).Return(latestBaseSha, types.NewBranchRef(baseBranch), nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Name:   flowevents.PullRequestTarget,
			Commit: baseSha,
			Ref:    types.GitRef(baseRefName),
			Ghe:    e,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(data.References.CheckoutCommit, types.NewWorkflowInvocationReference(latestBaseSha, types.GitRef(baseRefName)))
	s.Require().Equal(data.References.CheckoutRefProtected, true)
	// GetMergeStatusForPullRequest should only be called for PR related events.
	client.AssertNumberOfCalls(s.T(), "GetMergeStatusForPullRequest", 0)

	client.AssertNumberOfCalls(s.T(), "IsRefProtected", 1)
}

func (s *InvokerTestSuite) Test_GetInvocationData_NotQueryRefProtectedForPullRequest() {
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	mergeCommitSha := types.CommitSha("merge-commit-sha")
	topicRefName := "refs/heads/topic-one"
	baseRefName := "refs/heads/base-one"

	var pr = &gogithub.PullRequest{
		Head: &gogithub.PullRequestBranch{
			Ref: &topicRefName,
			Repo: &gogithub.Repository{
				NodeID: &forkRepoNodeID,
			},
		},
		Base: &gogithub.PullRequestBranch{
			Ref: &baseRefName,
		},
	}

	event := &gogithub.PullRequestEvent{PullRequest: pr}

	client := &github.MockClient{}
	client.On("GetMergeStatusForPullRequest", mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&github.PullRequestMergeState{
			Merged:      false,
			Closed:      false,
			Mergeable:   githubv4.MergeableStateMergeable,
			MergeCommit: mergeCommitSha,
			MergeCommitParents: [2]types.CommitSha{
				types.CommitSha("base-sha"),
				commitSha,
			},
		}, nil)

	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, mergeCommitSha, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{
			WorkflowFeatureFlags: types.WorkflowFeatureFlags{}}, nil)

	mergeRef := fmt.Sprintf("refs/pull/%d/merge", pr.GetNumber())

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: commitSha,
			Ref:    types.GitRef(topicRefName),
			Ghe:    event,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(data.References.CheckoutCommit, types.NewWorkflowInvocationReference(mergeCommitSha, types.GitRef(mergeRef)))
	s.Require().Equal(data.References.CheckoutRefProtected, false)
	client.AssertNumberOfCalls(s.T(), "GetMergeStatusForPullRequest", 1)

	// IsRefProtected should only be called for PR_Target and non_PR related events.
	client.AssertNumberOfCalls(s.T(), "IsRefProtected", 0)
}

func (s *InvokerTestSuite) Test_GetInvocationData_CallableFeatureFlagIsOn_ForGHES() {
	expectedCommitSHA := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	baseRef := types.GitRef("refs/heads/topic")

	client := &github.MockClient{}
	client.On("GetDataForWorkflowInvocation", mock.Anything, mock.Anything, expectedCommitSHA, mock.Anything, mock.Anything, mock.Anything).
		Return(&types.WorkflowInvocationData{
			WorkflowFeatureFlags: types.WorkflowFeatureFlags{}}, nil)

	client.On("IsRefProtected", mock.Anything, mock.Anything, mock.Anything).
		Return(true, nil)

	invocation := Invocation{
		Target: invocationTarget{
			RepositoryID: repoID,
		},
		Event: InvokingEvent{
			Commit: expectedCommitSHA,
			Ref:    baseRef,
			Ghe:    stubCheckSuiteEvent,
		},
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}
	s.invoker.isEnterprise = true
	data, err := s.invoker.getInvocationData(context.Background(), NewNullObservability(), client, invocation, launchconfig.ProductionAppEnv)
	s.Require().NoError(err)
	s.Require().Equal(data.References.CheckoutCommit, types.NewWorkflowInvocationReference(expectedCommitSHA, baseRef))
	client.AssertNumberOfCalls(s.T(), "GetDataForWorkflowInvocation", 1)
}

func TestInvokerTestSuite(t *testing.T) {
	suite.Run(t, new(InvokerTestSuite))
}

func mustIntID(id types.GlobalID) int64 {
	_, out, err := id.Decode()
	if err != nil {
		panic(err)
	}
	return out
}
