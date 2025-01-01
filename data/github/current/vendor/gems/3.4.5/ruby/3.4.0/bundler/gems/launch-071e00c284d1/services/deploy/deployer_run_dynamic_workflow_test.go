package deploy

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/shurcooL/githubv4"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/processors/build"
	"github.com/github/launch/services/deploy/workflowinvoker"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowparser"
)

func TestDeployer_RunDynamicWorkflow(t *testing.T) {
	suite.Run(t, new(RunDynamicWorkflowSuite))
}

type RunDynamicWorkflowSuite struct {
	suite.Suite
	svc *service
	aq  *aqueduct.MockClient

	ghClient *github.MockClient
	ghtwirp  *ghtwirp.MockClient
}

var (
	queueName   = "test-queue"
	repoID      = types.IdentityFromGlobalID("MDEwOlJlcG9zaXRvcnkz")
	actorID     = types.IdentityFromGlobalID("MDQ6VXNlcjE2NjMxMDQy")
	repoNextID  = types.IdentityFromGlobalID("R_kgAD")
	actorNextID = types.IdentityFromGlobalID("U_kgDOAP3FAg")
	commitSha   = types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")
	branchRef   = types.NewBranchRef("main")

	repoGID        = types.GlobalID(repoNextID.GlobalId)
	repoDatabaseID = int64(3)
)

func (s *RunDynamicWorkflowSuite) SetupTest() {
	svc, mocks := newServiceWithMocks()
	s.aq = mocks.aq

	s.ghClient = mocks.ghclient
	s.ghtwirp = mocks.ghtwirp
	s.svc = svc
}

func (s *RunDynamicWorkflowSuite) TearDownTest() {
	s.aq.AssertExpectations(s.T())
}

func (s *RunDynamicWorkflowSuite) Test_HappyPath() {
	type testCase struct {
		name   string
		appEnv launchconfig.AppEnv
	}

	testCases := []testCase{
		{"production env", launchconfig.ProductionAppEnv},
		{"lab env", launchconfig.LabAppEnv},
	}

	for _, tc := range testCases {
		s.svc.cfg.AppEnv = tc.appEnv
		ctx := context.Background()

		inputs := map[string]string{
			"foo": "bar",
		}

		jobMatcher := mock.MatchedBy(func(aqJob aqueduct.Job) bool {
			var buildJob build.Job
			s.NoError(json.Unmarshal(aqJob.Payload, &buildJob))

			return s.Equal(commitSha, buildJob.Invocation.Event.Commit) &&
				s.Equal(flowevents.Dynamic, buildJob.Invocation.Event.Name) &&
				s.Equal(types.IdentityToGlobalID(ctx, repoNextID), buildJob.Invocation.Target.RepositoryID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.ExecutingActor.ID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.TriggeringActor.ID) &&
				s.Equal("{\"ref\":\"refs/heads/main\",\"workflow\":\"on: push\\njobs:\\n  b:\\n    runs-on: ubuntu-latest\\n    steps:\\n    - run: echo\",\"inputs\":{\"foo\":\"bar\"},\"workflow_name\":\"some-workflow\",\"slug\":\"some-slug\",\"visibility\":\"DEFAULT\"}", string(buildJob.Invocation.Event.Payload)) &&
				s.NotEmpty(buildJob.Invocation.ExistingExecutionID)
		})

		s.aq.On("Send", mock.Anything, jobMatcher).Return("jobID", nil)

		checkSuiteID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 12))

		s.ghtwirp.ExpectedCalls = nil

		s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
			switch globalID {
			case repoID.GlobalId, repoNextID.GlobalId:
				return types.GlobalID(repoNextID.GlobalId)
			case actorID.GlobalId, actorNextID.GlobalId:
				return types.GlobalID(actorNextID.GlobalId)
			default:
				s.FailNow("unexpected global id", "global id: %s", globalID)
				return ""
			}
		}, nil)

		s.ghtwirp.On("GetRepositoryOwners", mock.Anything, mock.Anything).
			Return(&ghtwirp.RepositoryOwners{
				Owner:    ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
				Business: &ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
			}, nil)
		s.ghtwirp.On("IsUserSpammy", mock.Anything, mock.Anything).Return(false, nil).Once()

		s.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return("{}", nil)

		s.ghClient.On("CreateCheckSuite",
			mock.Anything,
			mock.Anything,
		).Return(&github.CreateCheckSuiteResponse{
			CheckSuiteIDPair: types.IDPair{
				DatabaseID: 12,
				GlobalID:   checkSuiteID,
			},
			WorkflowRun: &github.CheckSuiteWorkflowRun{
				DatabaseID: int64(14),
			},
		}, nil)

		s.aq.Mock.On("Send", mock.Anything, mock.Anything).
			Return(func(ctx context.Context, j aqueduct.Job) (string, error) {

				return "", nil
			})

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		res, err := s.svc.RunDynamicWorkflow(ctx, &pb.RunDynamicWorkflowRequest{
			RepositoryId:   repoID,
			InstallationId: 123,
			ActorId:        actorID,
			ActorLogin:     "monalisa",
			Workflow:       "on: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n    - run: echo",
			Ref:            branchRef.String(),
			Inputs:         inputs,
			WorkflowName:   "some-workflow",
			Slug:           "some-slug",
		})

		s.NoError(err)
		s.NotZero(res.GetExecutionId())
		s.Equal(int64(14), res.GetWorkflowRunId())
	}

}

func (s *RunDynamicWorkflowSuite) Test_HappyPath_NextGID() {
	type testCase struct {
		name   string
		appEnv launchconfig.AppEnv
	}

	testCases := []testCase{
		{"production env", launchconfig.ProductionAppEnv},
		{"lab env", launchconfig.LabAppEnv},
	}

	for _, tc := range testCases {
		s.svc.cfg.AppEnv = tc.appEnv
		ctx := context.Background()

		inputs := map[string]string{
			"foo": "bar",
		}

		jobMatcher := mock.MatchedBy(func(aqJob aqueduct.Job) bool {
			var buildJob build.Job
			s.NoError(json.Unmarshal(aqJob.Payload, &buildJob))

			return s.Equal(commitSha, buildJob.Invocation.Event.Commit) &&
				s.Equal(flowevents.Dynamic, buildJob.Invocation.Event.Name) &&
				s.Equal(types.IdentityToGlobalID(ctx, repoNextID), buildJob.Invocation.Target.RepositoryID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.ExecutingActor.ID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.TriggeringActor.ID) &&
				s.Equal("{\"ref\":\"refs/heads/main\",\"workflow\":\"on: push\\njobs:\\n  b:\\n    runs-on: ubuntu-latest\\n    steps:\\n    - run: echo\",\"inputs\":{\"foo\":\"bar\"},\"workflow_name\":\"some-workflow\",\"slug\":\"some-slug\",\"visibility\":\"DEFAULT\"}", string(buildJob.Invocation.Event.Payload)) &&
				s.NotEmpty(buildJob.Invocation.ExistingExecutionID)
		})

		s.aq.On("Send", mock.Anything, jobMatcher).Return("jobID", nil)

		checkSuiteID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 12))
		s.ghClient.ExpectedCalls = nil
		s.ghClient.On("ResolveRef", mock.Anything, types.GlobalID(repoNextID.GlobalId), branchRef).Return(commitSha, branchRef, nil)

		s.ghtwirp.ExpectedCalls = nil

		s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
			switch globalID {
			case repoID.GlobalId, repoNextID.GlobalId:
				return types.GlobalID(repoNextID.GlobalId)
			case actorID.GlobalId, actorNextID.GlobalId:
				return types.GlobalID(actorNextID.GlobalId)
			default:
				s.FailNow("unexpected global id", "global id: %s", globalID)
				return ""
			}
		}, nil)
		s.ghtwirp.On("GetRepositoryOwners", mock.Anything, mock.Anything).
			Return(&ghtwirp.RepositoryOwners{
				Owner:    ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorNextID)},
				Business: &ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorNextID)},
			}, nil)
		s.ghtwirp.On("IsUserSpammy", mock.Anything, mock.Anything).Return(false, nil).Once()

		s.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return("{}", nil)

		s.ghClient.On("CreateCheckSuite",
			mock.Anything,
			mock.Anything,
		).Return(&github.CreateCheckSuiteResponse{
			CheckSuiteIDPair: types.IDPair{
				DatabaseID: 12,
				GlobalID:   checkSuiteID,
			},
			WorkflowRun: &github.CheckSuiteWorkflowRun{
				DatabaseID: int64(14),
			},
		}, nil)

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		res, err := s.svc.RunDynamicWorkflow(ctx, &pb.RunDynamicWorkflowRequest{
			RepositoryId:   repoID,
			InstallationId: 123,
			ActorId:        actorID,
			ActorLogin:     "monalisa",
			Workflow:       "on: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n    - run: echo",
			Ref:            branchRef.String(),
			Inputs:         inputs,
			WorkflowName:   "some-workflow",
			Slug:           "some-slug",
		})

		s.NoError(err)
		s.NotZero(res.GetExecutionId())
		s.Equal(int64(14), res.GetWorkflowRunId())
	}

}

func (s *RunDynamicWorkflowSuite) Test_HiddenVisibilityPath() {
	type testCase struct {
		name   string
		appEnv launchconfig.AppEnv
	}

	testCases := []testCase{
		{"production env", launchconfig.ProductionAppEnv},
		{"lab env", launchconfig.LabAppEnv},
	}

	for _, tc := range testCases {
		s.svc.cfg.AppEnv = tc.appEnv

		ctx := context.Background()

		inputs := map[string]string{
			"test": "fee",
		}

		jobMatcher := mock.MatchedBy(func(aqJob aqueduct.Job) bool {
			var buildJob build.Job
			s.NoError(json.Unmarshal(aqJob.Payload, &buildJob))

			return s.Equal(commitSha, buildJob.Invocation.Event.Commit) &&
				s.Equal(flowevents.Dynamic, buildJob.Invocation.Event.Name) &&
				s.Equal(types.IdentityToGlobalID(ctx, repoNextID), buildJob.Invocation.Target.RepositoryID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.ExecutingActor.ID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.TriggeringActor.ID) &&
				s.Equal("{\"ref\":\"refs/heads/main\",\"workflow\":\"on: push\\njobs:\\n  b:\\n    runs-on: ubuntu-latest\\n    steps:\\n    - run: echo\",\"inputs\":{\"test\":\"fee\"},\"workflow_name\":\"some-workflow\",\"slug\":\"some-slug\",\"visibility\":\"HIDDEN\"}", string(buildJob.Invocation.Event.Payload)) && s.NotEmpty(buildJob.Invocation.ExistingExecutionID)
		})

		s.aq.On("Send", mock.Anything, jobMatcher).Return("jobID", nil)

		checkSuiteID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 12))

		s.ghtwirp.On("GetRepositoryOwners", mock.Anything, mock.Anything).
			Return(&ghtwirp.RepositoryOwners{
				Owner:    ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
				Business: &ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
			}, nil)
		s.ghtwirp.On("IsUserSpammy", mock.Anything, mock.Anything).Return(false, nil).Once()

		s.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return("{}", nil)

		s.ghClient.On("CreateCheckSuite",
			mock.Anything,
			mock.Anything,
		).Return(&github.CreateCheckSuiteResponse{
			CheckSuiteIDPair: types.IDPair{
				DatabaseID: 12,
				GlobalID:   checkSuiteID,
			},
			WorkflowRun: &github.CheckSuiteWorkflowRun{
				DatabaseID: int64(14),
			},
		}, nil)

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		res, err := s.svc.RunDynamicWorkflow(ctx, &pb.RunDynamicWorkflowRequest{
			RepositoryId:   repoID,
			InstallationId: 123,
			ActorId:        actorID,
			ActorLogin:     "monalisa",
			Workflow:       "on: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n    - run: echo",
			Ref:            branchRef.String(),
			Inputs:         inputs,
			WorkflowName:   "some-workflow",
			Slug:           "some-slug",
			Visibility:     pb.Visibility_HIDDEN,
		})

		s.NoError(err)
		s.NotZero(res.GetExecutionId())
		s.Equal(int64(14), res.GetWorkflowRunId())
	}
}

func (s *RunDynamicWorkflowSuite) Test_InvalidWorkflow() {
	type testCase struct {
		name   string
		appEnv launchconfig.AppEnv
	}

	testCases := []testCase{
		{"production env", launchconfig.ProductionAppEnv},
		{"lab env", launchconfig.LabAppEnv},
	}

	for _, tc := range testCases {
		s.svc.cfg.AppEnv = tc.appEnv

		ctx := context.Background()

		s.ghtwirp.On("GetRepositoryOwners", mock.Anything, mock.Anything).
			Return(&ghtwirp.RepositoryOwners{
				Owner:    ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
				Business: &ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
			}, nil)
		s.ghtwirp.On("IsUserSpammy", mock.Anything, mock.Anything).Return(false, nil).Once()
		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)
		s.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return("{}", nil)

		res, err := s.svc.RunDynamicWorkflow(ctx, &pb.RunDynamicWorkflowRequest{
			RepositoryId:   repoID,
			InstallationId: 123,
			ActorId:        actorID,
			ActorLogin:     "monalisa",
			Workflow:       "on: push\nTODO",
			Ref:            branchRef.String(),
		})

		s.Error(err)
		s.Zero(res.GetExecutionId())
		s.Zero(res.GetWorkflowRunId())
		s.Equal(err, svcerr.NewInvalidArgumentError("Invalid workflow: 'You have an error in your yaml syntax on line 2'"))
	}

}

func (s *RunDynamicWorkflowSuite) Test_ReusableWorkflow_HappyPath() {
	type testCase struct {
		name   string
		appEnv launchconfig.AppEnv
	}

	testCases := []testCase{
		{"production env", launchconfig.ProductionAppEnv},
		{"lab env", launchconfig.LabAppEnv},
	}

	for _, tc := range testCases {
		s.svc.cfg.AppEnv = tc.appEnv
		ctx := context.Background()

		inputs := map[string]string{
			"foo": "bar",
		}

		jobMatcher := mock.MatchedBy(func(aqJob aqueduct.Job) bool {
			var buildJob build.Job
			s.NoError(json.Unmarshal(aqJob.Payload, &buildJob))

			return s.Equal(commitSha, buildJob.Invocation.Event.Commit) &&
				s.Equal(flowevents.Dynamic, buildJob.Invocation.Event.Name) &&
				s.Equal(types.IdentityToGlobalID(ctx, repoNextID), buildJob.Invocation.Target.RepositoryID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.ExecutingActor.ID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.TriggeringActor.ID) &&
				s.Equal("{\"ref\":\"refs/heads/main\",\"workflow\":\"on: push\\njobs:\\n  b:\\n    uses: actions/workflows/.github/workflows/called.yml@v1\",\"inputs\":{\"foo\":\"bar\"},\"workflow_name\":\"some-workflow\",\"slug\":\"some-slug\",\"visibility\":\"DEFAULT\"}", string(buildJob.Invocation.Event.Payload)) &&
				s.NotEmpty(buildJob.Invocation.ExistingExecutionID)
		})

		s.aq.On("Send", mock.Anything, jobMatcher).Return("jobID", nil)

		checkSuiteID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 12))

		s.ghtwirp.On("GetRepositoryOwners", mock.Anything, mock.Anything).
			Return(&ghtwirp.RepositoryOwners{
				Owner:    ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
				Business: &ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
			}, nil)
		s.ghtwirp.On("IsUserSpammy", mock.Anything, mock.Anything).Return(false, nil).Once()

		s.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return("{}", nil)

		s.ghClient.On("CreateCheckSuite",
			mock.Anything,
			mock.Anything,
		).Return(&github.CreateCheckSuiteResponse{
			CheckSuiteIDPair: types.IDPair{
				DatabaseID: 12,
				GlobalID:   checkSuiteID,
			},
			WorkflowRun: &github.CheckSuiteWorkflowRun{
				DatabaseID: int64(14),
			},
		}, nil)

		wfSrc := &workflowparser.StubWorkflowSource{
			SourceMap: map[string]workflowparser.WorkflowDetails{
				"actions/workflows/.github/workflows/called.yml@v1": {
					Content: `
on:
  workflow_call:
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
					RefType: "refs/tags/",
				},
			}}

		mockWorkflowSourceFactory := &workflowinvoker.MockWorkflowSourceFactory{}
		mockWorkflowSourceFactory.On(
			"Build",
			mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything,
		).Return(wfSrc)
		s.svc.cfg.WorkflowSourceFactory = mockWorkflowSourceFactory

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		res, err := s.svc.RunDynamicWorkflow(ctx, &pb.RunDynamicWorkflowRequest{
			RepositoryId:   repoID,
			InstallationId: 123,
			ActorId:        actorID,
			ActorLogin:     "monalisa",
			Workflow:       "on: push\njobs:\n  b:\n    uses: actions/workflows/.github/workflows/called.yml@v1",
			Ref:            branchRef.String(),
			Inputs:         inputs,
			WorkflowName:   "some-workflow",
			Slug:           "some-slug",
		})

		s.NoError(err)
		s.NotZero(res.GetExecutionId())
		s.Equal(int64(14), res.GetWorkflowRunId())
	}
}

func (s *RunDynamicWorkflowSuite) Test_ReusableWorkflow_HappyPath_Nested() {
	type testCase struct {
		name   string
		appEnv launchconfig.AppEnv
	}

	testCases := []testCase{
		{"production env", launchconfig.ProductionAppEnv},
		{"lab env", launchconfig.LabAppEnv},
	}

	for _, tc := range testCases {
		s.svc.cfg.AppEnv = tc.appEnv
		ctx := context.Background()

		inputs := map[string]string{
			"foo": "bar",
		}

		jobMatcher := mock.MatchedBy(func(aqJob aqueduct.Job) bool {
			var buildJob build.Job
			s.NoError(json.Unmarshal(aqJob.Payload, &buildJob))

			return s.Equal(commitSha, buildJob.Invocation.Event.Commit) &&
				s.Equal(flowevents.Dynamic, buildJob.Invocation.Event.Name) &&
				s.Equal(types.IdentityToGlobalID(ctx, repoNextID), buildJob.Invocation.Target.RepositoryID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.ExecutingActor.ID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.TriggeringActor.ID) &&
				s.Equal("{\"ref\":\"refs/heads/main\",\"workflow\":\"on: push\\njobs:\\n  b:\\n    uses: actions/workflows/.github/workflows/B.yml@v1\",\"inputs\":{\"foo\":\"bar\"},\"workflow_name\":\"caller\",\"slug\":\"some-slug\",\"visibility\":\"DEFAULT\"}", string(buildJob.Invocation.Event.Payload)) &&
				s.NotEmpty(buildJob.Invocation.ExistingExecutionID)
		})

		s.aq.On("Send", mock.Anything, jobMatcher).Return("jobID", nil)

		checkSuiteID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 12))

		s.ghtwirp.On("GetRepositoryOwners", mock.Anything, mock.Anything).
			Return(&ghtwirp.RepositoryOwners{
				Owner:    ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
				Business: &ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
			}, nil)
		s.ghtwirp.On("IsUserSpammy", mock.Anything, mock.Anything).Return(false, nil).Once()

		s.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return("{}", nil)

		s.ghClient.On("CreateCheckSuite",
			mock.Anything,
			mock.Anything,
		).Return(&github.CreateCheckSuiteResponse{
			CheckSuiteIDPair: types.IDPair{
				DatabaseID: 12,
				GlobalID:   checkSuiteID,
			},
			WorkflowRun: &github.CheckSuiteWorkflowRun{
				DatabaseID: int64(14),
			},
		}, nil)

		wfSrc := &workflowparser.StubWorkflowSource{
			SourceMap: map[string]workflowparser.WorkflowDetails{
				"actions/workflows/.github/workflows/B.yml@v1": {
					Content: `
on:
  workflow_call:
jobs:
  thing:
    uses: owner/repo/.github/workflows/C.yml@main`,
					RefType: "refs/tags/",
				},
				"owner/repo/.github/workflows/C.yml@main": {
					Content: `
on:
  workflow_call:
jobs:
  thing:
    uses: owner/repo/.github/workflows/D.yml@v2`,
					RefType: "refs/heads/",
				},
				"owner/repo/.github/workflows/D.yml@v2": {
					Content: `
on:
  workflow_call:
jobs:
  thing:
    steps:
      - uses: owner/repo@master`,
					RefType: "refs/tags/",
				}}}

		mockWorkflowSourceFactory := &workflowinvoker.MockWorkflowSourceFactory{}
		mockWorkflowSourceFactory.On(
			"Build",
			mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything,
		).Return(wfSrc)
		s.svc.cfg.WorkflowSourceFactory = mockWorkflowSourceFactory

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		res, err := s.svc.RunDynamicWorkflow(ctx, &pb.RunDynamicWorkflowRequest{
			RepositoryId:   repoID,
			InstallationId: 123,
			ActorId:        actorID,
			ActorLogin:     "monalisa",
			Workflow:       "on: push\njobs:\n  b:\n    uses: actions/workflows/.github/workflows/B.yml@v1",
			Ref:            branchRef.String(),
			Inputs:         inputs,
			WorkflowName:   "caller",
			Slug:           "some-slug",
		})

		s.NoError(err)
		s.NotZero(res.GetExecutionId())
		s.Equal(int64(14), res.GetWorkflowRunId())
	}
}

func Test_RunDynamicWorkflow_MultiTenant(t *testing.T) {
	tenantID := int64(1)
	tenantSlug := "slug"

	ctxWithoutTenant := context.Background()
	ctxWithTenantIDAndSlug, _ := ghtenant.ContextWithTenantID(context.Background(), tenantID, true)
	ctxWithTenantIDAndSlug, _ = ghtenant.ContextWithTenantSlug(ctxWithTenantIDAndSlug, tenantSlug, true)
	ctxWithoutTenantID, _ := ghtenant.ContextWithTenantSlug(context.Background(), tenantSlug, true)
	ctxWithoutTenantSlug, _ := ghtenant.ContextWithTenantID(context.Background(), tenantID, true)
	ctxWithTenantIDAndMalformedSlug, _ := ghtenant.ContextWithTenantID(context.Background(), int64(1), true)
	ctxWithTenantIDAndMalformedSlug, _ = ghtenant.ContextWithTenantSlug(ctxWithTenantIDAndMalformedSlug, "", true)
	ctxWithMalformedTenantIDAndTenantSlug, _ := ghtenant.ContextWithTenantID(context.Background(), int64(-1), true)
	ctxWithMalformedTenantIDAndTenantSlug, _ = ghtenant.ContextWithTenantSlug(ctxWithMalformedTenantIDAndTenantSlug, tenantSlug, true)

	tests := []struct {
		name          string
		isMultiTenant bool
		ctx           context.Context
		shouldErr     bool
	}{
		{
			name: "not-multi-tenant/no-tenant-in-context",
			ctx:  ctxWithoutTenant,
		},
		{
			name: "not-multi-tenant/ctx-with-tenant-id-and-tenant-slug",
			ctx:  ctxWithTenantIDAndSlug,
		},
		{
			name:          "multi-tenant/ctx-with-tenant-id-and-tenant-slug",
			isMultiTenant: true,
			ctx:           ctxWithTenantIDAndSlug,
		},
		{
			name:          "multi-tenant/missing-tenant-id",
			isMultiTenant: true,
			ctx:           ctxWithoutTenantID,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/ctx-missing-tenant-slug",
			isMultiTenant: true,
			ctx:           ctxWithoutTenantSlug,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/ctx-with-tenant-id-and-malformed-slug",
			isMultiTenant: true,
			ctx:           ctxWithTenantIDAndMalformedSlug,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/ctx-with-malformed-tenant-id-and-tenant-slug",
			isMultiTenant: true,
			ctx:           ctxWithMalformedTenantIDAndTenantSlug,
			shouldErr:     true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			svc, mocks := newServiceWithMocks()
			svc.IsMultiTenant = test.isMultiTenant

			mocks.ghtwirp.On("GetRepositoryOwners", mock.Anything, mock.Anything).
				Return(&ghtwirp.RepositoryOwners{
					Owner:    ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(test.ctx, actorID)},
					Business: &ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(test.ctx, actorID)},
				}, nil)
			mocks.ghtwirp.On("IsUserSpammy", mock.Anything, mock.Anything).Return(false, nil).Once()
			mocks.ghclient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
				Owner: "monalisa",
				Name:  "some-repo",
			}, nil)

			mocks.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return("{}", nil)

			mocks.ghclient.On("CreateCheckSuite",
				mock.Anything,
				mock.Anything,
			).Return(&github.CreateCheckSuiteResponse{
				CheckSuiteIDPair: types.IDPair{
					DatabaseID: 12,
					GlobalID:   types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 12)),
				},
				WorkflowRun: &github.CheckSuiteWorkflowRun{
					DatabaseID: int64(14),
				},
			}, nil)

			// In multi-tenant environments, the key assertion is that the the published aqueduct message
			// to run the dynamic workflow contains GitHub tenant information in the payload.
			mocks.aq.Mock.On("Send", mock.Anything, mock.Anything).Return("jobID", nil)

			_, err := svc.RunDynamicWorkflow(test.ctx, &pb.RunDynamicWorkflowRequest{
				RepositoryId:   repoID,
				InstallationId: 123,
				ActorId:        actorID,
				ActorLogin:     "monalisa",
				Workflow:       "on: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n    - run: echo",
				Ref:            branchRef.String(),
				Inputs: map[string]string{
					"foo": "bar",
				},
				WorkflowName: "some-workflow",
				Slug:         "some-slug",
			})

			r := require.New(t)

			if test.shouldErr {
				r.Error(err)
				mocks.aq.AssertNumberOfCalls(t, "Send", 0)
				return
			}

			r.NoError(err)
			mocks.aq.AssertNumberOfCalls(t, "Send", 1)
			aqueductJob, ok := mocks.aq.Calls[0].Arguments.Get(1).(aqueduct.Job)

			if !ok {
				t.Fatalf("error getting aqueduct job payload for Send call, check arguments")
			}

			var invocationJob build.Job
			err = json.Unmarshal(aqueductJob.Payload, &invocationJob)
			r.NoError(err, "expected aqueduct job payload to be an Invocation struct")

			if test.isMultiTenant {
				githubTenant := invocationJob.Invocation.Target.GitHubTenant
				r.Equal(tenantID, githubTenant.ID)
				r.Equal(tenantSlug, githubTenant.Slug)
			}
		})
	}
}

func (s *RunDynamicWorkflowSuite) Test_InstallationValidAfter() {
	type testCase struct {
		name                   string
		installationValidAfter *timestamppb.Timestamp
		delayExpected          bool
	}

	now := time.Now().UTC()
	testCases := []testCase{
		{"installation valid after not set, no delay", nil, false},
		{"installation valid after in future, delayed", timestamppb.New(now.Add(time.Minute)), true},
		{"installation valid after in past, no delay", timestamppb.New(now.Add(-time.Minute)), false},
	}

	for _, tc := range testCases {
		ctx := context.Background()

		s.ghtwirp.ExpectedCalls = nil
		s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
			switch globalID {
			case repoID.GlobalId, repoNextID.GlobalId:
				return types.GlobalID(repoNextID.GlobalId)
			case actorID.GlobalId, actorNextID.GlobalId:
				return types.GlobalID(actorNextID.GlobalId)
			default:
				s.FailNow("unexpected global id", "global id: %s", globalID)
				return ""
			}
		}, nil)
		s.ghtwirp.On("IsUserSpammy", mock.Anything, mock.Anything).Return(false, nil).Once()
		s.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return("{}", nil)

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		s.ghClient.On("CreateCheckSuite", mock.Anything, mock.Anything).Return(&github.CreateCheckSuiteResponse{
			CheckSuiteIDPair: types.IDPair{
				DatabaseID: 12,
				GlobalID:   types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 12)),
			},
			WorkflowRun: &github.CheckSuiteWorkflowRun{
				DatabaseID: int64(14),
			},
		}, nil)

		jobMatcher := mock.MatchedBy(func(aqJob aqueduct.Job) bool {
			if tc.delayExpected {
				return s.Equal(tc.installationValidAfter.AsTime(), aqJob.DeliverAt)
			}
			return s.Equal(time.Time{}, aqJob.DeliverAt)
		})

		s.aq.ExpectedCalls = nil
		s.aq.On("Send", mock.Anything, jobMatcher).Return("jobID", nil)

		res, err := s.svc.RunDynamicWorkflow(ctx, &pb.RunDynamicWorkflowRequest{
			RepositoryId:           repoID,
			InstallationId:         123,
			ActorId:                actorID,
			ActorLogin:             "monalisa",
			Workflow:               "on: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n    - run: echo",
			Ref:                    branchRef.String(),
			WorkflowName:           "some-workflow",
			Slug:                   "some-slug",
			InstallationValidAfter: tc.installationValidAfter,
		})

		s.NoError(err)
		s.NotZero(res.GetExecutionId())
		s.Equal(int64(14), res.GetWorkflowRunId())
	}
}

func (s *RunDynamicWorkflowSuite) Test_FailsDynamicRunForSpammyUser() {
	type testCase struct {
		name               string
		userIsSpammy       bool
		spammyCheckErrored bool
		runShouldFail      bool
		appEnv             launchconfig.AppEnv
	}

	testCases := []testCase{
		{
			name:         "run succeeds when spammy flag is enabled but user is not spammy. Production env",
			userIsSpammy: false,
			appEnv:       launchconfig.ProductionAppEnv,
		},
		{
			name:          "run fails when spammy flag is enabled and user is spammy. Production env",
			userIsSpammy:  true,
			runShouldFail: true,
			appEnv:        launchconfig.ProductionAppEnv,
		},
		{
			name:               "run continues when spammy flag is enabled and spammy check fails. Production env",
			userIsSpammy:       true,
			spammyCheckErrored: true,
			runShouldFail:      false,
			appEnv:             launchconfig.ProductionAppEnv,
		},
		{
			name:         "run succeeds when spammy flag is enabled but user is not spammy. Launch lab env",
			userIsSpammy: false,
			appEnv:       launchconfig.LabAppEnv,
		},
		{
			name:          "run fails when spammy flag is enabled and user is spammy. Launch lab env",
			userIsSpammy:  true,
			runShouldFail: true,
			appEnv:        launchconfig.LabAppEnv,
		},
		{
			name:               "run continues when spammy flag is enabled and spammy check fails. Launch lab env",
			userIsSpammy:       true,
			spammyCheckErrored: true,
			runShouldFail:      false,
			appEnv:             launchconfig.LabAppEnv,
		},
	}

	for _, tc := range testCases {
		s.svc.cfg.AppEnv = tc.appEnv
		ctx := context.Background()

		inputs := map[string]string{
			"foo": "bar",
		}

		jobMatcher := mock.MatchedBy(func(aqJob aqueduct.Job) bool {
			var buildJob build.Job
			s.NoError(json.Unmarshal(aqJob.Payload, &buildJob))

			return s.Equal(commitSha, buildJob.Invocation.Event.Commit) &&
				s.Equal(flowevents.Dynamic, buildJob.Invocation.Event.Name) &&
				s.Equal(types.IdentityToGlobalID(ctx, repoNextID), buildJob.Invocation.Target.RepositoryID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.ExecutingActor.ID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.TriggeringActor.ID) &&
				s.Equal("{\"ref\":\"refs/heads/main\",\"workflow\":\"on: push\\njobs:\\n  b:\\n    runs-on: ubuntu-latest\\n    steps:\\n    - run: echo\",\"inputs\":{\"foo\":\"bar\"},\"workflow_name\":\"some-workflow\",\"slug\":\"some-slug\",\"visibility\":\"DEFAULT\"}", string(buildJob.Invocation.Event.Payload)) &&
				s.NotEmpty(buildJob.Invocation.ExistingExecutionID)
		})

		s.aq.On("Send", mock.Anything, jobMatcher).Return("jobID", nil)

		checkSuiteID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 12))

		s.ghtwirp.ExpectedCalls = nil

		s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
			switch globalID {
			case repoID.GlobalId, repoNextID.GlobalId:
				return types.GlobalID(repoNextID.GlobalId)
			case actorID.GlobalId, actorNextID.GlobalId:
				return types.GlobalID(actorNextID.GlobalId)
			default:
				s.FailNow("unexpected global id", "global id: %s", globalID)
				return ""
			}
		}, nil)

		s.ghtwirp.On("GetRepositoryOwners", mock.Anything, mock.Anything).
			Return(&ghtwirp.RepositoryOwners{
				Owner:    ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
				Business: &ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
			}, nil)

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		actorGID := types.GlobalID(actorNextID.GlobalId)
		if tc.spammyCheckErrored {
			s.ghtwirp.On("IsUserSpammy", mock.Anything, actorGID).Return(false, errors.New("some error")).Once()
		} else {
			s.ghtwirp.On("IsUserSpammy", mock.Anything, actorGID).Return(tc.userIsSpammy, nil).Once()
		}

		if tc.spammyCheckErrored || !tc.userIsSpammy {
			s.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return("{}", nil)
		}

		s.ghClient.On("CreateCheckSuite",
			mock.Anything,
			mock.Anything,
		).Return(&github.CreateCheckSuiteResponse{
			CheckSuiteIDPair: types.IDPair{
				DatabaseID: 12,
				GlobalID:   checkSuiteID,
			},
			WorkflowRun: &github.CheckSuiteWorkflowRun{
				DatabaseID: int64(14),
			},
		}, nil)

		s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		res, err := s.svc.RunDynamicWorkflow(ctx, &pb.RunDynamicWorkflowRequest{
			RepositoryId:   repoID,
			InstallationId: 123,
			ActorId:        actorID,
			ActorLogin:     "monalisa",
			Workflow:       "on: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n    - run: echo",
			Ref:            branchRef.String(),
			Inputs:         inputs,
			WorkflowName:   "some-workflow",
			Slug:           "some-slug",
		})

		if tc.runShouldFail {
			s.Require().Error(err)
			s.Require().EqualError(err, "twirp error failed_precondition: Not running dynamic workflow for spammy user")
			s.Require().Zero(res.GetExecutionId())
			s.Require().Zero(res.GetWorkflowRunId())
		} else {
			s.Require().NoError(err)
			s.Require().NotZero(res.GetExecutionId())
			s.Require().Equal(int64(14), res.GetWorkflowRunId())
		}

	}

}

func (s *RunDynamicWorkflowSuite) Test_DynamicRunWithRepositoryEventDetails() {
	const (
		workflow     = "on: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n    - run: echo"
		workflowName = "some-workflow"
		slug         = "some-slug"
		visibility   = githubv4.CheckSuiteVisibilityDefault
	)

	inputs := map[string]string{
		"foo": "bar",
	}

	userOwnedRepoEventDetails, err := os.ReadFile(filepath.Join("scheduled", "fixtures", "user_repository_details.json"))
	s.NoError(err)

	var userRepoPayload map[string]map[string]interface{}
	err = json.Unmarshal([]byte(userOwnedRepoEventDetails), &userRepoPayload)
	s.NoError(err)
	s.NotNil(userRepoPayload["repository"])

	orgRepoEventDetails, err := os.ReadFile(filepath.Join("scheduled", "fixtures", "organization_repository_details.json"))
	s.NoError(err)

	var orgRepoPayload map[string]map[string]interface{}
	err = json.Unmarshal([]byte(orgRepoEventDetails), &orgRepoPayload)
	s.NoError(err)
	s.NotNil(orgRepoPayload["repository"])
	s.NotNil(orgRepoPayload["organization"])

	enterpriseRepoEventDetails, err := os.ReadFile(filepath.Join("scheduled", "fixtures", "enterprise_repository_details.json"))
	s.NoError(err)

	var enterpriseRepoPayload map[string]map[string]interface{}
	err = json.Unmarshal([]byte(enterpriseRepoEventDetails), &enterpriseRepoPayload)
	s.NoError(err)
	s.NotNil(enterpriseRepoPayload["repository"])
	s.NotNil(enterpriseRepoPayload["organization"])
	s.NotNil(enterpriseRepoPayload["enterprise"])

	testCases := []struct {
		name                 string
		eventDetails         string
		eventDetailsErr      error
		expectedEventPayload flowevents.DynamicEvent
	}{
		{
			name:            "error fetching event details",
			eventDetailsErr: errors.New("fetching event details"),
			expectedEventPayload: flowevents.DynamicEvent{
				Ref:          branchRef.String(),
				Workflow:     workflow,
				Inputs:       inputs,
				WorkflowName: workflowName,
				Slug:         slug,
				Visibility:   visibility,
			},
		},
		{
			name:         "user owned repository",
			eventDetails: string(userOwnedRepoEventDetails),
			expectedEventPayload: flowevents.DynamicEvent{
				Ref:          branchRef.String(),
				Workflow:     workflow,
				Inputs:       inputs,
				WorkflowName: workflowName,
				Slug:         slug,
				Visibility:   visibility,
				Repository:   userRepoPayload["repository"],
			},
		},
		{
			name:         "organization repository",
			eventDetails: string(orgRepoEventDetails),
			expectedEventPayload: flowevents.DynamicEvent{
				Ref:          branchRef.String(),
				Workflow:     workflow,
				Inputs:       inputs,
				WorkflowName: workflowName,
				Slug:         slug,
				Visibility:   visibility,
				Repository:   orgRepoPayload["repository"],
				Organization: orgRepoPayload["organization"],
			},
		},
		{
			name:         "enterprise repository",
			eventDetails: string(enterpriseRepoEventDetails),
			expectedEventPayload: flowevents.DynamicEvent{
				Ref:          branchRef.String(),
				Workflow:     workflow,
				Inputs:       inputs,
				WorkflowName: workflowName,
				Slug:         slug,
				Visibility:   visibility,
				Repository:   enterpriseRepoPayload["repository"],
				Organization: enterpriseRepoPayload["organization"],
				Enterprise:   enterpriseRepoPayload["enterprise"],
			},
		},
	}

	for _, tc := range testCases {
		ctx := context.Background()

		jobMatcher := mock.MatchedBy(func(aqJob aqueduct.Job) bool {
			var buildJob build.Job
			s.NoError(json.Unmarshal(aqJob.Payload, &buildJob))

			var payloadToDynamicEvent flowevents.DynamicEvent
			s.NoError(json.Unmarshal(buildJob.Invocation.Event.Payload, &payloadToDynamicEvent))

			return s.Equal(commitSha, buildJob.Invocation.Event.Commit) &&
				s.Equal(flowevents.Dynamic, buildJob.Invocation.Event.Name) &&
				s.Equal(types.IdentityToGlobalID(ctx, repoNextID), buildJob.Invocation.Target.RepositoryID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.ExecutingActor.ID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.TriggeringActor.ID) &&
				s.Equal(tc.expectedEventPayload, payloadToDynamicEvent) &&
				s.NotEmpty(buildJob.Invocation.ExistingExecutionID)
		})

		s.aq.ExpectedCalls = nil
		s.aq.Calls = nil
		s.aq.On("Send", mock.Anything, jobMatcher).Return("jobID", nil)

		checkSuiteID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 12))

		s.ghtwirp.ExpectedCalls = nil

		s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
			switch globalID {
			case repoID.GlobalId, repoNextID.GlobalId:
				return types.GlobalID(repoNextID.GlobalId)
			case actorID.GlobalId, actorNextID.GlobalId:
				return types.GlobalID(actorNextID.GlobalId)
			default:
				s.FailNow("unexpected global id", "global id: %s", globalID)
				return ""
			}
		}, nil)

		s.ghtwirp.On("GetRepositoryOwners", mock.Anything, mock.Anything).
			Return(&ghtwirp.RepositoryOwners{
				Owner:    ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
				Business: &ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
			}, nil)
		s.ghtwirp.On("IsUserSpammy", mock.Anything, mock.Anything).Return(false, nil).Once()

		if tc.eventDetails != "" || tc.eventDetailsErr != nil {
			s.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return(tc.eventDetails, tc.eventDetailsErr)
		}

		s.ghClient.On("CreateCheckSuite",
			mock.Anything,
			mock.Anything,
		).Return(&github.CreateCheckSuiteResponse{
			CheckSuiteIDPair: types.IDPair{
				DatabaseID: 12,
				GlobalID:   checkSuiteID,
			},
			WorkflowRun: &github.CheckSuiteWorkflowRun{
				DatabaseID: int64(14),
			},
		}, nil)

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		res, err := s.svc.RunDynamicWorkflow(ctx, &pb.RunDynamicWorkflowRequest{
			RepositoryId:   repoID,
			InstallationId: 123,
			ActorId:        actorID,
			ActorLogin:     "monalisa",
			Workflow:       workflow,
			Ref:            branchRef.String(),
			Inputs:         inputs,
			WorkflowName:   workflowName,
			Slug:           slug,
		})

		s.NoError(err)
		s.NotZero(res.GetExecutionId())
		s.Equal(int64(14), res.GetWorkflowRunId())
	}
}

func (s *RunDynamicWorkflowSuite) Test_DynamicRunPullHeadRefFallback() {
	const (
		workflow     = "on: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n    - run: echo"
		workflowName = "some-workflow"
		slug         = "some-slug"
		visibility   = githubv4.CheckSuiteVisibilityDefault
	)

	inputs := map[string]string{
		"foo": "bar",
	}

	pullHeadRef := types.GitRef("refs/pull/1/head")

	testCases := []struct {
		name             string
		ref              types.GitRef
		resolvedRef      types.GitRef
		expectedEventRef types.GitRef
	}{
		{
			name:             "Pull head ref",
			ref:              pullHeadRef,
			resolvedRef:      types.GitRefZeroValue,
			expectedEventRef: pullHeadRef,
		},
		{
			name:             "Head ref (branch)",
			ref:              branchRef,
			resolvedRef:      branchRef,
			expectedEventRef: branchRef,
		},
		{
			name:             "Resolved empty ref for non-PR ref",
			ref:              types.GitRef("refs/foo"),
			resolvedRef:      types.GitRefZeroValue,
			expectedEventRef: "",
		},
	}

	for _, tc := range testCases {
		ctx := context.Background()

		jobMatcher := mock.MatchedBy(func(aqJob aqueduct.Job) bool {
			var buildJob build.Job
			s.NoError(json.Unmarshal(aqJob.Payload, &buildJob))

			event := buildJob.Invocation.Event

			return s.Equal(commitSha, buildJob.Invocation.Event.Commit) &&
				s.Equal(flowevents.Dynamic, buildJob.Invocation.Event.Name) &&
				s.Equal(types.IdentityToGlobalID(ctx, repoNextID), buildJob.Invocation.Target.RepositoryID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.ExecutingActor.ID) &&
				s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.TriggeringActor.ID) &&
				s.Equal(tc.expectedEventRef, event.Ref) &&
				s.NotEmpty(buildJob.Invocation.ExistingExecutionID)
		})

		s.aq.ExpectedCalls = nil
		s.aq.Calls = nil
		s.aq.On("Send", mock.Anything, jobMatcher).Return("jobID", nil)

		checkSuiteID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 12))

		s.ghtwirp.ExpectedCalls = nil

		s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
			switch globalID {
			case repoID.GlobalId, repoNextID.GlobalId:
				return types.GlobalID(repoNextID.GlobalId)
			case actorID.GlobalId, actorNextID.GlobalId:
				return types.GlobalID(actorNextID.GlobalId)
			default:
				s.FailNow("unexpected global id", "global id: %s", globalID)
				return ""
			}
		}, nil)

		s.ghtwirp.On("GetRepositoryOwners", mock.Anything, mock.Anything).
			Return(&ghtwirp.RepositoryOwners{
				Owner:    ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
				Business: &ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
			}, nil)
		s.ghtwirp.On("IsUserSpammy", mock.Anything, mock.Anything).Return(false, nil).Once()

		s.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return("{}", nil)

		s.ghClient.ExpectedCalls = nil

		s.ghClient.On("ResolveRef", mock.Anything, types.GlobalID(repoNextID.GlobalId), tc.ref).Return(commitSha, tc.resolvedRef, nil)

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		s.ghClient.On("CreateCheckSuite",
			mock.Anything,
			mock.Anything,
		).Return(&github.CreateCheckSuiteResponse{
			CheckSuiteIDPair: types.IDPair{
				DatabaseID: 12,
				GlobalID:   checkSuiteID,
			},
			WorkflowRun: &github.CheckSuiteWorkflowRun{
				DatabaseID: int64(14),
			},
		}, nil)

		res, err := s.svc.RunDynamicWorkflow(ctx, &pb.RunDynamicWorkflowRequest{
			RepositoryId:   repoID,
			InstallationId: 123,
			ActorId:        actorID,
			ActorLogin:     "monalisa",
			Workflow:       workflow,
			Ref:            tc.ref.String(),
			Inputs:         inputs,
			WorkflowName:   workflowName,
			Slug:           slug,
		})

		s.NoError(err)
		s.NotZero(res.GetExecutionId())
		s.Equal(int64(14), res.GetWorkflowRunId())
	}
}

func (s *RunDynamicWorkflowSuite) Test_DynamicRunOnSha() {
	const (
		workflow     = "on: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n    - run: echo"
		workflowName = "some-workflow"
		slug         = "some-slug"
		visibility   = githubv4.CheckSuiteVisibilityDefault
	)

	inputs := map[string]string{
		"foo": "bar",
	}

	validShaString := "fae17700da1efec77fdff0ccde490a84e9ae9305"

	testCases := []struct {
		name               string
		requestedShaString string
		expectedEventSha   types.CommitSha
		expectsError       bool
	}{
		{
			name:               "Valid SHA",
			requestedShaString: validShaString,
			expectedEventSha:   types.CommitSha(validShaString),
		},
		{
			name:               "Empty SHA",
			requestedShaString: "",
			expectedEventSha:   commitSha,
		},
		{
			name:               "Null SHA",
			requestedShaString: types.NullCommitSha.String(),
			expectsError:       true,
		},
		{
			name:               "Invalid SHA",
			requestedShaString: "zzz",
			expectsError:       true,
		},
	}

	for _, tc := range testCases {
		ctx := context.Background()

		s.aq.ExpectedCalls = nil
		s.aq.Calls = nil
		if !tc.expectsError {
			jobMatcher := mock.MatchedBy(func(aqJob aqueduct.Job) bool {
				var buildJob build.Job
				s.NoError(json.Unmarshal(aqJob.Payload, &buildJob))

				event := buildJob.Invocation.Event

				return s.Equal(tc.expectedEventSha, buildJob.Invocation.Event.Commit) &&
					s.Equal(flowevents.Dynamic, buildJob.Invocation.Event.Name) &&
					s.Equal(types.IdentityToGlobalID(ctx, repoNextID), buildJob.Invocation.Target.RepositoryID) &&
					s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.ExecutingActor.ID) &&
					s.Equal(types.IdentityToGlobalID(ctx, actorNextID), buildJob.Invocation.TriggeringActor.ID) &&
					s.Equal(branchRef, event.Ref) &&
					s.NotEmpty(buildJob.Invocation.ExistingExecutionID)
			})

			s.aq.On("Send", mock.Anything, jobMatcher).Return("jobID", nil)
		}

		checkSuiteID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 12))

		s.ghtwirp.ExpectedCalls = nil

		s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
			switch globalID {
			case repoID.GlobalId, repoNextID.GlobalId:
				return types.GlobalID(repoNextID.GlobalId)
			case actorID.GlobalId, actorNextID.GlobalId:
				return types.GlobalID(actorNextID.GlobalId)
			default:
				s.FailNow("unexpected global id", "global id: %s", globalID)
				return ""
			}
		}, nil)

		s.ghtwirp.On("GetRepositoryOwners", mock.Anything, mock.Anything).
			Return(&ghtwirp.RepositoryOwners{
				Owner:    ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
				Business: &ghtwirp.Entity{GlobalID: types.IdentityToGlobalID(ctx, actorID)},
			}, nil)
		s.ghtwirp.On("IsUserSpammy", mock.Anything, mock.Anything).Return(false, nil).Once()

		s.ghtwirp.On("GetRepositoryEventDetails", mock.Anything, repoDatabaseID).Return("{}", nil)

		s.ghClient.ExpectedCalls = nil

		s.ghClient.On("ResolveRef", mock.Anything, types.GlobalID(repoNextID.GlobalId), branchRef).Return(commitSha, branchRef, nil)

		s.ghClient.On("RepositoryNWO", mock.Anything, mock.AnythingOfType("types.GlobalID")).Return(types.RepositoryFullName{
			Owner: "monalisa",
			Name:  "some-repo",
		}, nil)

		s.ghClient.On("CreateCheckSuite",
			mock.Anything,
			mock.Anything,
		).Return(&github.CreateCheckSuiteResponse{
			CheckSuiteIDPair: types.IDPair{
				DatabaseID: 12,
				GlobalID:   checkSuiteID,
			},
			WorkflowRun: &github.CheckSuiteWorkflowRun{
				DatabaseID: int64(14),
			},
		}, nil)

		res, err := s.svc.RunDynamicWorkflow(ctx, &pb.RunDynamicWorkflowRequest{
			RepositoryId:   repoID,
			InstallationId: 123,
			ActorId:        actorID,
			ActorLogin:     "monalisa",
			Workflow:       workflow,
			Ref:            branchRef.String(),
			Inputs:         inputs,
			WorkflowName:   workflowName,
			Slug:           slug,
			Sha:            tc.requestedShaString,
		})

		if tc.expectsError {
			s.Error(err)
		} else {
			s.NoError(err)
			s.NotZero(res.GetExecutionId())
			s.Equal(int64(14), res.GetWorkflowRunId())
		}
	}
}

type mocks struct {
	aq       *aqueduct.MockClient
	ghclient *github.MockClient
	ghtwirp  *ghtwirp.MockClient
}

func newServiceWithMocks() (*service, *mocks) {
	mocks := &mocks{}

	ctx := context.WithValue(context.Background(), reqmeta.RMDContextKey, reqmeta.NewRequestMetadata())
	aq := &aqueduct.MockClient{}
	mocks.aq = aq

	ghClient := &github.MockClient{}
	mocks.ghclient = ghClient
	ghClient.On("ResolveRef", mock.Anything, types.IdentityToGlobalID(ctx, repoNextID), branchRef).Return(commitSha, branchRef, nil)

	ghClientFactory := &github.MockFactory{}
	ghClientFactory.On("NewClientForRepositoryOwnerDatabaseID", mock.Anything, mock.Anything, mock.Anything).Return(ghClient, nil)

	ghtwirp := &ghtwirp.MockClient{}
	mocks.ghtwirp = ghtwirp
	ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		switch globalID {
		case repoID.GlobalId, repoNextID.GlobalId:
			return types.GlobalID(repoNextID.GlobalId)
		case actorID.GlobalId, actorNextID.GlobalId:
			return types.GlobalID(actorNextID.GlobalId)
		default:
			return "UNKNOWN"
		}
	}, nil)

	migrator := deployer.NewGlobalIDMigrator(ghtwirp)

	svc := &service{
		cfg: config{
			Obs:                   observability.NewNullObservability(),
			AqueductClient:        aq,
			AqueductQueue:         queueName,
			ClientFactory:         ghClientFactory,
			Log:                   logger.TestLogger(),
			GithubTwirpClient:     ghtwirp,
			WorkflowSourceFactory: workflowinvoker.NullWorkflowSourceFactory{},
		},
		gidMigrator: migrator,
	}

	return svc, mocks
}
