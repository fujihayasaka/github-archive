package buildhealer

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/github"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/build"
)

type fixersSuite struct {
	suite.Suite
	mockClient *github.MockClient
}

func TestFixers(t *testing.T) {
	suite.Run(t, new(fixersSuite))
}

func (s *fixersSuite) SetupTest() {
	s.mockClient = github.NewMockClient(s.T())
}

const (
	repoID  = types.GlobalID("R_kgDODDgboQ")
	ownerID = int64(16631042)
)

var exampleWorkflowInfo = WorkflowInfo{
	RepositoryID:     repoID,
	CheckSuiteID:     types.GlobalID("checksuite-1"),
	State:            build.WorkflowStateStarted,
	WorkflowFilePath: ".github/workflows/test.yaml",
}

func (s *fixersSuite) Test_checkSuiteNoCheckRuns_HappyPath() {
	s.mockClient.EXPECT().CreateCheckRun(mock.Anything, mock.MatchedBy(func(req github.CreateCheckRunRequest) bool {
		s.Equal("Build failed", req.Name)
		return true
	})).Return(github.CheckRunResponse{}, nil)

	s.mockClient.EXPECT().UpdateCheckSuite(mock.Anything, mock.MatchedBy(func(req github.UpdateCheckSuiteRequest) bool {
		s.Equal(types.GlobalID("checksuite-1"), req.CheckSuiteID)
		return true
	})).Return(&types.IDPair{}, nil)

	state := github.CheckSuiteInfo{
		Status: string(github.CheckSuiteInProgressStatus),
		SHA:    "some-sha-asdf",
	}

	fixer := checkSuiteNoCheckRuns{conclusion: azptypes.ResultFailed}
	res, healed, err := fixer.Fix(context.Background(), s.mockClient, exampleWorkflowInfo, &state)
	s.NoError(err)
	s.True(healed)

	s.Equal(build.WorkflowStateFailed, res)
}

func (s *fixersSuite) Test_checkSuiteSomeRunsIncomplete_HappyPath() {
	now := time.Now().UTC()
	state := github.CheckSuiteInfo{
		Status:       string(github.CheckSuiteInProgressStatus),
		SHA:          "some-sha-asdf",
		NumCheckRuns: int64(2),
		CheckRuns: []github.CheckRunInfo{
			{
				ID:         "cr-done",
				Status:     string(github.CheckRunCompletedStatus),
				Conclusion: string(github.CheckRunSuccessConclusion),
				StartedAt:  &now,
				Number:     0,
			},
			{
				ID:        "cr-in-progress",
				Status:    string(github.CheckRunInProgressStatus),
				StartedAt: &now,
				Number:    1,
				Steps: []github.StepInfo{
					{
						Number:     0,
						Status:     string(github.CheckStepCompletedStatus),
						Conclusion: string(github.CheckStepSuccessConclusion),
					},
					{
						Number: 1,
						Status: string(github.CheckStepInProgressStatus),
					},
				},
			},
			{
				ID:     "cr-queued",
				Status: string(github.CheckRunQueuedStatus),
				Number: 2,
			},
		},
	}

	crFakeRes := github.CheckRunResponse{
		CheckRunIDPair: types.IDPair{
			GlobalID:   types.GlobalID("cr-in-progress"),
			DatabaseID: int64(42),
		},
	}

	// First call
	s.mockClient.EXPECT().UpdateCheckRun(mock.Anything, mock.MatchedBy(func(req github.UpdateCheckRunRequest) bool {
		if types.GlobalID("cr-in-progress") != req.CheckRunID {
			return false
		}

		s.Equal(string(github.CheckRunNeutralConclusion), req.Conclusion)
		s.Len(req.Steps, 1) // Just update the in progress one
		s.Equal(int64(1), req.Steps[0].Number)
		return true
	})).Return(crFakeRes, nil).Once()

	// Second call
	s.mockClient.EXPECT().UpdateCheckRun(mock.Anything, mock.MatchedBy(func(req github.UpdateCheckRunRequest) bool {
		if types.GlobalID("cr-queued") != req.CheckRunID {
			return false
		}

		s.Equal(string(github.CheckRunNeutralConclusion), req.Conclusion)
		s.Len(req.Steps, 0) // Run had no Steps
		return true
	})).Return(crFakeRes, nil).Once()

	s.mockClient.EXPECT().UpdateCheckSuite(mock.Anything, mock.MatchedBy(func(req github.UpdateCheckSuiteRequest) bool {
		s.Equal(types.GlobalID("checksuite-1"), req.CheckSuiteID)
		return true
	})).Return(&types.IDPair{}, nil)

	fixer := checkSuiteSomeRunsIncomplete{conclusion: azptypes.ResultCanceled}
	res, healed, err := fixer.Fix(context.Background(), s.mockClient, exampleWorkflowInfo, &state)
	s.NoError(err)
	s.True(healed)

	s.Equal(build.WorkflowStateCanceled, res)
}

func (s *fixersSuite) Test_checkSuiteAllRunsComplete_HappyPath() {
	now := time.Now().UTC()
	state := github.CheckSuiteInfo{
		Status:       string(github.CheckSuiteInProgressStatus),
		SHA:          "some-sha-asdf",
		NumCheckRuns: int64(2),
		CheckRuns: []github.CheckRunInfo{
			{
				ID:         "cr-done",
				Status:     string(github.CheckRunCompletedStatus),
				Conclusion: string(github.CheckRunFailedConclusion),
				StartedAt:  &now,
				Number:     0,
			},
			{
				ID:         "cr-done-also",
				Status:     string(github.CheckRunCompletedStatus),
				Conclusion: string(github.CheckRunSuccessConclusion),
				StartedAt:  &now,
				Number:     0,
			},
		},
	}

	s.mockClient.EXPECT().UpdateCheckSuite(mock.Anything, mock.MatchedBy(func(req github.UpdateCheckSuiteRequest) bool {
		s.Equal(types.GlobalID("checksuite-1"), req.CheckSuiteID)
		s.Equal(string(github.CheckSuiteFailureConclusion), req.Conclusion)
		return true
	})).Return(&types.IDPair{}, nil)

	fixer := checkSuiteAllRunsComplete{conclusion: azptypes.ResultSucceeded}
	res, healed, err := fixer.Fix(context.Background(), s.mockClient, exampleWorkflowInfo, &state)
	s.NoError(err)
	s.True(healed)

	s.Equal(build.WorkflowStateSucceeded, res)
}

func (s *fixersSuite) Test_rollupCheckRunConclusions() {
	tests := []struct {
		in       string
		out      string
		expected string
	}{
		{"action_required", "stale", "action_required"},
		{"stale", "timed_out", "stale"},
		{"timed_out", "failure", "timed_out"},
		{"failure", "cancelled", "failure"},
		{"cancelled", "success", "cancelled"},
		{"unknown", "success", "success"},
		{"unknown", "timed_out", "timed_out"},
	}

	for _, tt := range tests {
		s.Run(fmt.Sprintf("%s-%s-%s", tt.in, tt.out, tt.expected), func() {
			res := rollupCheckRunConclusions([]github.CheckRunInfo{
				{
					Conclusion: tt.in,
				},
				{
					Conclusion: tt.out,
				},
			})
			s.Equal(tt.expected, string(res))

			// Try in reverse order
			res = rollupCheckRunConclusions([]github.CheckRunInfo{
				{
					Conclusion: tt.out,
				},
				{
					Conclusion: tt.in,
				},
			})
			s.Equal(tt.expected, string(res))
		})
	}
}
