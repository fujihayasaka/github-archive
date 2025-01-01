package buildhealer

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/build"
)

type healBuildSuite struct {
	suite.Suite
	mockClientFactory *github.MockClientFactory
	mockClient        *github.MockClient
	mockRepo          *deployer.MockWorkflowBuildsRepository
}

func TestHealBuild(t *testing.T) {
	suite.Run(t, new(healBuildSuite))
}

func (s *healBuildSuite) SetupTest() {
	s.mockClientFactory = github.NewMockClientFactory()
	s.mockClient = github.NewMockClient(s.T())
	s.mockClientFactory.ByRepositoryOwnerDatabaseID[ownerID] = s.mockClient
	s.mockRepo = deployer.NewMockWorkflowBuildsRepository(s.T())
}

func (s *healBuildSuite) setupMockGithubTwirpClient(isUserSpammy, isRepositoryActionsDisabled bool) *ghtwirp.MockClient {
	ghTwirp := ghtwirp.NewMockClient(s.T())
	ghTwirp.EXPECT().IsRepositoryActionsDisabled(mock.Anything, mock.Anything).Return(isRepositoryActionsDisabled, nil)
	return ghTwirp
}

func (s *healBuildSuite) Test_HealWorkflow() {
	log := testutils.NewRecordingLogger()
	obs := observability.New(log.Logger, statter.NullStatter())

	uuid := types.NewRandomWorkflowExecutionID()

	wbID := int64(42)

	s.mockClient.EXPECT().GetCheckSuiteFromDotcom(mock.Anything, mock.Anything).
		Return(&github.CheckSuiteInfo{}, nil)

	s.mockClient.EXPECT().CreateCheckRun(mock.Anything, mock.MatchedBy(func(req github.CreateCheckRunRequest) bool {
		s.Equal("Build succeeded", req.Name)
		return true
	})).Return(github.CheckRunResponse{}, nil)

	s.mockClient.EXPECT().UpdateCheckSuite(mock.Anything, mock.MatchedBy(func(req github.UpdateCheckSuiteRequest) bool {
		s.Equal(types.GlobalID("checksuite-1"), req.CheckSuiteID)
		return true
	})).Return(&types.IDPair{}, nil)

	isUserSpammy := false
	isRepositoryActionsDisabled := false
	ghTwirp := s.setupMockGithubTwirpClient(isUserSpammy, isRepositoryActionsDisabled)

	s.mockRepo.EXPECT().Complete(mock.Anything, mock.Anything, mock.Anything, wbID, build.WorkflowStateSucceeded).Once().Return(nil)

	healer := Healer{
		obs:           obs,
		gf:            s.mockClientFactory,
		ghTwirpClient: ghTwirp,
		wfbRepo:       s.mockRepo,
	}
	w := WorkflowInfo{
		ID:           wbID,
		RepositoryID: repoID,
		OwnerID:      ownerID,
		CheckSuiteID: types.GlobalID("checksuite-1"),
		State:        build.WorkflowStateStarted,
		UUID:         uuid,
	}

	res, healed, err := healer.CompleteBuild(context.Background(), w, azptypes.StatusCompleted, azptypes.ResultSucceeded, ReasonManual)

	s.NoError(err)
	s.True(healed)
	s.Equal("no_check_runs", res)
}

func (s *healBuildSuite) Test_HealWorkflow_UnresolvableChecksuite() {
	log := testutils.NewRecordingLogger()
	obs := observability.New(log.Logger, statter.NullStatter())

	uuid := types.NewRandomWorkflowExecutionID()

	wbID := int64(42)

	s.mockClient.EXPECT().GetCheckSuiteFromDotcom(mock.Anything, mock.Anything).Return(nil, nil)

	s.mockRepo.EXPECT().Complete(mock.Anything, mock.Anything, mock.Anything, wbID, build.WorkflowStateCanceled).Once().Return(nil)

	isUserSpammy := false
	isRepositoryActionsDisabled := false
	ghTwirp := s.setupMockGithubTwirpClient(isUserSpammy, isRepositoryActionsDisabled)

	healer := Healer{
		obs:           obs,
		gf:            s.mockClientFactory,
		ghTwirpClient: ghTwirp,
		wfbRepo:       s.mockRepo,
	}
	w := WorkflowInfo{
		ID:           wbID,
		RepositoryID: repoID,
		OwnerID:      ownerID,
		CheckSuiteID: types.GlobalID("checksuite-1"),
		State:        build.WorkflowStateStarted,
		UUID:         uuid,
	}

	res, healed, err := healer.CompleteBuild(context.Background(), w, azptypes.StatusCompleted, azptypes.ResultSucceeded, ReasonManual)

	s.NoError(err)
	s.False(healed)
	s.Equal("workflow_run_deleted", res)
}

func (s *healBuildSuite) Test_HealWorkflow_NoCheckSuite() {
	log := testutils.NewRecordingLogger()
	obs := observability.New(log.Logger, statter.NullStatter())

	wbID := int64(42)
	uuid := types.NewRandomWorkflowExecutionID()

	w := WorkflowInfo{
		ID:           wbID,
		RepositoryID: repoID,
		OwnerID:      ownerID,
		CheckSuiteID: types.NilGlobalID,
		State:        build.WorkflowStateStarted,
		UUID:         uuid,
	}

	isUserSpammy := false
	isRepositoryActionsDisabled := false
	ghTwirp := s.setupMockGithubTwirpClient(isUserSpammy, isRepositoryActionsDisabled)

	s.mockRepo.EXPECT().Complete(mock.Anything, mock.Anything, mock.Anything, wbID, build.WorkflowStateNeverStarted).Once().Return(nil)

	healer := Healer{
		obs:           obs,
		gf:            s.mockClientFactory,
		ghTwirpClient: ghTwirp,
		wfbRepo:       s.mockRepo,
	}

	res, healed, err := healer.CompleteBuild(context.Background(), w, "completed", "success", ReasonManual)

	s.NoError(err)
	s.False(healed)
	s.Equal("check_suite_missing", res)
}

func (s *healBuildSuite) Test_CategorizeCheckSuiteState() {
	log := testutils.NewRecordingLogger()
	obs := observability.New(log.Logger, statter.NullStatter())
	healer := Healer{
		obs: obs,
		gf:  s.mockClientFactory,
	}

	tests := []struct {
		cs         *github.CheckSuiteInfo
		status     string
		conclusion string
		reason     HealReason
		expected   checkSuiteFixer
	}{
		{
			cs: &github.CheckSuiteInfo{
				Status: "COMPLETED",
			},
			status:     azptypes.StatusCompleted,
			conclusion: azptypes.ResultSucceeded,
			expected:   &checkSuiteAlreadyCompleted{conclusion: azptypes.ResultSucceeded},
		},
		{
			cs: &github.CheckSuiteInfo{
				NumCheckRuns: 0,
			},
			status:     azptypes.StatusCompleted,
			conclusion: azptypes.ResultSucceeded,
			reason:     ReasonScheduled,
			expected:   &checkSuiteNoCheckRuns{conclusion: azptypes.ResultSucceeded, reason: ReasonScheduled},
		},
		{
			cs: &github.CheckSuiteInfo{
				NumCheckRuns: 1,
				CheckRuns: []github.CheckRunInfo{
					{
						Status: "COMPLETED",
					},
				},
			},
			status:     azptypes.StatusCompleted,
			conclusion: azptypes.ResultSucceeded,
			expected:   &checkSuiteAllRunsComplete{conclusion: azptypes.ResultSucceeded},
		},
		{
			cs: &github.CheckSuiteInfo{
				NumCheckRuns: 2,
				CheckRuns: []github.CheckRunInfo{
					{
						Status: "COMPLETED",
					},
					{
						Status: "QUEUED",
					},
				},
			},
			status:     azptypes.StatusCompleted,
			conclusion: azptypes.ResultSucceeded,
			reason:     ReasonManual,
			expected:   &checkSuiteSomeRunsIncomplete{incompleteRunsCount: 1, conclusion: azptypes.ResultSucceeded, reason: ReasonManual},
		},
	}

	for _, tt := range tests {
		s.Run(string(tt.expected.String()), func() {
			res := healer.categorizeCheckSuiteState(tt.cs, tt.conclusion, tt.reason)
			s.Equal(tt.expected, res)
		})
	}
}

type simpleWorkflowBuild struct {
	uuid        types.WorkflowExecutionID
	queuedAt    *time.Time
	completedAt *time.Time
	state       int
}
