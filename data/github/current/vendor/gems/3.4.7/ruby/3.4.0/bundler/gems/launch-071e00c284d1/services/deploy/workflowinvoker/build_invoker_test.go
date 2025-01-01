package workflowinvoker

import (
	"context"
	"encoding/base64"
	"encoding/json"
	goerr "errors"
	"fmt"
	"net/http"
	"reflect"
	"sort"
	"strconv"
	"testing"
	"time"

	githubgo "github.com/google/go-github/v25/github"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"

	parser "github.com/github/actions-workflow-parser/go"

	"github.com/github/launch/clients/earthsmoke"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	ghclient "github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/clients/runservice"
	"github.com/github/launch/clients/utils"
	"github.com/github/launch/clients/varz"
	"github.com/github/launch/config/customerlabels"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/model"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/observability/statter"
	azpclient "github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/rate"
	"github.com/github/launch/pkg/wfparser"
	"github.com/github/launch/services/auth/hkdf"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	launchutils "github.com/github/launch/utils"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild"
	"github.com/github/launch/workflowbuild/azp/azperrors"
	"github.com/github/launch/workflowbuild/build"
	"github.com/github/launch/workflowparser"

	checksv1 "github.com/github/actions-proto/gen/go/checks/v1"
	resultspb "github.com/github/actions-proto/gen/go/results/api/v1"
	runtwirpv1 "github.com/github/actions-proto/gen/go/run-service/api/twirp/v1"
)

var eventNameMap = map[reflect.Type]string{
	reflect.TypeOf(&flowevents.DynamicEvent{}):      "dynamic",
	reflect.TypeOf(&flowevents.ScheduleEvent{}):     "schedule",
	reflect.TypeOf(&flowevents.WorkflowCallEvent{}): "workflow_call",

	reflect.TypeOf(&githubgo.CreateEvent{}):       "create",
	reflect.TypeOf(&githubgo.DeleteEvent{}):       "delete",
	reflect.TypeOf(&githubgo.IssueEvent{}):        "issues",
	reflect.TypeOf(&githubgo.IssueCommentEvent{}): "issue_comment",
	reflect.TypeOf(&githubgo.GollumEvent{}):       "gollum",
	// Override the event name in the test if you want `pull_request_target` for PullRequestEvent
	reflect.TypeOf(&githubgo.PullRequestEvent{}):              "pull_request",
	reflect.TypeOf(&githubgo.PullRequestReviewEvent{}):        "pull_request_review",
	reflect.TypeOf(&githubgo.PullRequestReviewCommentEvent{}): "pull_request_review_comment",
	reflect.TypeOf(&githubgo.PushEvent{}):                     "push",
}

// see setupSecretStoreMocks
var actionsDecryptedSecrets = map[string]string{
	"ACTIONS_SECRET_ONE": "one",
	"ACTIONS_SECRET_TWO": "two",
}
var dependabotDecryptedSecrets = map[string]string{
	"DEPENDABOT_SECRET_ONE": "dependabot_one",
	"DEPENDABOT_SECRET_TWO": "dependabot_two",
}

type buildInvokerTest struct {
	suite.Suite
	invoker *buildInvoker

	recordingLogger testutils.RecordingLogger

	wfb              *build.WorkflowBuild
	azpClient        *azpclient.MockRepositoryClient
	kredzClient      *kredz.MockClient
	varzClient       *varz.MockClient
	repo             *deployer.MockWorkflowBuildsRepository
	mockEmitter      *slometrics.MockHydroEmitter
	decryptor        *earthsmoke.MockDecryptor
	ghtwirp          *ghtwirp.MockClient
	runServiceClient *runservice.MockClient
	resultsClient    *results.MockClient
}

func TestBuildInvoker(t *testing.T) {
	suite.Run(t, new(buildInvokerTest))
}

func (s *buildInvokerTest) SetupTest() {
	testutils.SetAppMode(s.T(), launchconfig.EnterpriseAppMode)
	s.wfb = &build.WorkflowBuild{
		Event:            flowevents.Push,
		GitHubEvent:      &githubgo.PushEvent{},
		WorkflowFilePath: ".github/workflows/main.yml",
		RootWorkflow: build.RootWorkflow{
			FilePath: ".github/workflows/main.yml",
		},
		ResolvedFiles: []types.ResolvedFile{
			{
				Path: ".github/workflows/main.yml",
			},
		},
	}

	s.azpClient = &azpclient.MockRepositoryClient{}

	filter := &workflowbuild.MockWorkflowFilter{}
	filter.On("ShouldRun", mock.Anything, mock.Anything).Return(true)

	emitter := &slometrics.MockHydroEmitter{}
	s.mockEmitter = emitter

	repo := &deployer.MockWorkflowBuildsRepository{}
	s.repo = repo
	s.recordingLogger = testutils.NewRecordingLogger()

	mockTokenFactory := &workflowbuild.MockTokenFactory{}
	mockTokenFactory.On(
		"CalculateRunPermissions", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything,
	).Return(&tokens.PermissionSettings{}, nil)

	s.runServiceClient = &runservice.MockClient{}
	s.resultsClient = &results.MockClient{}
	s.ghtwirp = &ghtwirp.MockClient{}

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceProximaFeatureFlag, mock.Anything).Return(false).Maybe()

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.BlockArtifactsV3Exempted, mock.Anything).Return(false).Maybe()
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.OptOutOfCacheServiceV2, mock.Anything).Return(false).Maybe()

	urlProviderFactory, err := utils.TestURLProviderFactoryWithDefaults()
	if err != nil {
		s.FailNowf("error creating url provider for build invoker", "%v", err)
	}

	s.invoker = &buildInvoker{
		obs:              NewTestObservability(observability.New(s.recordingLogger.Logger, statter.NullStatter())),
		azpClient:        s.azpClient,
		workflowMetadata: &metadata.WorkflowMetadata{},
		ghClient:         &ghclient.MockClient{},
		ghTwirpClient:    s.ghtwirp,
		data: &types.WorkflowInvocationData{
			PlanOwner: types.WorkflowInvocationPlanOwner{
				GlobalID: "E_kgAB", // global ID for github-inc (databaseID: 1)
			},
			AllowsAllActions: true,
		},
		invocation:            Invocation{},
		outcome:               deployer.OrgCreationSuccess,
		filter:                filter,
		repo:                  repo,
		repositoryTenants:     &types.RepositoryTenants{},
		tokenFactory:          mockTokenFactory,
		actionsAppGlobalID:    "actions-app-global-id",
		dependabotAppGlobalID: "dependabot-app-global-id",
		kredzClient:           &kredz.MockClient{},
		secretDecryptor:       &earthsmoke.MockDecryptor{},
		keyGenerator:          hkdf.NewKeyGenerator([]byte{}),
		receiverURL:           "example.com",
		resultsReceiverURL:    "example.com/results",
		errorHandler:          nil,
		workflowSource:        workflowparser.NullWorkflowSource{},
		urlProviderFactory:    urlProviderFactory,
		reporter:              slometrics.New(emitter),
		labeler:               customerlabels.NewNoopCustomerLabeler(),
		queueBuildRateLimiter: &rate.NullRateLimiter{},
		webhookRateLimiter:    &rate.NullRateLimiter{},
		resultsClient:         s.resultsClient,
	}
}

func (s *buildInvokerTest) TestValidatesActionsPolicyWithTwirp() {
	ctx := context.Background()

	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}
	s.ghtwirp.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)

	// Set AllowsAllActions to false so we hit policy endpoint
	s.invoker.data.AllowsAllActions = false
	s.invoker.data.RepoGlobalID = "fakeId"

	workflow := `
on: push
name: "simple"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`

	wf, _ := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "main.yml"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	res := s.invoker.ActionsAllowedByPolicy(ctx, NewBuildStartErrContext(wf.Path, wf.Name, s.invoker.invocation, s.invoker.data, "", ""), "fakeid", wf)
	s.Nil(res)
	s.ghtwirp.AssertExpectations(s.T())
}

func (s *buildInvokerTest) TestValidatesWorkflowsPolicyWithTwirp() {
	ctx := context.Background()

	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	workflowsPolicyInfo := &ghtwirp.WorkflowsPolicyInfo{
		IsExecutionAllowed: true,
	}
	wfPaths := map[string]bool{
		"owner/repo/.github/workflows/build.yml@master":           true,
		"owner/repo/.github/workflows/build2.yml@master":          true,
		"owner4/repo2/.github/workflows/build.yml@testSHAasdf123": true,
	}
	validateInputPaths := func(paths []string) bool {
		for _, path := range paths {
			if _, ok := wfPaths[path]; !ok {
				return false
			}
		}
		return true
	}
	s.ghtwirp.On("CheckWorkflowsAllowedByPolicy", mock.Anything, mock.Anything, mock.MatchedBy(validateInputPaths), false).Return(workflowsPolicyInfo, nil)

	// Set AllowsAllActions to false so we hit policy endpoint
	s.invoker.data.AllowsAllActions = false
	s.invoker.data.RepoGlobalID = "fakeId"

	workflow := `
on: push
name: "simple"
jobs:
  calling-local:
    uses: ./.github/workflows/build.yml
  calling:
    uses: owner/repo/.github/workflows/build.yml@master
  calling2:
    uses: owner/repo/.github/workflows/build.yml@master
  calling3:
    uses: owner/repo/.github/workflows/build2.yml@master`

	wfs := &workflowparser.StubWorkflowSource{
		SourceMap: map[string]workflowparser.WorkflowDetails{
			"owner/repo/.github/workflows/build.yml@master": {
				Content: "on:\n  workflow_call:\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				RefType: "refs/heads/",
			},
			"owner/repo/.github/workflows/build2.yml@master": {
				Content: "on:\n  workflow_call:\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				RefType: "refs/heads/",
			},
			"owner4/repo2/.github/workflows/build.yml@testSHAasdf123": {
				Content: "on:\n  workflow_call:\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
			},
		},
		CallerRepoID: "R_kgAw",
		CallerRepoNWO: types.RepositoryFullName{
			Owner: "owner4",
			Name:  "repo2",
		},
		CallerRepoSHA: "testSHAasdf123",
	}
	wf, _ := workflowparser.ParseWithCalledWorkflows(ctx, types.ResolvedFile{Text: workflow, Path: "main.yml"}, types.WorkflowFeatureFlags{}, wfs, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	res := s.invoker.WorkflowsAllowedByPolicy(ctx, NewBuildStartErrContext(wf.Path, wf.Name, s.invoker.invocation, s.invoker.data, "", ""), "fakeid", wf, wf.CalledWorkflows)
	s.Nil(res)
	s.ghtwirp.AssertExpectations(s.T())
}

func (s *buildInvokerTest) TestValidatesActionsPolicyWithTwirpForRequiredWorkflows() {
	ctx := context.Background()

	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}
	s.ghtwirp.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, true).Return(actionsPolicyInfo, nil)

	// Set AllowsAllActions to false so we hit policy endpoint
	s.invoker.data.AllowsAllActions = false
	s.invoker.data.RepoGlobalID = "fakeId"

	workflow := `
on: push
name: "simple"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`

	wf, _ := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "required/123/test.yml", SHA: "7385e4b18473d3f8daa525da1ec7512868582cad"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	res := s.invoker.ActionsAllowedByPolicy(ctx, NewBuildStartErrContext(wf.Path, wf.Name, s.invoker.invocation, s.invoker.data, types.CommitSha(wf.File.SHA), ""), "fakeid", wf)
	s.Nil(res)
	s.ghtwirp.AssertExpectations(s.T())
}

func (s *buildInvokerTest) TestValidatesWorkflowsPolicyWithTwirpForRequiredWorkflows() {
	ctx := context.Background()

	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	workflowsPolicyInfo := &ghtwirp.WorkflowsPolicyInfo{
		IsExecutionAllowed: true,
	}
	wfPaths := map[string]bool{
		"owner/repo/.github/workflows/build.yml@master":           true,
		"owner/repo/.github/workflows/build2.yml@master":          true,
		"owner4/repo2/.github/workflows/build.yml@testSHAasdf123": true,
	}
	validateInputPaths := func(paths []string) bool {
		for _, path := range paths {
			if _, ok := wfPaths[path]; !ok {
				return false
			}
		}
		return true
	}
	s.ghtwirp.On("CheckWorkflowsAllowedByPolicy", mock.Anything, mock.Anything, mock.MatchedBy(validateInputPaths), true).Return(workflowsPolicyInfo, nil)

	// Set AllowsAllActions to false so we hit policy endpoint
	s.invoker.data.AllowsAllActions = false
	s.invoker.data.RepoGlobalID = "fakeId"

	workflow := `
on: push
name: "simple"
jobs:
  calling-local:
    uses: ./.github/workflows/build.yml
  calling:
    uses: owner/repo/.github/workflows/build.yml@master
  calling2:
    uses: owner/repo/.github/workflows/build.yml@master
  calling3:
    uses: owner/repo/.github/workflows/build2.yml@master`

	wfs := &workflowparser.StubWorkflowSource{
		SourceMap: map[string]workflowparser.WorkflowDetails{
			"owner/repo/.github/workflows/build.yml@master": {
				Content: "on:\n  workflow_call:\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				RefType: "refs/heads/",
			},
			"owner/repo/.github/workflows/build2.yml@master": {
				Content: "on:\n  workflow_call:\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				RefType: "refs/heads/",
			},
			"owner4/repo2/.github/workflows/build.yml@testSHAasdf123": {
				Content: "on:\n  workflow_call:\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
			},
		},
		CallerRepoID: "R_kgAw",
		CallerRepoNWO: types.RepositoryFullName{
			Owner: "owner4",
			Name:  "repo2",
		},
		CallerRepoSHA: "testSHAasdf123",
	}
	wf, _ := workflowparser.ParseWithCalledWorkflows(ctx, types.ResolvedFile{Text: workflow, Path: "required/1234/main.yml", SHA: "7385e4b18473d3f8daa525da1ec7512868582cad"}, types.WorkflowFeatureFlags{}, wfs, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	res := s.invoker.WorkflowsAllowedByPolicy(ctx, NewBuildStartErrContext(wf.Path, wf.Name, s.invoker.invocation, s.invoker.data, types.CommitSha(wf.File.SHA), ""), "fakeid", wf, wf.CalledWorkflows)
	s.Nil(res)
	s.ghtwirp.AssertExpectations(s.T())
}

func (s *buildInvokerTest) TestIfActionsAllowedByLaunchForRequiredWorkflows_Disallowed() {
	ctx := context.Background()
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler
	workflow := `
on: push
name: "simple"
jobs:
  action-1:
    steps:
    - uses: owner/repo@master
  action-2:
    steps:
    - uses: github/codeql-action/init@v1
  action-3:
    steps:
    - uses: github/codeql-action/autobuild@v2
  action-4:
    steps:
    - uses: github/codeql-action/analyze@main
  action-5:
    steps:
    - uses: github/codeql-action/upload-sarif@936cd8cad458e56910e6480bf786f930f0a5ebe9`

	wf, _ := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "required/123/test.yml", SHA: "7385e4b18473d3f8daa525da1ec7512868582cad"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	res := s.invoker.CheckIfActionsAllowedByLaunch(ctx, NewBuildStartErrContext(wf.Path, wf.Name, s.invoker.invocation, s.invoker.data, types.CommitSha(wf.File.SHA), ""), wf)
	s.Error(res)

	// github/codeql-action/upload-sarif is allowed
	s.Equal(res.stepErr.Error(), "The following actions are not allowed to be used inside a required workflow: github/codeql-action/analyze@main, github/codeql-action/autobuild@v2, github/codeql-action/init@v1")
}

func (s *buildInvokerTest) TestIfActionsAllowedByLaunchForRequiredWorkflows_Allowed() {
	ctx := context.Background()
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	workflow := `
on: push
name: "simple"
jobs:
  action-1:
    steps:
    - uses: owner/repo@master
  action-2:
    steps:
    - uses: github/sample-action@v1
  action-3:
    steps:
    - uses: actions/checkout-action@v2
  action-4:
    steps:
    - uses: github/codeql-action-new-allowed-version@main
  action-5:
    steps:
    - uses: anothergithub/codeql-action/upload-sarif@936cd8cad458e56910e6480bf786f930f0a5ebe9`

	wf, _ := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "required/123/test.yml", SHA: "7385e4b18473d3f8daa525da1ec7512868582cad"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	res := s.invoker.CheckIfActionsAllowedByLaunch(ctx, NewBuildStartErrContext(wf.Path, wf.Name, s.invoker.invocation, s.invoker.data, types.CommitSha(wf.File.SHA), ""), wf)
	s.Nil(res)
}

func (s *buildInvokerTest) TestIsCustomImageGenerationAllowedByPolicyOnGHES_Disallowed() {
	ctx := context.Background()
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	s.invoker.isEnterprise = true
	s.invoker.data.Owner.Type = ownerTypeOrganisation
	s.invoker.data.HasHostedRunnerCustomImagesEnabled = true
	s.invoker.data.WorkflowFeatureFlags = types.WorkflowFeatureFlags{
		CustomImagesPolicyEnforced: true,
	}

	workflow := `
on: push
name: "simple"
jobs:
  action-1:
    snapshot: customImageName
    steps:
    - uses: owner/repo@master`

	wf, wfErr := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "required/123/test.yml", SHA: "7385e4b18473d3f8daa525da1ec7512868582cad"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	s.Nil(wfErr)

	res := s.invoker.IsCustomImageGenerationAllowedByPolicy(ctx, NewBuildStartErrContext(wf.Path, wf.Name, s.invoker.invocation, s.invoker.data, types.CommitSha(wf.File.SHA), ""), wf)

	s.Error(res)
	s.Equal(res.stepErr.Error(), "`snapshot` is not supported.")
}

func (s *buildInvokerTest) TestIsCustomImageGenerationAllowedByPolicyNonOrgOwner_Disallowed() {
	ctx := context.Background()
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	s.invoker.data.Owner.Type = "User"
	s.invoker.data.HasHostedRunnerCustomImagesEnabled = true
	s.invoker.data.WorkflowFeatureFlags = types.WorkflowFeatureFlags{
		CustomImagesPolicyEnforced: true,
	}

	workflow := `
on: push
name: "simple"
jobs:
  action-1:
    snapshot: customImageName
    steps:
    - uses: owner/repo@master`

	wf, wfErr := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "required/123/test.yml", SHA: "7385e4b18473d3f8daa525da1ec7512868582cad"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	s.Nil(wfErr)

	res := s.invoker.IsCustomImageGenerationAllowedByPolicy(ctx, NewBuildStartErrContext(wf.Path, wf.Name, s.invoker.invocation, s.invoker.data, types.CommitSha(wf.File.SHA), ""), wf)

	s.Error(res)
	s.Equal(res.stepErr.Error(), "`snapshot` is not supported for personal repositories.")
}

func (s *buildInvokerTest) TestIsCustomImageGenerationAllowedByPolicy_Disallowed() {
	testCases := []struct {
		flagEnabled     bool
		policyAllowed   bool
		snapshotPresent bool
		desc            string
		expectedAllowed bool
	}{
		{false, false, false, "nothing enabled", true},
		{false, false, true, "snapshot present, nothing enabled", true},
		{false, true, false, "policy enabled, no snapshot", true},
		{false, true, true, "policy enabled, snapshot present, flag not enabled", true},
		{true, false, false, "flag enabled, no snapshot", true},
		{true, false, true, "flag enabled, snapshot present, policy not enabled", false},
		{true, true, false, "flag enabled, policy enabled, no snapshot", true},
		{true, true, true, "flag enabled, snapshot present, policy enabled", true},
	}

	for _, tc := range testCases {
		s.Run(tc.desc, func() {
			ctx := context.Background()
			mockErrorHandler := &MockWorkflowStartErrHandler{}
			mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
			s.invoker.errorHandler = mockErrorHandler

			s.invoker.data.Owner.Type = ownerTypeOrganisation
			s.invoker.data.HasHostedRunnerCustomImagesEnabled = tc.policyAllowed
			s.invoker.data.WorkflowFeatureFlags = types.WorkflowFeatureFlags{
				CustomImagesPolicyEnforced: tc.flagEnabled,
			}

			snapshotDirective := ""
			if tc.snapshotPresent {
				snapshotDirective = "snapshot: customImageName"
			}
			workflow := fmt.Sprintf(`
on: push
name: "simple"
jobs:
  action-1:
    %s
    steps:
    - uses: owner/repo@master`, snapshotDirective)

			wf, wfErr := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "required/123/test.yml", SHA: "7385e4b18473d3f8daa525da1ec7512868582cad"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
			s.Nil(wfErr)

			res := s.invoker.IsCustomImageGenerationAllowedByPolicy(ctx, NewBuildStartErrContext(wf.Path, wf.Name, s.invoker.invocation, s.invoker.data, types.CommitSha(wf.File.SHA), ""), wf)

			if tc.expectedAllowed {
				s.Nil(res)
			} else {
				s.Error(res)
				s.Equal(res.stepErr.Error(), "The workflow contains `snapshot` but the organization is not allowed to create custom images.")
			}
		})
	}
}

func (s *buildInvokerTest) TestValidatesWorkflowsPolicyWithTwirpOmittedNWO() {
	ctx := context.Background()
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	s.ghtwirp.AssertNotCalled(s.T(), "CheckWorkflowsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false)

	// Set AllowsAllActions to false so we hit policy endpoint
	s.invoker.data.AllowsAllActions = false
	s.invoker.data.RepoGlobalID = "fakeId"
	calledWorkflows := map[string]workflowparser.CalledWorkflow{
		"uses": {
			Workflow: workflowparser.Workflow{
				Path: "./.github/workflows/build.yml",
			},
		},
	}
	wf := &workflowparser.Workflow{}
	res := s.invoker.WorkflowsAllowedByPolicy(ctx, NewBuildStartErrContext("main.yml", "simple", s.invoker.invocation, s.invoker.data, "", ""), "fakeid", wf, calledWorkflows)
	s.Error(res)
	s.ghtwirp.AssertExpectations(s.T())
}

func (s *buildInvokerTest) TestDoesNotHitTwirpforAllAllowed() {
	ctx := context.Background()
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	// When set to AllowsAllActions, we don't hit twirp because it's unnecessary
	s.invoker.data.AllowsAllActions = true
	s.invoker.data.RepoGlobalID = "fakeId"

	s.ghtwirp.AssertNotCalled(s.T(), "CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.ghtwirp.AssertNotCalled(s.T(), "CheckWorkflowsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, mock.Anything)

	workflow := `
on: push
name: "simple"
jobs:
  calling:
    uses: owner/repo/.github/workflows/ci.yml@master
  thing:
    steps:
    - uses: owner/repo@master`

	workflowFile := types.ResolvedFile{Text: workflow, Path: "main.yml"}
	wfs := &workflowparser.StubWorkflowSource{
		SourceMap: map[string]workflowparser.WorkflowDetails{
			"owner/repo/.github/workflows/ci.yml@master": {
				Content: "on:\n  workflow_call:\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				RefType: "refs/heads/",
			},
		}}
	wf, _ := workflowparser.ParseWithCalledWorkflows(ctx, workflowFile, types.WorkflowFeatureFlags{}, wfs, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	res := s.invoker.ActionsAllowedByPolicy(context.Background(), NewBuildStartErrContext(wf.Path, wf.Name, s.invoker.invocation, s.invoker.data, "", ""), "fakeid", wf)
	s.Nil(res)

	res = s.invoker.WorkflowsAllowedByPolicy(ctx, NewBuildStartErrContext(wf.Path, wf.Name, s.invoker.invocation, s.invoker.data, "", ""), "fakeid", wf, wf.CalledWorkflows)
	s.Nil(res)

	s.ghtwirp.AssertExpectations(s.T())
}

func (s *buildInvokerTest) Test_TransitionToNeverStartedWhenFinalAttempt() {
	s.repo.EXPECT().TransitionTo(mock.Anything, mock.Anything, mock.Anything).Return(true, nil)

	// Return error when queuing
	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("Queue", mock.Anything, s.wfb, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, goerr.New("build error"))
	s.invoker.azpClient = s.azpClient

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)

	ss := s.getSecretStore(s.wfb)
	vm := s.getVariables()
	err := s.invoker.queueBuild(context.Background(), s.wfb, ss, vm, 0, true, nil, nil, nil, nil)

	s.Error(err)
	s.repo.AssertCalled(s.T(), "TransitionTo", mock.Anything, mock.Anything, build.WorkflowStateNeverStarted, mock.Anything)
}

func (s *buildInvokerTest) Test_GHESRateLimit() {
	mockLimiter := &rate.MockRateLimiter{}
	mockLimiter.On("Allow", mock.Anything, mock.Anything).Return(false)
	s.invoker.queueBuildRateLimiter = mockLimiter
	s.invoker.isEnterprise = true
	ss := s.getSecretStore(s.wfb)
	vm := s.getVariables()

	err := s.invoker.queueBuild(context.Background(), s.wfb, ss, vm, 0, true, nil, nil, nil, nil)

	s.Error(err)
}

func (s *buildInvokerTest) Test_RateLimitingQueueBuilds() {
	mockLimiter := &rate.MockRateLimiter{}
	mockLimiter.On("Allow", mock.Anything, mock.Anything).Return(false)
	s.invoker.queueBuildRateLimiter = mockLimiter
	ss := s.getSecretStore(s.wfb)
	vm := s.getVariables()

	err := s.invoker.queueBuild(context.Background(), s.wfb, ss, vm, 0, true, nil, nil, nil, nil)

	s.Error(err)
}

func (s *buildInvokerTest) Test_TransitionToNeverStartedUnlessFinalAttempt() {
	// Return error when queuing
	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("Queue", mock.Anything, s.wfb, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, goerr.New("build error"))
	s.invoker.azpClient = s.azpClient

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)

	ss := s.getSecretStore(s.wfb)
	vm := s.getVariables()
	err := s.invoker.queueBuild(context.Background(), s.wfb, ss, vm, 0, false, nil, nil, nil, nil)

	s.Error(err)
	s.repo.AssertNotCalled(s.T(), "TransitionTo", mock.Anything, mock.Anything, build.WorkflowStateNeverStarted, mock.Anything)
}

func (s *buildInvokerTest) Test_QueueRunThroughRunServiceWhenFFEnabled() {
	s.wfb.Backend = types.WorkflowBackendRunService
	runStampURL := "https://run-service.github.app"
	s.runServiceClient.On("StartPlan", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(uuid.NewString(), runStampURL, nil).Once()
	s.invoker.runServiceClient = s.runServiceClient

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("UpdateWorkflowRunExecution", mock.Anything, mock.Anything, mock.Anything, runStampURL).Return(nil)

	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil).Once()
	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()

	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("GetRunTenantInfo").Return(&runtwirpv1.TenantInfo{
		Id: "tenant_abc",
		Urls: map[string]string{
			"PipelinesServiceUrl": "https://pipelines.example.com",
			"CacheServiceUrl":     "https://cache.example.com",
		},
	})
	s.invoker.azpClient = s.azpClient

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	s.invoker.data.PipelineFiles = []types.ResolvedFile{file.File}
	ss := s.getSecretStore(s.wfb)
	vm := s.getVariables()
	s.invoker.appEnv = launchconfig.DevelopmentAppEnv
	testutils.SetAppMode(s.T(), launchconfig.HostedAppMode)

	err := s.invoker.queueBuild(context.Background(), s.wfb, ss, vm, 0, false, nil, nil, nil, nil)
	s.NoError(err)
	s.mockEmitter.AssertExpectations(s.T())
}

func (s *buildInvokerTest) Test_FourNinesFullReruns() {
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)

	runStampURL := "https://run-service.github.app"
	s.runServiceClient.On("StartPlan", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(executionID.String(), runStampURL, nil).Once()
	s.invoker.runServiceClient = s.runServiceClient

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("UpdateWorkflowRunExecution", mock.Anything, mock.Anything, mock.Anything, runStampURL).Return(nil)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)

	s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
		return in.RepositoryID == repoID &&
			in.PlanID == executionID &&
			in.Attempt == attemptNum
	})).Return(nil)

	s.invoker.ghTwirpClient = s.ghtwirp

	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum, Backend: types.WorkflowBackendRunService}, nil)
	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil)

	s.resultsClient.On("GetWorkflowRunState", mock.Anything, mock.Anything).Return(&resultspb.GetWorkflowRunStateResponse{
		Status:      checksv1.Status_STATUS_COMPLETED,
		CompletedAt: timestamppb.New(time.Now()),
	}, nil)
	s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, "").Return(nil).Once()

	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	s.invoker.invocation.ExistingCheckSuite = &types.CheckSuiteState{
		RepositoryID: repoID,
		CheckSuiteIDPair: types.IDPair{
			GlobalID: types.GlobalID(checkSuiteNodeID),
		},
		ExecutionID: executionID,
		Backend:     types.WorkflowBackendRunService,
	}
	s.invoker.data.PipelineFiles = []types.ResolvedFile{file.File}
	s.invoker.appEnv = launchconfig.DevelopmentAppEnv
	testutils.SetAppMode(s.T(), launchconfig.HostedAppMode)

	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("GetRunTenantInfo").Return(&runtwirpv1.TenantInfo{
		Id: "tenant_abc",
		Urls: map[string]string{
			"PipelinesServiceUrl": "https://pipelines.example.com",
			"CacheServiceUrl":     "https://cache.example.com",
		},
	})
	s.invoker.azpClient = s.azpClient

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
	s.ghtwirp.AssertExpectations(s.T())
	s.repo.AssertExpectations(s.T())
	s.runServiceClient.AssertExpectations(s.T())
	s.resultsClient.AssertExpectations(s.T())
	s.mockEmitter.AssertExpectations(s.T())
	mockErrorHandler.AssertExpectations(s.T())
}

func (s *buildInvokerTest) Test_FourNinesPartialReruns() {
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)
	previousPlanId := uuid.New()

	runStampURL := "https://run-service.github.app"
	s.runServiceClient.On("StartPlan", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(executionID.String(), runStampURL, nil).Once()
	s.invoker.runServiceClient = s.runServiceClient

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("UpdateWorkflowRunExecution", mock.Anything, mock.Anything, mock.Anything, runStampURL).Return(nil)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
	s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
		return in.RepositoryID == repoID &&
			in.PlanID == executionID &&
			in.Attempt == attemptNum
	})).Return(nil)

	s.invoker.ghTwirpClient = s.ghtwirp

	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum, Backend: types.WorkflowBackendRunService}, nil)
	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil)

	s.resultsClient.On("GetWorkflowRunState", mock.Anything, mock.Anything).Return(&resultspb.GetWorkflowRunStateResponse{
		Status:      checksv1.Status_STATUS_COMPLETED,
		CompletedAt: timestamppb.New(time.Now()),
	}, nil)
	s.resultsClient.On("GetWorkflowOrchestrationContexts", mock.Anything, types.WorkflowExecutionID(previousPlanId)).Return([]string{"context_1", "context_2"}, nil)
	s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, previousPlanId.String()).Return(nil).Once()

	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	s.invoker.invocation.ExistingCheckSuite = &types.CheckSuiteState{
		RepositoryID: repoID,
		CheckSuiteIDPair: types.IDPair{
			GlobalID: types.GlobalID(checkSuiteNodeID),
		},
		Backend: types.WorkflowBackendRunService,
	}
	s.invoker.invocation.RerunInfo = &types.RerunInfo{
		PlanID: previousPlanId.String(),
		JobIDs: types.JobIDs{"a-job-id"},
	}

	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("GetRunTenantInfo").Return(&runtwirpv1.TenantInfo{
		Id: "tenant_abc",
		Urls: map[string]string{
			"PipelinesServiceUrl": "https://pipelines.example.com",
			"CacheServiceUrl":     "https://cache.example.com",
		},
	})
	s.invoker.azpClient = s.azpClient

	s.invoker.data.PipelineFiles = []types.ResolvedFile{file.File}
	s.invoker.appEnv = launchconfig.DevelopmentAppEnv
	testutils.SetAppMode(s.T(), launchconfig.HostedAppMode)

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
	s.ghtwirp.AssertExpectations(s.T())
	s.repo.AssertExpectations(s.T())
	s.runServiceClient.AssertExpectations(s.T())
	s.resultsClient.AssertExpectations(s.T())
	s.mockEmitter.AssertExpectations(s.T())
	mockErrorHandler.AssertExpectations(s.T())
}

func (s *buildInvokerTest) Test_PartialRerunsUseSameBackend() {
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)
	previousPlanId := uuid.New()

	runStampURL := "https://run-service.github.app"
	s.runServiceClient.On("StartPlan", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(executionID.String(), runStampURL, nil).Once()
	s.invoker.runServiceClient = s.runServiceClient

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false) // partial rerun should go to 4-nines even feature flag is disabled
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlagForHardCodedHostedLabels, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("UpdateWorkflowRunExecution", mock.Anything, mock.Anything, mock.Anything, runStampURL).Return(nil)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
	s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
		return in.RepositoryID == repoID &&
			in.PlanID == executionID &&
			in.Attempt == attemptNum
	})).Return(nil)

	s.invoker.ghTwirpClient = s.ghtwirp

	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Run(func(_ context.Context, _ types.GlobalID, b *build.WorkflowBuild, _ *tokens.PermissionSettings, _ *metadata.WorkflowMetadata, _ types.GlobalID, _ bool) {
			s.Assert().Equal(types.WorkflowBackendRunService, b.Backend)
		}).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum, Backend: types.WorkflowBackendRunService}, nil)
	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil)

	s.resultsClient.On("GetWorkflowRunState", mock.Anything, mock.Anything).Return(&resultspb.GetWorkflowRunStateResponse{
		Status:      checksv1.Status_STATUS_COMPLETED,
		CompletedAt: timestamppb.New(time.Now()),
	}, nil)
	s.resultsClient.On("GetWorkflowOrchestrationContexts", mock.Anything, types.WorkflowExecutionID(previousPlanId)).Return([]string{"context_1", "context_2"}, nil)
	s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, previousPlanId.String()).Return(nil).Once()

	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	s.invoker.invocation.ExistingCheckSuite = &types.CheckSuiteState{
		RepositoryID: repoID,
		CheckSuiteIDPair: types.IDPair{
			GlobalID: types.GlobalID(checkSuiteNodeID),
		},
		Backend: types.WorkflowBackendRunService,
	}
	s.invoker.invocation.RerunInfo = &types.RerunInfo{
		PlanID: previousPlanId.String(),
		JobIDs: types.JobIDs{"a-job-id"},
	}

	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("GetRunTenantInfo").Return(&runtwirpv1.TenantInfo{
		Id: "tenant_abc",
		Urls: map[string]string{
			"PipelinesServiceUrl": "https://pipelines.example.com",
			"CacheServiceUrl":     "https://cache.example.com",
		},
	})
	s.invoker.azpClient = s.azpClient

	s.invoker.data.PipelineFiles = []types.ResolvedFile{file.File}
	s.invoker.appEnv = launchconfig.DevelopmentAppEnv
	testutils.SetAppMode(s.T(), launchconfig.HostedAppMode)

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
	s.ghtwirp.AssertExpectations(s.T())
	s.repo.AssertExpectations(s.T())
	s.runServiceClient.AssertExpectations(s.T())
	s.resultsClient.AssertExpectations(s.T())
	s.mockEmitter.AssertExpectations(s.T())
	mockErrorHandler.AssertExpectations(s.T())
}

func (s *buildInvokerTest) Test_QueueRunThroughRunService_TenantInfoWithoutEnterprise() {
	s.wfb.Backend = types.WorkflowBackendRunService
	s.wfb.ActionsBillingPlanOwner = build.ActionsBillingPlanOwner{
		TenantID:  "org_tenant_id",
		TenantURL: "https://pipelines.com/org_tenant",
	}
	runStampURL := "https://run-service.github.app"

	expectedRepoTenantInfo := &types.RepositoryTenantInfo{
		RepoTenantInfo: &runtwirpv1.TenantInfo{
			Id: "tenant_abc",
			Urls: map[string]string{
				"PipelinesService": "https://pipelines.example.com",
			},
		},
		OwnerTenantInfo: &runtwirpv1.TenantInfo{
			Id: "org_tenant_id",
			Urls: map[string]string{
				"PipelinesService": "https://pipelines.com/org_tenant",
			},
		},
	}

	s.runServiceClient.On("StartPlan", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, expectedRepoTenantInfo, mock.Anything, mock.Anything).
		Return(uuid.NewString(), runStampURL, nil).Once()
	s.invoker.runServiceClient = s.runServiceClient

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("UpdateWorkflowRunExecution", mock.Anything, mock.Anything, mock.Anything, runStampURL).Return(nil)

	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil).Once()
	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()

	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("GetRunTenantInfo").Return(&runtwirpv1.TenantInfo{
		Id: "tenant_abc",
		Urls: map[string]string{
			"PipelinesService": "https://pipelines.example.com",
		},
	})
	s.invoker.azpClient = s.azpClient

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	s.invoker.data.PipelineFiles = []types.ResolvedFile{file.File}
	ss := s.getSecretStore(s.wfb)
	vm := s.getVariables()
	s.invoker.appEnv = launchconfig.DevelopmentAppEnv
	testutils.SetAppMode(s.T(), launchconfig.HostedAppMode)

	err := s.invoker.queueBuild(context.Background(), s.wfb, ss, vm, 0, false, nil, nil, nil, nil)
	s.NoError(err)
	s.mockEmitter.AssertExpectations(s.T())
}

func (s *buildInvokerTest) Test_QueueRunThroughRunService_TenantInfoWithEnterprise() {
	s.wfb.Backend = types.WorkflowBackendRunService
	s.wfb.ActionsBillingPlanOwner = build.ActionsBillingPlanOwner{
		Type:                  "Business",
		TenantID:              "enterprise_tenant_id",
		TenantURL:             "https://pipelines.com/enterprise_tenant",
		OrganizationTenantID:  "org_tenant_id",
		OrganizationTenantURL: "https://pipelines.com/org_tenant",
	}
	runStampURL := "https://run-service.github.app"

	expectedRepoTenantInfo := &types.RepositoryTenantInfo{
		RepoTenantInfo: &runtwirpv1.TenantInfo{
			Id: "tenant_abc",
			Urls: map[string]string{
				"PipelinesService": "https://pipelines.example.com",
			},
		},
		OwnerTenantInfo: &runtwirpv1.TenantInfo{
			Id: "org_tenant_id",
			Urls: map[string]string{
				"PipelinesService": "https://pipelines.com/org_tenant",
			},
		},
		EnterpriseTenantInfo: &runtwirpv1.TenantInfo{
			Id: "enterprise_tenant_id",
			Urls: map[string]string{
				"PipelinesService": "https://pipelines.com/enterprise_tenant",
			},
		},
	}

	s.runServiceClient.On("StartPlan", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, expectedRepoTenantInfo, mock.Anything, mock.Anything).
		Return(uuid.NewString(), runStampURL, nil).Once()
	s.invoker.runServiceClient = s.runServiceClient

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("UpdateWorkflowRunExecution", mock.Anything, mock.Anything, mock.Anything, runStampURL).Return(nil)

	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil).Once()
	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()

	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("GetRunTenantInfo").Return(&runtwirpv1.TenantInfo{
		Id: "tenant_abc",
		Urls: map[string]string{
			"PipelinesService": "https://pipelines.example.com",
		},
	})
	s.invoker.azpClient = s.azpClient

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	s.invoker.data.PipelineFiles = []types.ResolvedFile{file.File}
	ss := s.getSecretStore(s.wfb)
	vm := s.getVariables()
	s.invoker.appEnv = launchconfig.DevelopmentAppEnv
	testutils.SetAppMode(s.T(), launchconfig.HostedAppMode)

	err := s.invoker.queueBuild(context.Background(), s.wfb, ss, vm, 0, false, nil, nil, nil, nil)
	s.NoError(err)
	s.mockEmitter.AssertExpectations(s.T())
}

func (s *buildInvokerTest) TestValidatesPolicyWithTwirpFailure() {
	ctx := context.Background()
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)

	s.invoker.errorHandler = mockErrorHandler

	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: false,
		PolicyErrorMessage: "Policy error message",
	}
	s.ghtwirp.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)

	// Set AllowsAllActions to false so we hit policy endpoint
	s.invoker.data.AllowsAllActions = false
	s.invoker.data.RepoGlobalID = "fakeId"

	workflow := `
on: push
name: "simple"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`

	wf, _ := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "main.yml"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	err := s.invoker.Run(ctx, &model.Workflow{}, wf, false)
	s.Assert().Equal(err.Error(), "Policy error message")
}

func (s *buildInvokerTest) TestRunBuild() {
	expectedSecretSource := workflowbuild.ActionsSecretSource.String()
	expectedSecrets := actionsDecryptedSecrets
	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient.On("Queue", mock.Anything, s.wfb, s.invoker.receiverURL, s.invoker.resultsReceiverURL, expectedSecretSource, expectedSecrets, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)

	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil)
	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)

	ss := s.getSecretStore(s.wfb)
	vm := s.getVariables()
	err := s.invoker.queueBuild(context.Background(), s.wfb, ss, vm, 0, false, nil, nil, nil, nil)
	s.NoError(err)
	s.Equal(s.wfb.ExternalID, "123")
	s.mockEmitter.AssertExpectations(s.T())
}

func (s *buildInvokerTest) TestRunBuild_FromLab() {
	expectedSecretSource := workflowbuild.ActionsSecretSource.String()
	expectedSecrets := actionsDecryptedSecrets
	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient.On("Queue", mock.Anything, s.wfb, s.invoker.receiverURL, s.invoker.resultsReceiverURL, expectedSecretSource, expectedSecrets, mock.Anything, mock.Anything, mock.Anything, mock.Anything, launchconfig.LabAppEnv).Return(azpBuild, nil)

	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil)
	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)

	ss := s.getSecretStore(s.wfb)
	vm := s.getVariables()
	s.invoker.appEnv = launchconfig.LabAppEnv
	err := s.invoker.queueBuild(context.Background(), s.wfb, ss, vm, 0, false, nil, nil, nil, nil)
	s.NoError(err)
	s.Equal(s.wfb.ExternalID, "123")
	s.mockEmitter.AssertExpectations(s.T())
}

func (s *buildInvokerTest) TestRunBuild_CacheV2Features() {
	tc := []struct {
		name             string
		flags            map[string]bool
		expectedContains map[string]bool
	}{
		{
			name: "cache v2 disabled",
			flags: map[string]bool{
				github.EnableCacheServiceV2:   false,
				github.OptOutOfCacheServiceV2: false,
			},
			expectedContains: map[string]bool{
				github.EnableCacheServiceV2: false,
			},
		},
		{
			name: "cache v2 enabled",
			flags: map[string]bool{
				github.EnableCacheServiceV2:   true,
				github.OptOutOfCacheServiceV2: false,
			},
			expectedContains: map[string]bool{
				github.EnableCacheServiceV2: true,
			},
		},
		{
			name: "cache v2 opted out",
			flags: map[string]bool{
				github.EnableCacheServiceV2:   true,
				github.OptOutOfCacheServiceV2: true,
			},
			expectedContains: map[string]bool{
				github.EnableCacheServiceV2: false,
			},
		},
	}

	for _, tt := range tc {
		s.Run(tt.name, func() {
			s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)

			for flag, value := range tt.flags {
				s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, flag, mock.Anything).Return(value)
			}

			s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil)
			s.mockEmitter.EXPECT().EmitQueueRun(mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
				return msg.Status == hydroV0.QueueRun_SUCCESS
			})).Return()

			azpBuild := &azpclient.Build{ID: 123}
			s.azpClient.EXPECT().Queue(mock.Anything, s.wfb, s.invoker.receiverURL, s.invoker.resultsReceiverURL, workflowbuild.ActionsSecretSource.String(), actionsDecryptedSecrets, mock.Anything, mock.Anything, mock.Anything, mock.MatchedBy(func(features map[string]bool) bool {
				return s.Subset(features, tt.expectedContains)
			}), mock.Anything).Return(azpBuild, nil)

			ss := s.getSecretStore(s.wfb)
			vm := s.getVariables()
			err := s.invoker.queueBuild(context.Background(), s.wfb, ss, vm, 0, false, nil, nil, nil, nil)
			s.NoError(err)
			s.Equal(s.wfb.ExternalID, "123")
			s.mockEmitter.AssertExpectations(s.T())
		})
	}
}

func (s *buildInvokerTest) TestWorkflowCannotActivateItself() {
	targetWorkflow := &model.Workflow{
		Identifier: "CI",
		Path:       "./github/workflows/ci.yaml",
		On: &model.OnEvent{
			Event: flowevents.WorkflowRun,
		},
	}

	previousWorkflow := &githubgo.Workflow{
		ID:   1,
		Name: "CI",
		Path: "./github/workflows/ci.yaml",
	}

	runWorkflowActivationCycle(s, previousWorkflow, targetWorkflow, nil)
}

func (s *buildInvokerTest) TestWorkflowCannotActivateItself_IgnorePath() {
	targetWorkflow := &model.Workflow{
		Identifier: "CI",
		Path:       "./github/workflows/ci.yaml",
		On: &model.OnEvent{
			Event: flowevents.WorkflowRun,
		},
	}

	previousWorkflow := &githubgo.Workflow{
		ID:   1,
		Name: "CI",
		Path: "./github/workflows/some_other_ci.yaml",
	}

	runWorkflowActivationCycle(s, previousWorkflow, targetWorkflow, nil)
}

func (s *buildInvokerTest) TestWorkflowCannotActivateItself_IgnoreCase() {
	targetWorkflow := &model.Workflow{
		Identifier: "cI",
		Path:       "./github/workflows/ci.yaml",
		On: &model.OnEvent{
			Event: flowevents.WorkflowRun,
		},
	}

	previousWorkflow := &githubgo.Workflow{
		ID:   1,
		Name: "CI",
		Path: "./github/workflows/some_other_ci.yaml",
	}

	runWorkflowActivationCycle(s, previousWorkflow, targetWorkflow, nil)
}

func (s *buildInvokerTest) TestRunBuildOmitSecretsForPullRequestsFromFork() {
	headID := int64(1)
	baseID := int64(2)
	pr := &githubgo.PullRequest{
		Head: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &headID,
			},
		},
		Base: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &baseID,
			},
		},
	}
	events := map[string]flowevents.GitHubEvent{
		"pull_request":                &githubgo.PullRequestEvent{PullRequest: pr},
		"pull_request_review":         &githubgo.PullRequestReviewEvent{PullRequest: pr},
		"pull_request_review_comment": &githubgo.PullRequestReviewCommentEvent{PullRequest: pr},
	}

	for name, ghe := range events {
		s.Run(fmt.Sprintf("omits secrets for %q event", name), func() {
			wfb := &build.WorkflowBuild{
				Event:       name,
				GitHubEvent: ghe,
			}

			expectedSecretSource := workflowbuild.NoSecretSource.String()
			expectedSecrets := map[string]string{}
			azpBuild := &azpclient.Build{ID: 123}
			s.azpClient.On("Queue", mock.Anything, wfb, s.invoker.receiverURL, s.invoker.resultsReceiverURL, expectedSecretSource, expectedSecrets, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)
			s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, strconv.Itoa(azpBuild.ID)).Return(nil)
			s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
				return msg.Status == hydroV0.QueueRun_SUCCESS
			})).Return()

			s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)

			ss := s.getSecretStore(wfb)
			vm := map[string]string{}
			err := s.invoker.queueBuild(context.TODO(), wfb, ss, vm, 0, false, nil, nil, nil, nil)
			s.NoError(err)
			s.Equal(wfb.ExternalID, "123")
		})
	}
}

func (s *buildInvokerTest) TestRunBuildOmitVariablesCallForPullRequestsFromFork() {
	setupPullRequestTest(s, true, true, nil)
	setupExpectationsForQueuedRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}

	s.invoker.data.WorkflowFeatureFlags.ConfigurationVariablesEnabled = true

	var emptyVariablesMap map[string]string
	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient = &azpclient.MockRepositoryClient{}

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.azpClient.On("Queue", mock.Anything, mock.Anything, s.invoker.receiverURL, s.invoker.resultsReceiverURL, mock.Anything, mock.Anything, emptyVariablesMap, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)
	s.invoker.azpClient = s.azpClient

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunBuildVariablesCallForNonFork() {
	setupPullRequestTest(s, false, true, nil)
	setupExpectationsForQueuedRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}

	variablesMap := map[string]string{"VAR_KEY": "var_val"}

	mockTwirpClient := &ghtwirp.MockClient{}

	mockTwirpClient.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)

	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.OptOutOfCacheServiceV2, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceProximaFeatureFlag, mock.Anything).Return(false)
	mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(types.GlobalID("id_next"), nil).Times(7)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.BlockArtifactsV3Exempted, mock.Anything).Return(false)

	s.invoker.data.WorkflowFeatureFlags.ConfigurationVariablesEnabled = true
	mockVarzClient := &varz.MockClient{}
	mockVarzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(
		&varz.RepositoryVariablesResponse{RepositoryVariables: map[string]string{"VAR_KEY": "dmFyX3ZhbA=="}, OrganizationVariables: map[string]string{"VAR_KEY": "dmFyX3ZhbF8w"}}, nil)
	s.invoker.varzClient = mockVarzClient
	s.invoker.ghTwirpClient = mockTwirpClient

	s.azpClient = &azpclient.MockRepositoryClient{}
	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient.On("Queue", mock.Anything, mock.Anything, s.invoker.receiverURL, s.invoker.resultsReceiverURL, mock.Anything, mock.Anything, variablesMap, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil).Once()
	s.invoker.azpClient = s.azpClient

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestEnableDebugLogging_AddsDebugLoggingSecretsWhenTrue() {
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)

	s.invoker.invocation.EnableDebugLogging = true

	ss := build.MockSecretStore{}
	ss.On("GetSecretSource", mock.Anything).Return(workflowbuild.ActionsSecretSource)
	ss.On("GetDecryptedSecrets", mock.Anything).Return(map[string]string{
		"OTHER_SECRET": "value",
	}, nil)

	wfb := &build.WorkflowBuild{}
	expectedSecrets := map[string]string{
		"OTHER_SECRET":         "value",
		"ACTIONS_STEP_DEBUG":   "true",
		"ACTIONS_RUNNER_DEBUG": "true",
	}

	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient.On("Queue", mock.Anything, wfb, s.invoker.receiverURL, s.invoker.resultsReceiverURL, workflowbuild.ActionsSecretSource.String(), expectedSecrets, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)
	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, strconv.Itoa(azpBuild.ID)).Return(nil)
	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()
	vm := map[string]string{}
	err := s.invoker.queueBuild(context.TODO(), wfb, &ss, vm, 0, false, nil, nil, nil, nil)
	s.NoError(err)
}

func (s *buildInvokerTest) TestEnableDebugLogging_DoesNotOverrideSecretsWhenFalse() {
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)

	s.invoker.invocation.EnableDebugLogging = false

	ss := build.MockSecretStore{}
	ss.On("GetSecretSource", mock.Anything).Return(workflowbuild.ActionsSecretSource)
	ss.On("GetDecryptedSecrets", mock.Anything).Return(map[string]string{
		"OTHER_SECRET":         "value",
		"ACTIONS_STEP_DEBUG":   "true",
		"ACTIONS_RUNNER_DEBUG": "true",
	}, nil)

	wfb := &build.WorkflowBuild{}
	expectedSecrets := map[string]string{
		"OTHER_SECRET":         "value",
		"ACTIONS_STEP_DEBUG":   "true",
		"ACTIONS_RUNNER_DEBUG": "true",
	}

	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient.On("Queue", mock.Anything, wfb, s.invoker.receiverURL, s.invoker.resultsReceiverURL, workflowbuild.ActionsSecretSource.String(), expectedSecrets, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)
	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, strconv.Itoa(azpBuild.ID)).Return(nil)
	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()
	vm := map[string]string{}
	err := s.invoker.queueBuild(context.TODO(), wfb, &ss, vm, 0, false, nil, nil, nil, nil)
	s.NoError(err)
}

func (s *buildInvokerTest) TestMapQueueErrorToStartErr() {
	tests := []struct {
		name            string
		err             error
		expectedErrType any
		backend         types.WorkflowBackend
	}{
		{
			name:            "Actions Service: syntax error",
			err:             azperrors.NewInvalidSyntaxError("A syntax error"),
			expectedErrType: &azperrors.AZPSyntaxError{},
			backend:         types.WorkflowBackendActionsService,
		},
		{
			name:            "Actions Service: TooManyBuilds error",
			err:             &azperrors.TooManyBuildsError{},
			expectedErrType: &terrors.UserError{},
			backend:         types.WorkflowBackendActionsService,
		},
		{
			name:            "Workflow Parser: syntax error",
			err:             wfparser.NewWorkflowParseError([]error{errors.New("A syntax error")}),
			expectedErrType: &wfparser.WorkflowParseError{},
			backend:         types.WorkflowBackendInconclusive,
		},
		{
			name:            "Generic HTTP error",
			err:             terrors.NewHTTPError(&http.Response{StatusCode: 500}),
			expectedErrType: nil,
			backend:         types.WorkflowBackendRunService,
		},
	}
	for _, tt := range tests {
		s.Run(tt.name, func() {
			errCtx := &WorkflowStartErrorContext{}
			startErr := s.invoker.mapQueueErrorToStartErr(context.Background(), tt.backend, tt.err, errCtx)

			if tt.expectedErrType != nil {
				s.Require().IsType(tt.expectedErrType, startErr.stepErr)
			} else {
				s.Require().Error(startErr.stepErr)
				s.Require().Equal(tt.err, startErr.stepErr)
			}

			s.Require().Equal(tt.backend, startErr.backend)
		})
	}
}

func (s *buildInvokerTest) TestRunBuildForPullRequestsTargetFromFork() {
	headID := int64(1)
	baseID := int64(2)
	pr := &githubgo.PullRequest{
		Head: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &headID,
			},
		},
		Base: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &baseID,
			},
		},
	}

	name := "pull_request_target"
	ghe := &githubgo.PullRequestEvent{PullRequest: pr}

	s.Run(fmt.Sprintf("emits secrets for %q event", name), func() {
		wfb := &build.WorkflowBuild{
			Event:       name,
			GitHubEvent: ghe,
		}

		azpBuild := &azpclient.Build{ID: 123}
		expectedSecretSource := workflowbuild.ActionsSecretSource.String()
		expectedSecrets := actionsDecryptedSecrets
		s.azpClient.On("Queue", mock.Anything, wfb, s.invoker.receiverURL, s.invoker.resultsReceiverURL, expectedSecretSource, expectedSecrets, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)
		s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, strconv.Itoa(azpBuild.ID)).Return(nil)
		s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
			return msg.Status == hydroV0.QueueRun_SUCCESS
		})).Return()

		s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
		s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
		s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
		s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
		s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
		s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)

		ss := s.getSecretStore(wfb)
		vm := s.getVariables()
		err := s.invoker.queueBuild(context.TODO(), wfb, ss, vm, 0, false, nil, nil, nil, nil)
		s.NoError(err)
		s.Equal(wfb.ExternalID, "123")
		s.mockEmitter.AssertExpectations(s.T())
	})
}

func (s *buildInvokerTest) TestGreenTreesPreviousWorkflowRunReuse() {
	tests := []struct {
		name                       string
		featureFlagOn              bool
		event                      string
		reuseKeyPresent            bool
		reusableCheckSuiteFound    bool
		succesfullWorkflowRunReuse bool
	}{
		{
			name:                       "A workflow run is successfully reused",
			featureFlagOn:              true,
			event:                      "push",
			reuseKeyPresent:            true,
			reusableCheckSuiteFound:    true,
			succesfullWorkflowRunReuse: true,
		},
		{
			name:                       "A workflow run does not have the required key",
			featureFlagOn:              true,
			event:                      "push",
			reuseKeyPresent:            false,
			reusableCheckSuiteFound:    true,
			succesfullWorkflowRunReuse: false,
		},
		{
			name:                       "A workflow run is not reused if actions_green_trees is off",
			featureFlagOn:              false,
			event:                      "push",
			reuseKeyPresent:            true,
			reusableCheckSuiteFound:    true,
			succesfullWorkflowRunReuse: false,
		},
		{
			name:                       "A non-supported event has the reuse key",
			featureFlagOn:              true,
			event:                      "workflow_dispatch",
			reuseKeyPresent:            true,
			reusableCheckSuiteFound:    true,
			succesfullWorkflowRunReuse: false,
		},
		{
			name:                       "A failiure occurs during the cloning operation",
			featureFlagOn:              true,
			event:                      "push",
			reuseKeyPresent:            true,
			reusableCheckSuiteFound:    true,
			succesfullWorkflowRunReuse: false,
		},
	}
	for _, tt := range tests {
		s.Run(tt.name, func() {
			workflow := setupWorkflowRunReuseTest(&setupWorkflowRunReuseTestOptions{
				testSuite:                      s,
				eventType:                      tt.event,
				reusePreviousOutcomeKeyPresent: tt.reuseKeyPresent,
				GreenTreesEnabled:              tt.featureFlagOn,
			})

			ctx := context.Background()
			parsed, err := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "main.yml"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
			s.Require().NoError(err)

			mockGitHubClient := &ghclient.MockClient{}

			if tt.reusableCheckSuiteFound {
				checkSuiteToCloneReponse := &ghtwirp.ReusableCheckSuite{
					GlobalID:   types.GlobalID("check-suite-to-clone-global-id"),
					DatabaseID: 100,
				}

				s.ghtwirp.On("FindTreeIDAndPreviousWorkflowRunToReuse", mock.Anything, types.GlobalID("abc"), mock.Anything, mock.Anything, mock.Anything).Return(types.CommitSha("some-tree-id"), checkSuiteToCloneReponse, nil)

				if tt.succesfullWorkflowRunReuse {
					// successful workflow run reuse
					mockGitHubClient.On("ReusePreviousWorkflowRun",
						mock.Anything,
						mock.Anything,
					).Return(&ghclient.ReusePreviousWorkflowRunResponse{
						CheckSuiteID:          "new-check-suite-global-id",
						CheckSuiteDatabaseID:  123,
						WorkflowRunID:         "new-workflow-run-global-id",
						WorkflowRunDatabaseID: 123,
					}, nil)
				} else {
					// unsuccessful workflow run reuse
					mockGitHubClient.On("ReusePreviousWorkflowRun",
						mock.Anything,
						mock.Anything,
					).Return(nil, goerr.New("boom during reuse operation"))
				}
			} else {
				// No previous run to reuse was found
				mockGitHubClient.On("ReusePreviousWorkflowRun",
					mock.Anything,
					mock.Anything,
				).Return(nil, goerr.New("things go boom"))
			}

			mockGitHubClient.On("CreateCheckSuite",
				mock.Anything,
				mock.Anything,
			).Return(&ghclient.CreateCheckSuiteResponse{
				WorkflowRun: &ghclient.CheckSuiteWorkflowRun{},
			}, nil)

			s.invoker.ghClient = mockGitHubClient

			err = s.invoker.Run(context.Background(), &model.Workflow{
				Identifier: "CI",
				Path:       parsed.Path,
				File:       parsed.File,
			}, parsed, false)

			if tt.succesfullWorkflowRunReuse {
				s.assertLogged("Existing workflow run successfully cloned! Not queuing a new run in actions-dotnet")
				mockGitHubClient.AssertNumberOfCalls(s.T(), "CreateCheckSuite", 0)
			} else {
				mockGitHubClient.AssertNumberOfCalls(s.T(), "CreateCheckSuite", 1)
			}
		})
	}
}

func (s *buildInvokerTest) TestRunPRWorkflow_FromUntrustedAuthor() {
	// Prevent workflows from first-time contributors
	setupUntrustedAuthorTests(s, false, nil)

	setupExpectationsForActionRequiredRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_PrivateRepo() {
	setupPullRequestTest(s, true, false, nil)

	s.invoker.data.RepoIsPrivate = true

	// Private repository should respect the response from ShouldRunWorkflows
	setupExpectationsForActionRequiredRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_PrivateRepo_ShouldRunWorkflows() {
	setupPullRequestTest(s, true, true, nil)

	s.invoker.data.RepoIsPrivate = true

	// Private repository should respect the response from ShouldRunWorkflows
	setupExpectationsForQueuedRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_FromTrustedAuthor() {
	setupPullRequestTest(s, true, true, nil)
	setupExpectationsForQueuedRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_RerequestAlwaysRun() {
	setupPullRequestTestWithOptions(&setupPullRequestOptions{
		testSuite:                  s,
		setupForkPR:                true,
		shouldRunWorkflowsExpected: false,
		rerun:                      true,
	})

	setupExpectationsForQueuedRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_UntrustedClosedPRDoesNotRun() {
	// PR author is untrusted
	// Executing actor is trusted
	triggeringActor := testutils.EncodeGlobalID("User", 128)
	prAuthor := testutils.EncodeGlobalID("User", 256)
	setupPullRequestTestWithOptions(&setupPullRequestOptions{
		testSuite:                       s,
		setupForkPR:                     true,
		shouldRunWorkflowsExpected:      true,
		shouldRunWorkflowsResponse:      false,                    // PR author is not trusted
		shouldRunWorkflowsExpectedActor: types.GlobalID(prAuthor), // Expect the PR author
		invocationCallback: func(i *Invocation) {
			i.TriggeringActor.ID = types.GlobalID(triggeringActor)
			i.ExecutingActor.ID = types.GlobalID(triggeringActor)

			prEvent, ok := i.Event.Ghe.(*githubgo.PullRequestEvent)
			s.Require().True(ok)
			closedAction := flowevents.PullRequestClosedAction
			i.Event.Action = closedAction
			prEvent.PullRequest.State = &closedAction
			prEvent.PullRequest.User = &githubgo.User{
				NodeID: &prAuthor,
			}
		},
	})

	// Workflow does not run since the PR author is not trusted
	setupExpectationsForActionRequiredRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_UntrustedClosedPRCanBeApproved() {
	// PR author is untrusted
	// Executing actor is trusted
	triggeringActor := testutils.EncodeGlobalID("User", 128)
	prAuthor := testutils.EncodeGlobalID("User", 256)

	setupPullRequestTestWithOptions(&setupPullRequestOptions{
		testSuite:                  s,
		setupForkPR:                true,
		shouldRunWorkflowsExpected: false,
		rerun:                      true, // An approval is a rerequest event (same as rerun)
		invocationCallback: func(i *Invocation) {
			i.TriggeringActor.ID = types.GlobalID(triggeringActor)
			i.ExecutingActor.ID = types.GlobalID(triggeringActor)

			prEvent, ok := i.Event.Ghe.(*githubgo.PullRequestEvent)
			s.Require().True(ok)
			closedAction := flowevents.PullRequestClosedAction
			i.Event.Action = closedAction
			prEvent.PullRequest.State = &closedAction
			prEvent.PullRequest.User = &githubgo.User{
				NodeID: &prAuthor,
			}
		},
	})

	// Workflow runs since it's a rererequest/rerun
	setupExpectationsForQueuedRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_PRDoesNotRunWhenNoPRAuthor() {
	// Executing actor is trusted
	triggeringActor := testutils.EncodeGlobalID("User", 128)

	// Invalid PR author
	prAuthor := ""

	setupPullRequestTestWithOptions(&setupPullRequestOptions{
		testSuite:                  s,
		setupForkPR:                true,
		shouldRunWorkflowsExpected: false, // We should fail early when PR author is not set
		invocationCallback: func(i *Invocation) {
			i.TriggeringActor.ID = types.GlobalID(triggeringActor)
			i.ExecutingActor.ID = types.GlobalID(triggeringActor)

			prEvent, ok := i.Event.Ghe.(*githubgo.PullRequestEvent)
			s.Require().True(ok)
			closedAction := flowevents.PullRequestClosedAction
			i.Event.Action = closedAction
			prEvent.PullRequest.State = &closedAction
			prEvent.PullRequest.User = &githubgo.User{
				NodeID: &prAuthor,
			}
		},
	})

	// Workflow does not run since the PR author is not valid
	setupExpectationsForActionRequiredRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_PRLabeledEventActionDoesntRun() {
	triggeringActor := testutils.EncodeGlobalID("User", 128)
	prAuthor := testutils.EncodeGlobalID("User", 256)

	setupPullRequestTestWithOptions(&setupPullRequestOptions{
		testSuite:                       s,
		setupForkPR:                     true,
		shouldRunWorkflowsExpected:      true,
		shouldRunWorkflowsResponse:      false,
		shouldRunWorkflowsExpectedActor: types.GlobalID(prAuthor),
		invocationCallback: func(i *Invocation) {
			i.TriggeringActor.ID = types.GlobalID(triggeringActor)
			i.ExecutingActor.ID = types.GlobalID(triggeringActor)

			prEvent, ok := i.Event.Ghe.(*githubgo.PullRequestEvent)
			s.Require().True(ok)
			labeledAction := flowevents.PullRequestLabeledAction
			i.Event.Action = labeledAction
			prEvent.PullRequest.State = &labeledAction
			prEvent.PullRequest.User = &githubgo.User{
				NodeID: &prAuthor,
			}
		},
	})

	setupExpectationsForActionRequiredRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)

}

func (s *buildInvokerTest) TestRunPRWorkflow_PRLabeledEventUsesAuthor() {
	triggeringActor := testutils.EncodeGlobalID("User", 128)
	prAuthor := testutils.EncodeGlobalID("User", 258)

	setupPullRequestTestWithOptions(&setupPullRequestOptions{
		testSuite:                       s,
		setupForkPR:                     true,
		shouldRunWorkflowsExpected:      true,
		shouldRunWorkflowsResponse:      false,
		shouldRunWorkflowsExpectedActor: types.GlobalID(prAuthor),
		invocationCallback: func(i *Invocation) {
			i.TriggeringActor.ID = types.GlobalID(triggeringActor)
			i.ExecutingActor.ID = types.GlobalID(triggeringActor)

			prEvent, ok := i.Event.Ghe.(*githubgo.PullRequestEvent)
			s.Require().True(ok)
			labeledAction := flowevents.PullRequestLabeledAction
			i.Event.Action = labeledAction
			prEvent.PullRequest.State = &labeledAction
			prEvent.PullRequest.User = &githubgo.User{
				NodeID: &prAuthor,
			}
		},
	})

	setupExpectationsForActionRequiredRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_UsesBothActorAndAutherWhenFlagEnabled() {
	// PR author is untrusted
	// Executing actor is trusted
	triggeringActor := testutils.EncodeGlobalID("User", 128)
	prAuthor := testutils.EncodeGlobalID("User", 256)

	setupPullRequestTestWithOptions(&setupPullRequestOptions{
		testSuite:                        s,
		setupForkPR:                      true,
		shouldRunWorkflowsExpected:       true,
		shouldRunWorkflowsResponse:       false, // PR author is not trusted
		shouldRunWorkflowsExpectedActor:  types.GlobalID(triggeringActor),
		shouldRunWorkflowsExpectedAuthor: types.GlobalID(prAuthor),

		invocationCallback: func(i *Invocation) {
			i.TriggeringActor.ID = types.GlobalID(triggeringActor)
			i.ExecutingActor.ID = types.GlobalID(triggeringActor)

			prEvent, ok := i.Event.Ghe.(*githubgo.PullRequestEvent)
			s.Require().True(ok)

			prEvent.PullRequest.User = &githubgo.User{
				NodeID: &prAuthor,
			}
		},
	})

	s.invoker.data.WorkflowFeatureFlags.WorkflowApprovalsUsePRAuthorEnabled = true
	s.T().Cleanup(func() {
		s.invoker.data.WorkflowFeatureFlags.WorkflowApprovalsUsePRAuthorEnabled = false
	})

	// Workflow does not run since the PR author is not trusted
	setupExpectationsForActionRequiredRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_TrustedAuthorAndActorWhenFlagEnabled() {
	// PR author is trusted
	// Executing actor is trusted
	triggeringActor := testutils.EncodeGlobalID("User", 128)
	prAuthor := testutils.EncodeGlobalID("User", 256)

	setupPullRequestTestWithOptions(&setupPullRequestOptions{
		testSuite:                        s,
		setupForkPR:                      true,
		shouldRunWorkflowsExpected:       true,
		shouldRunWorkflowsResponse:       true, // Both are trusted
		shouldRunWorkflowsExpectedActor:  types.GlobalID(triggeringActor),
		shouldRunWorkflowsExpectedAuthor: types.GlobalID(prAuthor),

		invocationCallback: func(i *Invocation) {
			i.TriggeringActor.ID = types.GlobalID(triggeringActor)
			i.ExecutingActor.ID = types.GlobalID(triggeringActor)

			prEvent, ok := i.Event.Ghe.(*githubgo.PullRequestEvent)
			s.Require().True(ok)

			prEvent.PullRequest.User = &githubgo.User{
				NodeID: &prAuthor,
			}
		},
	})

	s.invoker.data.WorkflowFeatureFlags.WorkflowApprovalsUsePRAuthorEnabled = true
	s.T().Cleanup(func() {
		s.invoker.data.WorkflowFeatureFlags.WorkflowApprovalsUsePRAuthorEnabled = false
	})

	// Workflow runs since both are trusted
	setupExpectationsForQueuedRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_PRDoesNotRunWhenNoPRAuthorWhenFlagEnabled() {
	triggeringActor := testutils.EncodeGlobalID("User", 128)

	setupPullRequestTestWithOptions(&setupPullRequestOptions{
		testSuite:                  s,
		setupForkPR:                true,
		shouldRunWorkflowsExpected: false, // We should fail early when PR author is not set
		invocationCallback: func(i *Invocation) {
			i.TriggeringActor.ID = types.GlobalID(triggeringActor)
			i.ExecutingActor.ID = types.GlobalID(triggeringActor)

			prEvent, ok := i.Event.Ghe.(*githubgo.PullRequestEvent)
			s.Require().True(ok)

			// Invalid PR author
			prAuthor := ""

			prEvent.PullRequest.User = &githubgo.User{
				NodeID: &prAuthor,
			}
		},
	})

	s.invoker.data.WorkflowFeatureFlags.WorkflowApprovalsUsePRAuthorEnabled = true
	s.T().Cleanup(func() {
		s.invoker.data.WorkflowFeatureFlags.WorkflowApprovalsUsePRAuthorEnabled = false
	})

	// Workflow does not run since the PR author is not valid
	setupExpectationsForActionRequiredRun(s)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRunPRWorkflow_HandlesErrorsWhenFlagEnabled() {
	author := testutils.EncodeGlobalID("User", 32)

	setupPullRequestTestWithOptions(&setupPullRequestOptions{
		testSuite:                        s,
		setupForkPR:                      true,
		shouldRunWorkflowsExpected:       true,
		shouldRunWorkflowsError:          errors.New("boom"),
		shouldRunWorkflowsExpectedActor:  types.GlobalID(author),
		shouldRunWorkflowsExpectedAuthor: types.GlobalID(author),
	})

	s.invoker.data.WorkflowFeatureFlags.WorkflowApprovalsUsePRAuthorEnabled = true
	s.T().Cleanup(func() {
		s.invoker.data.WorkflowFeatureFlags.WorkflowApprovalsUsePRAuthorEnabled = false
	})

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: file.File,
	}, &file, false)

	s.Assert().Error(err)
	s.Assert().ErrorContains(err, "boom")
}

func (s *buildInvokerTest) TestWorkflowRun_DetectCycleBetweenWorkflows() {
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).
		Return(func(ctx context.Context, globalID string) types.GlobalID {
			s.Assert().True(types.IsNextGlobalID(globalID))
			return types.NewGlobalID(ctx, globalID)
		}, nil).Maybe()

	addWorkflowRunRun := func(identifier string, runID int, previousIdentifier, previousCheckSuiteID string) string {
		previousWF := &githubgo.Workflow{
			ID:   runID,
			Name: fmt.Sprintf("./github/workflows/%v.yaml", previousIdentifier),
			Path: fmt.Sprintf("./github/workflows/%v.yaml", previousIdentifier),
		}

		previousWFR := &githubgo.WorkflowRun{
			Event:            flowevents.WorkflowRun,
			CheckSuiteNodeID: previousCheckSuiteID,
		}

		// Event that triggered the workflow
		payload, _ := json.Marshal(&githubgo.WorkflowRunEvent{
			Workflow:    previousWF,
			WorkflowRun: previousWFR,
		})
		checkSuiteNodeID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", int64(runID)))
		s.repo.On(
			"GetStateByCheckSuiteID", mock.Anything, checkSuiteNodeID,
		).Return(&types.CheckSuiteState{
			WorkflowFilePath: fmt.Sprintf("./github/workflows/%v.yaml", identifier),
			Event:            "workflow_run",
			EventPayload:     payload,
		}, true, nil)

		return checkSuiteNodeID.String()
	}

	// Previous workflows:
	// -push-> a.yml -workflow_run-> b.yml -workflow_run-> c.yml
	checkSuiteNodeID := addWorkflowRunRun("a", 1, "push", "")
	checkSuiteNodeID = addWorkflowRunRun("b", 1, "a", checkSuiteNodeID)
	checkSuiteNodeID = addWorkflowRunRun("c", 2, "b", checkSuiteNodeID)

	// Workflow to run as a result of the `c.yml` workflow run
	targetWorkflow := &model.Workflow{
		Identifier: "./github/workflows/a.yaml",
		Path:       "./github/workflows/a.yaml",
		On: &model.OnEvent{
			Event: flowevents.WorkflowRun,
		},
	}

	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)

	s.invoker.errorHandler = mockErrorHandler

	s.invoker.invocation = Invocation{
		Event: InvokingEvent{
			Name: "workflow_run",
			Ghe: &githubgo.WorkflowRunEvent{
				Workflow: &githubgo.Workflow{
					ID:   3,
					Name: fmt.Sprintf("./github/workflows/%v.yaml", "d"),
					Path: fmt.Sprintf("./github/workflows/%v.yaml", "d"),
				},
				WorkflowRun: &githubgo.WorkflowRun{
					Event:            flowevents.WorkflowRun,
					CheckSuiteNodeID: checkSuiteNodeID,
				},
			},
		},
	}

	_ = s.invoker.Run(context.Background(), targetWorkflow, &workflowparser.Workflow{}, false)
	s.Equal(s.wfb.ExternalID, "", "no checksuite should be created when a cycle is detected.")
	s.assertLogged("workflow_run cycle detection found a cycle")
	s.assertLogged("gh.launch.workflow_run_cycle.max_depth=3 gh.launch.workflow_run_cycle.cycles_count=1")
}

func (s *buildInvokerTest) TestWorkflowRun_DeploymentStatus_Cycle() {
	addWorkflowRunRun := func(identifier string, runID int, previousIdentifier, previousCheckSuiteID string) string {
		previousWF := &githubgo.Workflow{
			ID:   runID,
			Name: fmt.Sprintf("./github/workflows/%v.yaml", previousIdentifier),
			Path: fmt.Sprintf("./github/workflows/%v.yaml", previousIdentifier),
		}

		previousWFR := &githubgo.WorkflowRun{
			Event:            flowevents.WorkflowRun,
			CheckSuiteNodeID: previousCheckSuiteID,
		}

		// Event that triggered the workflow
		payload, _ := json.Marshal(&githubgo.WorkflowRunEvent{
			Workflow:    previousWF,
			WorkflowRun: previousWFR,
		})
		checkSuiteNodeID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", int64(runID)))
		s.repo.On(
			"GetStateByCheckSuiteID", mock.Anything, checkSuiteNodeID,
		).Return(&types.CheckSuiteState{
			WorkflowFilePath: fmt.Sprintf("./github/workflows/%v.yaml", identifier),
			Event:            "workflow_run",
			EventPayload:     payload,
		}, true, nil)

		return checkSuiteNodeID.String()
	}

	// pull_request -> a.yml -deployment_status -> a.yml
	checkSuiteNodeID := addWorkflowRunRun("a", 1, "pull", "")

	targetWorkflow := &model.Workflow{
		Identifier: "./github/workflows/a.yaml",
		Path:       "./github/workflows/a.yaml",
		On: &model.OnEvent{
			Event: flowevents.WorkflowRun,
		},
	}

	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)

	s.invoker.errorHandler = mockErrorHandler

	s.invoker.invocation = Invocation{
		Event: InvokingEvent{
			Name: "workflow_run",
			Ghe: &githubgo.DeploymentStatusEvent{
				Workflow: &githubgo.Workflow{
					ID:   2,
					Name: "./github/workflows/a.yaml",
					Path: "./github/workflows/a.yaml",
				},
				WorkflowRun: &githubgo.WorkflowRun{
					Event:            flowevents.DeploymentStatus,
					CheckSuiteNodeID: checkSuiteNodeID,
				},
			},
		},
	}

	_ = s.invoker.Run(context.Background(), targetWorkflow, &workflowparser.Workflow{}, false)
	s.assertLogged("workflow not running due to recursive cycle detected")
	s.assertLogged("deployment status loop detected")
}
func (s *buildInvokerTest) TestWorkflowRun_ReRunScenario() {
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}
	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
	}

	// Set AllowsAllActions to false so we hit policy endpoint
	s.invoker.data.AllowsAllActions = false

	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
		return in.RepositoryID == repoID &&
			in.PlanID == executionID &&
			in.Attempt == attemptNum
	})).Return(nil)

	tokenFactory := &workflowbuild.MockTokenFactory{}
	tokenFactory.On("CalculateRunPermissions", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&tokens.PermissionSettings{
		InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
		DefaultPermissions:      tokens.LimitedReadPermissions,
	}, nil)
	s.invoker.tokenFactory = tokenFactory

	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum}, nil)

	s.azpClient.On("Queue", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&azpclient.Build{ID: 123}, nil).Once()
	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil)
	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()

	s.invoker.invocation = Invocation{
		ExistingCheckSuite: &types.CheckSuiteState{
			RepositoryID: repoID,
			CheckSuiteIDPair: types.IDPair{
				GlobalID: types.GlobalID(checkSuiteNodeID),
			},
		},
	}
	s.invoker.data.PipelineFiles = []types.ResolvedFile{file.File}

	_ = s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
		File: file.File,
	}, &file, false)
	s.mockEmitter.AssertExpectations(s.T())
	s.repo.AssertExpectations(s.T())
	tokenFactory.AssertExpectations(s.T())
	s.ghtwirp.AssertExpectations(s.T())
	mockErrorHandler.AssertExpectations(s.T())
}

func (s *buildInvokerTest) TestWorkflowRun_ReRunScenarioWithRunName() {
	setupPullRequestTest(s, true, true, nil)
	setupExpectationsForQueuedRun(s)
	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)

	mockTwirpClient := &ghtwirp.MockClient{}
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	mockTwirpClient.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.OptOutOfCacheServiceV2, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceProximaFeatureFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.BlockArtifactsV3Exempted, mock.Anything).Return(false)

	mockTwirpClient.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
		return in.RepositoryID == repoID &&
			in.PlanID == executionID &&
			in.Attempt == attemptNum
	})).Return(nil)
	mockTwirpClient.On("UpdateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, "Attempt 3").Return(nil).Once()
	mockTwirpClient.On("GetNextGlobalID", mock.Anything, "").Return(types.NilGlobalID, nil)
	s.invoker.ghTwirpClient = mockTwirpClient

	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum}, nil)

	file := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
		RunNameExpression: "Attempt ${{ github.run_attempt }}",
	}
	s.invoker.invocation.ExistingCheckSuite = &types.CheckSuiteState{
		RepositoryID: repoID,
		CheckSuiteIDPair: types.IDPair{
			GlobalID: types.GlobalID(checkSuiteNodeID),
		},
	}

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       file.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File:              file.File,
		RunNameExpression: "Attempt ${{ github.run_attempt }}",
	}, &file, false)

	s.Assert().Nil(err)
	mockTwirpClient.AssertExpectations(s.T())
}

func (s *buildInvokerTest) TestCallableWorkflows_InvalidCalledWorkflowSyntaxPushEvent() {
	ctx := context.Background()
	setupExpectationsForQueuedRun(s)
	setupUntrustedAuthorTests(s, true, nil)

	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	mockErrorHandler.On("notifyInvalidWorkflow", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler
	s.invoker.data.WorkflowFeatureFlags = types.WorkflowFeatureFlags{}

	wf := types.ResolvedFile{
		Path: "org/repo/.github/workflows/ci.yaml",
		Text: `on: pull_request
jobs:
  a:
    uses: org/repo/.github/workflows/called.yml@main`,
	}
	cwf := &workflowparser.StubWorkflowSource{
		SourceMap: map[string]workflowparser.WorkflowDetails{
			"otheruser/otherrepo/.github/workflows/called.yml@v1": {
				Content: "on:\n  workflow_callmemaybe:\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				RefType: "refs/tags/",
			},
		}}
	s.invoker.workflowSource = cwf

	parsed, _ := workflowparser.Parse(ctx, wf, types.WorkflowFeatureFlags{}, cwf, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	s.invoker.invocation = Invocation{
		Event: InvokingEvent{
			Name: "pull_request",
		},
	}

	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)

	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum}, nil)

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       parsed.Path,
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
		File: parsed.File,
	}, parsed, false)

	s.Assert().Nil(err)
	s.assertLogged("invalid workflow file")
	mockErrorHandler.AssertNumberOfCalls(s.T(), "notifyInvalidWorkflow", 1)
}

func (s *buildInvokerTest) TestCallableWorkflows_ReferencedFilesAreSent() {
	setupExpectationsForQueuedRun(s)
	setupUntrustedAuthorTests(s, true, nil)

	cwf1 := workflowparser.CalledWorkflow{
		Workflow: workflowparser.Workflow{
			Path: "org1/repo1/.github/workflows/called1.yml@sha1",
			File: types.ResolvedFile{
				Path: "org1/repo1/.github/workflows/called1.yml@sha1",
				SHA:  "gfedcba",
			},
		},
		Metadata: workflowparser.RepositoryMetadata{
			TenantID:             "tenant-id-1",
			RepositoryNWO:        types.RepositoryFullName{Owner: "org1", Name: "repo1"},
			IsTrusted:            true,
			RepositoryID:         types.GlobalID("repo1global"),
			RepositoryDatabaseID: 1123,
			PlanOwnerID:          types.GlobalID("org1global"),
		},
	}

	cwf2 := workflowparser.CalledWorkflow{
		Workflow: workflowparser.Workflow{
			Path: "org1/repo1/.github/workflows/called2.yml@sha1",
			File: types.ResolvedFile{
				Path: "org1/repo1/.github/workflows/called2.yml@sha1",
				SHA:  "abcdefg",
			},
		},
		Metadata: workflowparser.RepositoryMetadata{
			TenantID:             "tenant-id-2",
			RepositoryNWO:        types.RepositoryFullName{Owner: "org1", Name: "repo1"},
			RepositoryID:         types.GlobalID("repo1global"),
			IsTrusted:            true,
			RepositoryDatabaseID: 1123,
			PlanOwnerID:          types.GlobalID("org1global"),
		},
	}
	mainFile := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},
		CalledWorkflows: map[string]workflowparser.CalledWorkflow{
			cwf1.Workflow.Path: cwf1,
			cwf2.Workflow.Path: cwf2,
		},
	}

	want := mock.MatchedBy(func(got *build.WorkflowBuild) bool {
		expected := map[string]build.ReferencedFile{
			cwf1.Workflow.Path: {
				TenantID:             "tenant-id-1",
				SHA:                  "gfedcba",
				RepositoryNWO:        types.RepositoryFullName{Owner: "org1", Name: "repo1"},
				RepositoryID:         types.GlobalID("repo1global"),
				RepositoryDatabaseID: 1123,
				PlanOwnerID:          types.GlobalID("org1global"),
				IsTrusted:            true},
			cwf2.Workflow.Path: {
				TenantID:             "tenant-id-2",
				SHA:                  "abcdefg",
				RepositoryNWO:        types.RepositoryFullName{Owner: "org1", Name: "repo1"},
				RepositoryID:         types.GlobalID("repo1global"),
				RepositoryDatabaseID: 1123,
				PlanOwnerID:          types.GlobalID("org1global"),
				IsTrusted:            true},
		}

		return s.Assert().Equal(expected, got.ReferencedFiles)
	})

	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("Queue", mock.Anything, want, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil).Once()
	s.invoker.azpClient = s.azpClient
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       mainFile.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: mainFile.File,
	}, &mainFile, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestCallableWorkflows_CalledWorkflowsAreSent() {
	setupExpectationsForQueuedRun(s)
	setupUntrustedAuthorTests(s, true, nil)

	cwf1 := workflowparser.Workflow{
		Path: "org1/repo1/.github/workflows/called1.yml@sha1",
		File: types.ResolvedFile{
			Path: "org1/repo1/.github/workflows/called1.yml@sha1",
		},
	}
	cwf2 := workflowparser.Workflow{
		Path: "org1/repo1/.github/workflows/called2.yml@sha1",
		File: types.ResolvedFile{
			Path: "org1/repo1/.github/workflows/called2.yml@sha1",
		},
	}
	mainFile := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},

		CalledWorkflows: map[string]workflowparser.CalledWorkflow{
			cwf1.Path: {Workflow: cwf1},
			cwf2.Path: {Workflow: cwf2},
		},
	}

	// modify expectations to verify we get the resolved files we wanted, in the right
	// order and without duplicates
	want := mock.MatchedBy(func(got *build.WorkflowBuild) bool {
		sort.Slice(got.ResolvedFiles, func(i, j int) bool {
			return got.ResolvedFiles[i].Path < got.ResolvedFiles[j].Path
		})
		return s.Assert().Equal(got.ResolvedFiles, []types.ResolvedFile{
			mainFile.File,
			cwf1.File,
			cwf2.File,
		})
	})

	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("Queue", mock.Anything, want, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil).Once()
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.invoker.azpClient = s.azpClient

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       mainFile.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: mainFile.File,
	}, &mainFile, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestCallableWorkflows_GraphsGeneratedOnReruns() {
	ctx := context.Background()
	setupExpectationsForQueuedRun(s)
	setupUntrustedAuthorTests(s, true, nil)
	s.invoker.data.WorkflowFeatureFlags = types.WorkflowFeatureFlags{}

	wf := types.ResolvedFile{
		Path: "org/repo/.github/workflows/ci.yaml",
		Text: `on: push
jobs:
  a:
    uses: org/repo/.github/workflows/called.yml@main`,
	}

	cwf := &workflowparser.StubWorkflowSource{
		SourceMap: map[string]workflowparser.WorkflowDetails{
			"org/repo/.github/workflows/called.yml@main": {
				Content: `
on: workflow_call
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
				RefType: "refs/heads/",
			},
		}}

	expectedGraph := "{\"stages\":[{\"groups\":[{\"id\":\"|\",\"type\":0,\"jobs\":[{\"id\":\"a.b\",\"name\":\"a / b\"}]}]}]}"

	parsed, _ := workflowparser.Parse(ctx, wf, types.WorkflowFeatureFlags{}, cwf, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	s.invoker.workflowSource = cwf
	s.invoker.invocation = Invocation{
		ExistingCheckSuite: &types.CheckSuiteState{
			RepositoryID: repoID,
			CheckSuiteIDPair: types.IDPair{
				GlobalID: types.GlobalID(checkSuiteNodeID),
			},
		},
	}

	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)

	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
		return in.RepositoryID == repoID &&
			in.PlanID == executionID &&
			in.Attempt == attemptNum &&
			in.ExecutionGraph == expectedGraph
	})).Return(nil)
	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum}, nil)

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       parsed.Path,
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
		File: parsed.File,
	}, parsed, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestCallableWorkflows_FeatureFlagTwirpCallCheckForBusinessActor_PrivateWorkflows() {
	ctx := context.Background()
	setupExpectationsForQueuedRun(s)
	setupUntrustedAuthorTests(s, true, nil)
	s.invoker.data.WorkflowFeatureFlags = types.WorkflowFeatureFlags{}
	s.invoker.data.PlanOwner.Type = "Business"
	s.invoker.data.PlanOwner.GlobalID = "E_kgAB"
	s.invoker.data.RepoIsPrivate = true

	wf := types.ResolvedFile{
		Path: "org/repo/.github/workflows/ci.yaml",
		Text: `on: push
jobs:
  a:
    uses: org/repo/.github/workflows/called.yml@main`,
	}

	cwf := &workflowparser.StubWorkflowSource{
		SourceMap: map[string]workflowparser.WorkflowDetails{
			"org/repo/.github/workflows/called.yml@main": {
				Content: `
on: workflow_call
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
				RefType: "refs/heads/",
			},
		}}

	parsed, _ := workflowparser.Parse(ctx, wf, types.WorkflowFeatureFlags{}, cwf, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	s.invoker.workflowSource = cwf
	s.invoker.invocation = Invocation{
		ExistingCheckSuite: &types.CheckSuiteState{
			RepositoryID: repoID,
			CheckSuiteIDPair: types.IDPair{
				GlobalID: types.GlobalID(checkSuiteNodeID),
			},
		},
	}

	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)

	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.Anything).Return(nil)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)

	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum}, nil)

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       parsed.Path,
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
		File: parsed.File,
	}, parsed, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestCallableWorkflows_NoGraphGeneratedForPartialReruns() {
	ctx := context.Background()
	setupExpectationsForQueuedRun(s)
	setupUntrustedAuthorTests(s, true, nil)
	s.invoker.data.WorkflowFeatureFlags = types.WorkflowFeatureFlags{}

	wf := types.ResolvedFile{
		Path: "org/repo/.github/workflows/ci.yaml",
		Text: `on: push
jobs:
  a:
    uses: org/repo/.github/workflows/called.yml@main`,
	}

	cwf := &workflowparser.StubWorkflowSource{
		SourceMap: map[string]workflowparser.WorkflowDetails{
			"org/repo/.github/workflows/called.yml@main": {
				Content: `
on: workflow_call
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
				RefType: "refs/heads/",
			},
		},
		CallerRepoID: "R_kgAw",
		CallerRepoNWO: types.RepositoryFullName{
			Owner: "owner4",
			Name:  "repo2",
		},
	}

	parsed, _ := workflowparser.Parse(ctx, wf, types.WorkflowFeatureFlags{}, cwf, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	s.invoker.workflowSource = cwf
	s.invoker.invocation = Invocation{
		ExistingCheckSuite: &types.CheckSuiteState{
			RepositoryID: repoID,
			CheckSuiteIDPair: types.IDPair{
				GlobalID: types.GlobalID(checkSuiteNodeID),
			},
		},
		RerunInfo: &types.RerunInfo{
			PlanID: "rerun-plan-id",
			JobIDs: types.JobIDs{"a-job-id"},
		},
	}

	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)

	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)

	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
		return in.RepositoryID == repoID &&
			in.PlanID == executionID &&
			in.Attempt == attemptNum &&
			in.ExecutionGraph == ""
	})).Return(nil)

	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum}, nil)

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       parsed.Path,
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
		File: parsed.File,
	}, parsed, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestCallableWorkflows_RunServicePartialReruns() {
	ctx := context.Background()
	setupExpectationsForQueuedRun(s)
	setupUntrustedAuthorTests(s, true, nil)
	s.invoker.data.WorkflowFeatureFlags = types.WorkflowFeatureFlags{}

	previousPlanId := uuid.New()
	wf := types.ResolvedFile{
		Path: "org/repo/.github/workflows/ci.yaml",
		Text: `on: push
jobs:
  a:
    uses: org/repo/.github/workflows/called.yml@main`,
	}

	cwf := &workflowparser.StubWorkflowSource{
		SourceMap: map[string]workflowparser.WorkflowDetails{
			"org/repo/.github/workflows/called.yml@main": {
				Content: `
on: workflow_call
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world`,
				RefType: "refs/heads/",
			},
		},
		CallerRepoID: "R_kgAw",
		CallerRepoNWO: types.RepositoryFullName{
			Owner: "owner4",
			Name:  "repo2",
		},
	}

	parsed, _ := workflowparser.Parse(ctx, wf, types.WorkflowFeatureFlags{}, cwf, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	s.invoker.workflowSource = cwf
	s.invoker.invocation = Invocation{
		ExistingCheckSuite: &types.CheckSuiteState{
			RepositoryID: repoID,
			CheckSuiteIDPair: types.IDPair{
				GlobalID: types.GlobalID(checkSuiteNodeID),
			},
		},
		RerunInfo: &types.RerunInfo{
			PlanID: previousPlanId.String(),
			JobIDs: types.JobIDs{"a-job-id"},
		},
	}

	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)

	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false) // FF is off but we should send to run service based on previous attempt
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
		return in.RepositoryID == repoID &&
			in.PlanID == executionID &&
			in.Attempt == attemptNum &&
			in.ExecutionGraph == ""
	})).Return(nil)

	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum, Backend: types.WorkflowBackendRunService}, nil)

	s.resultsClient.On("GetWorkflowOrchestrationContexts", mock.Anything, types.WorkflowExecutionID(previousPlanId)).Return([]string{"context_1", "context_2"}, nil)

	runStampURL := "https://run-service.github.app"
	s.runServiceClient.On("StartPlan", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(uuid.NewString(), runStampURL, nil).Once()
	s.invoker.runServiceClient = s.runServiceClient

	s.ghtwirp.On("UpdateWorkflowRunExecution", mock.Anything, mock.Anything, mock.Anything, runStampURL).Return(nil)

	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil).Once()

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       parsed.Path,
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
		File: parsed.File,
	}, parsed, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestCallableWorkflows_RecursiveCalledWorkflowsAreSent() {
	// not supported as a product-decision limitation, but the code is capable of handling it
	setupExpectationsForQueuedRun(s)
	setupUntrustedAuthorTests(s, true, nil)

	cwf1 := workflowparser.Workflow{
		Path: "org1/repo1/.github/workflows/called1.yml@sha1",
		File: types.ResolvedFile{
			Path: "org1/repo1/.github/workflows/called1.yml@sha1",
		},
	}
	cwf2 := workflowparser.Workflow{
		Path: "org1/repo1/.github/workflows/called2.yml@sha1",
		File: types.ResolvedFile{
			Path: "org1/repo1/.github/workflows/called2.yml@sha1",
		},
		CalledWorkflows: map[string]workflowparser.CalledWorkflow{
			cwf1.Path: {Workflow: cwf1},
		},
	}
	mainFile := workflowparser.Workflow{
		Path: "./github/workflows/ci.yaml",
		File: types.ResolvedFile{
			Path: "./github/workflows/ci.yaml",
		},

		CalledWorkflows: map[string]workflowparser.CalledWorkflow{
			cwf1.Path: {Workflow: cwf1},
			cwf2.Path: {Workflow: cwf2},
		},
	}

	// modify expectations to verify we get the resolved files we wanted, in the right
	// order and without duplicates
	want := mock.MatchedBy(func(got *build.WorkflowBuild) bool {
		sort.Slice(got.ResolvedFiles, func(i, j int) bool {
			return got.ResolvedFiles[i].Path < got.ResolvedFiles[j].Path
		})
		return s.Assert().Equal(got.ResolvedFiles, []types.ResolvedFile{
			mainFile.File,
			cwf1.File,
			cwf2.File,
		})
	})

	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("Queue", mock.Anything, want, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil).Once()

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)

	s.invoker.azpClient = s.azpClient

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       mainFile.Path,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: mainFile.File,
	}, &mainFile, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestCallableWorkflows_ReportCallableWorkflowParsingErrorOnReruns() {
	ctx := context.Background()
	setupExpectationsForQueuedRun(s)
	setupUntrustedAuthorTests(s, true, nil)
	s.invoker.data.WorkflowFeatureFlags = types.WorkflowFeatureFlags{}

	wf := types.ResolvedFile{
		Path: "org/repo/.github/workflows/ci.yaml",
		Text: `on: push
jobs:
  a:
    uses: org/repo/.github/workflows/called.yml@main`,
	}

	cwf := &workflowparser.StubWorkflowSource{
		SourceMap: map[string]workflowparser.WorkflowDetails{
			"org/repo/.github/workflows/called.yml@main": {
				Content: `
on: workflow_call
jobs:
  b:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello world

syntax error	  `,
				RefType: "refs/heads/",
			},
		}}

	parsed, _ := workflowparser.Parse(ctx, wf, types.WorkflowFeatureFlags{}, cwf, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	s.invoker.workflowSource = cwf
	s.invoker.invocation = Invocation{
		ExistingCheckSuite: &types.CheckSuiteState{
			RepositoryID: repoID,
			CheckSuiteIDPair: types.IDPair{
				GlobalID: types.GlobalID(checkSuiteNodeID),
			},
		},
	}

	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)

	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
		return in.Attempt == attemptNum
	})).Return(nil)

	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum}, nil)

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       parsed.Path,
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
		File: parsed.File,
	}, parsed, false)

	s.Require().Error(err)
	s.Assert().Equal(types.GlobalID(checkSuiteNodeID), err.checkSuiteID)
	s.Assert().Len(err.Errors(), 1)
	s.Assert().Equal(`error parsing called workflow
"org/repo/.github/workflows/ci.yaml"
-> "org/repo/.github/workflows/called.yml@main" (source branch with sha:main)
: You have an error in your yaml syntax on line 9`, err.Error())
}

func (s *buildInvokerTest) TestCallableWorkflows_ReportInternalErrors() {
	ctx := context.Background()
	setupExpectationsForQueuedRun(s)
	setupUntrustedAuthorTests(s, true, nil)
	s.invoker.data.WorkflowFeatureFlags = types.WorkflowFeatureFlags{}

	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	mockErrorHandler.On("notifyInvalidWorkflow", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	wf := types.ResolvedFile{
		Path: "org/repo/.github/workflows/ci.yaml",
		Text: `on: push
jobs:
  a:
    uses: org/repo/.github/workflows/called.yml@main`,
	}

	wfsrc := &workflowparser.ErrorWorkflowSource{
		Error: terrors.NewInternalError(errors.New("internal error")),
	}

	parsed, _ := workflowparser.Parse(ctx, wf, types.WorkflowFeatureFlags{}, wfsrc, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	s.invoker.workflowSource = wfsrc

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       parsed.Path,
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
		File: parsed.File,
	}, parsed, false)

	s.Assert().Nil(err)
	s.assertLogged("invalid workflow file")
	mockErrorHandler.AssertNumberOfCalls(s.T(), "notifyInvalidWorkflow", 1)
}

func (s *buildInvokerTest) TestCallableWorkflows_ReportInternalErrorsOnReruns() {
	ctx := context.Background()
	setupExpectationsForQueuedRun(s)
	setupUntrustedAuthorTests(s, true, nil)
	s.invoker.data.WorkflowFeatureFlags = types.WorkflowFeatureFlags{}

	wf := types.ResolvedFile{
		Path: "org/repo/.github/workflows/ci.yaml",
		Text: `on: push
jobs:
  a:
    uses: org/repo/.github/workflows/called.yml@main`,
	}

	wfsrc := &workflowparser.ErrorWorkflowSource{
		Error: terrors.NewInternalError(errors.New("internal error")),
	}

	parsed, _ := workflowparser.Parse(ctx, wf, types.WorkflowFeatureFlags{}, wfsrc, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())

	s.invoker.workflowSource = wfsrc
	s.invoker.invocation = Invocation{
		ExistingCheckSuite: &types.CheckSuiteState{
			RepositoryID: repoID,
			CheckSuiteIDPair: types.IDPair{
				GlobalID: types.GlobalID(checkSuiteNodeID),
			},
		},
	}

	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)

	s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
		return in.Attempt == attemptNum
	})).Return(nil)

	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum}, nil)

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       parsed.Path,
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
		File: parsed.File,
	}, parsed, false)

	s.Require().Error(err)
	s.Assert().Equal(types.GlobalID(checkSuiteNodeID), err.checkSuiteID)
	s.Assert().Len(err.Errors(), 1)
	s.Assert().False(err.IsUserError())
	s.Assert().Equal("resolving caller repository: internal error", err.Error())
}

func (s *buildInvokerTest) TestGetRepositoryTier() {
	tests := []struct {
		desc                string
		shouldCalculateTier bool
		isEnterprise        bool
	}{
		{
			desc:                "calculates tier for non-enterprise",
			shouldCalculateTier: true,
			isEnterprise:        false,
		},
		{
			desc:                "tier 1 without call for enterprise",
			shouldCalculateTier: false,
			isEnterprise:        true,
		},
	}

	for _, tt := range tests {
		s.Run(tt.desc, func() {
			mockTwirpClient := &ghtwirp.MockClient{}
			mockTwirpClient.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
			s.invoker.ghTwirpClient = mockTwirpClient

			s.invoker.isEnterprise = tt.isEnterprise

			repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 16))
			tier, err := s.invoker.GetRepositoryTier(context.Background(), repoID)
			s.Assert().NoError(err)

			if tt.shouldCalculateTier {
				mockTwirpClient.AssertNumberOfCalls(s.T(), "GetTrustTier", 1)

				s.Equal(types.RepositoryTier3, tier)
			} else {
				mockTwirpClient.AssertNumberOfCalls(s.T(), "GetTrustTier", 0)

				s.Equal(types.RepositoryTier1, tier)
			}
		})
	}
}

// TestCorrectSecretsSentToAzp is a high-level test that verifies the correct secret store is used to retrieve secrets and call azpClient.Queue.
// It covers some basic scenarios. TestGetSecretStore can be used for exhaustive permutations.
func (s *buildInvokerTest) TestCorrectSecretsSentToAzp() {
	noSecrets := map[string]string{}

	testCases := []struct {
		name                 string
		setupForkPR          bool
		actor                *metadata.WorkflowMetadataActor
		expectedSecretSource string
		expectedSecrets      map[string]string
	}{
		{
			name:                 "Uses Actions secrets for ordinary pull_request run",
			setupForkPR:          false,
			actor:                &metadata.WorkflowMetadataActor{},
			expectedSecretSource: workflowbuild.ActionsSecretSource.String(),
			expectedSecrets:      actionsDecryptedSecrets,
		},
		{
			name:                 "Uses no secrets for fork pull_request run",
			setupForkPR:          true,
			actor:                &metadata.WorkflowMetadataActor{},
			expectedSecretSource: workflowbuild.NoSecretSource.String(),
			expectedSecrets:      noSecrets,
		},
		{
			name:                 "Uses Dependabot secrets for Dependabot-triggered pull_request run",
			setupForkPR:          false,
			actor:                &metadata.WorkflowMetadataActor{IsDependabot: true},
			expectedSecretSource: workflowbuild.DependabotSecretSource.String(),
			expectedSecrets:      dependabotDecryptedSecrets,
		},
	}

	for _, tc := range testCases {

		s.Run(tc.name, func() {
			s.invoker.workflowMetadata.Actor = tc.actor

			if tc.setupForkPR {
				setupUntrustedAuthorTests(s, true, nil)
			} else {
				setupNonForkPRTests(s)
			}

			mockGitHubClient := &ghclient.MockClient{}
			mockTwirpClient := &ghtwirp.MockClient{}
			mockAzpClient := &azpclient.MockRepositoryClient{}

			actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
				IsExecutionAllowed: true,
			}

			mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
			mockTwirpClient.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
			mockTwirpClient.EXPECT().ShouldPullRequestWorkflowsRunForUser(mock.Anything, mock.Anything, mock.Anything).Return(true, nil).Once()
			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)

			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.OptOutOfCacheServiceV2, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceProximaFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.BlockArtifactsV3Exempted, mock.Anything).Return(false)

			mockGitHubClient.On("CreateCheckSuite",
				mock.Anything,
				mock.Anything,
			).Return(&ghclient.CreateCheckSuiteResponse{
				WorkflowRun: &ghclient.CheckSuiteWorkflowRun{},
			}, nil)

			// Arbitrary
			azpBuild := &azpclient.Build{ID: 123}

			mockAzpClient.On("Queue", mock.Anything, mock.Anything, mock.Anything, mock.Anything, tc.expectedSecretSource, tc.expectedSecrets, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)

			s.invoker.azpClient = mockAzpClient
			s.invoker.ghClient = mockGitHubClient
			s.invoker.ghTwirpClient = mockTwirpClient
			s.ghtwirp = mockTwirpClient

			// Need to be on test suite, so we can assert expectations
			s.azpClient = mockAzpClient
			s.setupSecretStoreMocks()
			s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, strconv.Itoa(azpBuild.ID)).Return(nil)
			s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
				return msg.Status == hydroV0.QueueRun_SUCCESS
			})).Return()

			file := workflowparser.Workflow{
				Path: "./github/workflows/ci.yaml",
				File: types.ResolvedFile{
					Path: "./github/workflows/ci.yaml",
				},
			}
			err := s.invoker.Run(context.Background(), &model.Workflow{
				Identifier: "CI",
				Path:       file.Path,
				On: &model.OnEvent{
					Event: flowevents.PullRequest,
				},
				File: file.File,
			}, &file, false)

			s.Assert().Nil(err)
			s.azpClient.AssertExpectations(s.T())
		})

	}
}

func (s *buildInvokerTest) TestGetSecretStore() {
	noSecrets := map[string]string{}

	headID := int64(1)
	baseID := int64(2)
	sourceRepo := &githubgo.Repository{
		ID: &baseID,
	}
	nonForkPR := &githubgo.PullRequest{
		Head: &githubgo.PullRequestBranch{
			Repo: sourceRepo,
		},
		Base: &githubgo.PullRequestBranch{
			Repo: sourceRepo,
		},
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

	nonForkPREvents := []flowevents.GitHubEvent{
		&githubgo.PullRequestEvent{PullRequest: nonForkPR},
		&githubgo.PullRequestReviewEvent{PullRequest: nonForkPR},
		&githubgo.PullRequestReviewCommentEvent{PullRequest: nonForkPR},
	}

	forkPREvents := []flowevents.GitHubEvent{
		&githubgo.PullRequestEvent{PullRequest: forkPR},
		&githubgo.PullRequestReviewEvent{PullRequest: forkPR},
		&githubgo.PullRequestReviewCommentEvent{PullRequest: forkPR},
	}

	testCases := []struct {
		name                string
		event               string
		ghEvents            []flowevents.GitHubEvent
		actor               *metadata.WorkflowMetadataActor
		forkPolicies        []types.ForkPRWorkflowsPolicy
		expectedSecretStore workflowbuild.SecretSource
		expectedSecrets     map[string]string
	}{
		{
			name:  "handles nil values",
			event: "",
			ghEvents: []flowevents.GitHubEvent{
				struct{}{},
			},
			actor:               &metadata.WorkflowMetadataActor{},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.NoSecretSource,
			expectedSecrets:     noSecrets,
		},
		{
			name:  "handles unknown event type",
			event: "shiny_new_event_type",
			ghEvents: []flowevents.GitHubEvent{
				struct{}{},
			},
			actor:               &metadata.WorkflowMetadataActor{},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.NoSecretSource,
			expectedSecrets:     noSecrets,
		},
		{
			name: "Actions secret store for non-PR webhook events",
			ghEvents: []flowevents.GitHubEvent{
				&githubgo.IssueEvent{},
				&githubgo.IssueCommentEvent{},
				&githubgo.CreateEvent{},
				&githubgo.DeleteEvent{},
				&githubgo.GollumEvent{},
				&githubgo.PushEvent{},
			},
			actor:               &metadata.WorkflowMetadataActor{},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.ActionsSecretSource,
			expectedSecrets:     actionsDecryptedSecrets,
		},
		{
			name:                "Actions secret store for non-fork PR events",
			ghEvents:            nonForkPREvents,
			actor:               &metadata.WorkflowMetadataActor{},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.ActionsSecretSource,
			expectedSecrets:     actionsDecryptedSecrets,
		},
		{
			name:                "Nil secret store for fork PR events",
			ghEvents:            forkPREvents,
			actor:               &metadata.WorkflowMetadataActor{},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.NoSecretSource,
			expectedSecrets:     noSecrets,
		},
		{
			name:  "Actions secret store for pull_request_target (fork or non-fork)",
			event: "pull_request_target",
			ghEvents: []flowevents.GitHubEvent{
				&githubgo.PullRequestEvent{PullRequest: forkPR},
				&githubgo.PullRequestEvent{PullRequest: nonForkPR},
			},
			actor:               &metadata.WorkflowMetadataActor{},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.ActionsSecretSource,
			expectedSecrets:     actionsDecryptedSecrets,
		},
		{
			name: "Actions secret store for dynamic workflows",
			ghEvents: []flowevents.GitHubEvent{
				&flowevents.DynamicEvent{
					Workflow: "name: CI\n  on: push\n  steps:",
					Ref:      "refs/heads/main",
					Slug:     "debug",
				},
				// arbitrary dynamic event
				&flowevents.DynamicEvent{},
			},
			actor:               &metadata.WorkflowMetadataActor{},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.ActionsSecretSource,
			expectedSecrets:     actionsDecryptedSecrets,
		},
		{
			name: "Actions secret store for schedule run",
			ghEvents: []flowevents.GitHubEvent{
				&flowevents.ScheduleEvent{},
			},
			actor:               &metadata.WorkflowMetadataActor{},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.ActionsSecretSource,
			expectedSecrets:     actionsDecryptedSecrets,
		},
		{
			name: "Nil secret store for workflow_call",
			ghEvents: []flowevents.GitHubEvent{
				&flowevents.WorkflowCallEvent{},
			},
			actor:               &metadata.WorkflowMetadataActor{},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.NoSecretSource,
			expectedSecrets:     noSecrets,
		},
		// Dependabot tests
		{
			name: "Dependabot: Nil secret store for dynamic workflows",
			ghEvents: []flowevents.GitHubEvent{
				&flowevents.DynamicEvent{},
			},
			actor:               &metadata.WorkflowMetadataActor{IsDependabot: true},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.NoSecretSource,
			expectedSecrets:     noSecrets,
		},
		{
			name: "Dependabot: Dependabot secret store for push",
			ghEvents: []flowevents.GitHubEvent{
				&githubgo.PushEvent{},
			},
			actor:               &metadata.WorkflowMetadataActor{IsDependabot: true},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.DependabotSecretSource,
			expectedSecrets:     dependabotDecryptedSecrets,
		},
		{
			name:                "Dependabot: Dependabot secret store for pull request",
			ghEvents:            nonForkPREvents,
			actor:               &metadata.WorkflowMetadataActor{IsDependabot: true},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.DependabotSecretSource,
			expectedSecrets:     dependabotDecryptedSecrets,
		},
		{
			// If Dependabot somehow triggered a run for a fork PR
			name:                "Dependabot: Nil secret store for fork pull request",
			ghEvents:            forkPREvents,
			actor:               &metadata.WorkflowMetadataActor{IsDependabot: true},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.NoSecretSource,
			expectedSecrets:     noSecrets,
		},
		{
			name:  "Dependabot: Actions secret store for pull_request_target (fork or non-fork)",
			event: "pull_request_target",
			ghEvents: []flowevents.GitHubEvent{
				&githubgo.PullRequestEvent{PullRequest: forkPR},
				&githubgo.PullRequestEvent{PullRequest: nonForkPR},
			},
			actor:               &metadata.WorkflowMetadataActor{IsDependabot: true},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.ActionsSecretSource,
			expectedSecrets:     actionsDecryptedSecrets,
		},
		{
			name: "Dependabot: Actions secret store for default branch webhook events",
			ghEvents: []flowevents.GitHubEvent{
				&githubgo.IssueEvent{},
				&githubgo.IssueCommentEvent{},
				&githubgo.DeleteEvent{},
				&githubgo.GollumEvent{},
			},
			actor:               &metadata.WorkflowMetadataActor{IsDependabot: true},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.ActionsSecretSource,
			expectedSecrets:     actionsDecryptedSecrets,
		},
		{
			// Dependabot creates PRs that bump action versions in workflows (e.g. actions/checkout@v1 => actions/checkout@v2).
			// Therefore, Dependabot can be a schedule workflow's last committer, making it the triggering actor.
			name: "Dependabot: Actions secret store for schedule run",
			ghEvents: []flowevents.GitHubEvent{
				&flowevents.ScheduleEvent{},
			},
			actor:               &metadata.WorkflowMetadataActor{IsDependabot: true},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.ActionsSecretSource,
			expectedSecrets:     actionsDecryptedSecrets,
		},
		{
			name: "Dependabot: Nil secret store for workflow_call",
			ghEvents: []flowevents.GitHubEvent{
				&flowevents.WorkflowCallEvent{},
			},
			actor:               &metadata.WorkflowMetadataActor{IsDependabot: true},
			forkPolicies:        []types.ForkPRWorkflowsPolicy{types.ForkPRWorkflowsRunWorkflows},
			expectedSecretStore: workflowbuild.NoSecretSource,
			expectedSecrets:     noSecrets,
		},
	}

	for _, tc := range testCases {
		if len(tc.ghEvents) == 0 {
			panic("you must specify one or more events")
		}

		if len(tc.forkPolicies) == 0 {
			panic("you must specify one or more fork policies")
		}

		for _, ghe := range tc.ghEvents {
			var eventName string
			if tc.event != "" {
				eventName = tc.event
			} else if ghe != struct{}{} {
				var ok bool
				if eventName, ok = eventNameMap[reflect.TypeOf(ghe)]; !ok {
					panic(fmt.Sprintf("No mapping for %T", ghe))
				}
			}

			for _, forkPolicy := range tc.forkPolicies {
				s.Run(fmt.Sprintf("%s (event: %s)(forkPolicy: %s)(isDependabot: %v)(expectedSecretStore: %s)", tc.name, eventName, forkPolicy, tc.actor.IsDependabot, tc.expectedSecretStore), func() {

					s.invoker.workflowMetadata.Actor = tc.actor
					s.invoker.data.ForkPRWorkflowsPolicy = forkPolicy
					ctx := context.Background()
					wfb := &build.WorkflowBuild{
						Event:       eventName,
						GitHubEvent: ghe,
					}
					ss := s.getSecretStore(wfb)
					s.Assert().NotNil(ss)
					s.Assert().Equal(tc.expectedSecretStore, ss.GetSecretSource())
					s.Assert().Equal(tc.expectedSecrets, ss.GetDecryptedSecrets(ctx))
				})

			}
		}
	}
}

func (s *buildInvokerTest) TestEvaluateConcurrency_WithContext() {
	tests := []struct {
		name        string
		concurrency string
		expectedErr bool
	}{
		{
			name:        "no context",
			concurrency: "production",
			expectedErr: false,
		},
		{
			name:        "github context",
			concurrency: "${{github.ref}}",
			expectedErr: false,
		},
		{
			name:        "inputs context",
			concurrency: "${{inputs.foo}}",
			expectedErr: false,
		},
		{
			name:        "vars context",
			concurrency: "${{vars.foo}}",
			expectedErr: false,
		},
		{
			name:        "invalid context",
			concurrency: "${{matrix.foo}}",
			expectedErr: true,
		},
	}

	for _, tt := range tests {
		s.Run(tt.name, func() {
			s.recordingLogger.Reset()
			setupPullRequestTest(s, false, true, nil)
			setupExpectationsForQueuedRun(s)

			mockTwirpClient := &ghtwirp.MockClient{}

			mockTwirpClient.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)

			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.OptOutOfCacheServiceV2, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(true)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(true)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.EvaluateConcurrencyFlag, mock.Anything).Return(true)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceProximaFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.BlockArtifactsV3Exempted, mock.Anything).Return(false)

			mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(types.GlobalID("id_next"), nil).Times(7)

			s.invoker.data.WorkflowFeatureFlags.ConfigurationVariablesEnabled = true

			mockVarzClient := &varz.MockClient{}
			mockVarzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(
				&varz.RepositoryVariablesResponse{RepositoryVariables: map[string]string{"VAR_KEY": "dmFyX3ZhbA=="}, OrganizationVariables: map[string]string{"VAR_KEY": "dmFyX3ZhbF8w"}}, nil)
			s.invoker.varzClient = mockVarzClient
			s.invoker.ghTwirpClient = mockTwirpClient

			ctx := context.Background()

			workflow := `
on: push
name: "simple"
concurrency: ` + tt.concurrency + `
jobs:
  thing:
    runs-on: ubuntu-latest
    steps:
    - run: echo "hello"`
			parsed, err := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: ".github/workflows/main.yml"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
			s.Require().NoError(err)
			err = s.invoker.Run(context.Background(), &model.Workflow{
				Identifier: "CI",
				Path:       parsed.Path,
				On: &model.OnEvent{
					Event: flowevents.Push,
				},
				File: parsed.File,
			}, parsed, false)

			if tt.expectedErr {
				s.NotContains(s.recordingLogger.String(), "Queueing build with parsed workflow attached")
			} else {
				s.assertLogged("Queueing build with parsed workflow attached")
			}
		})
	}

}

func (s *buildInvokerTest) TestConcurrency_PassedToQueueFunction() {
	tests := []struct {
		name             string
		group            string
		cancelInProgress bool
		expectedErr      bool
	}{
		{
			name:             "concurrency 1",
			group:            "foo",
			cancelInProgress: false,
			expectedErr:      false,
		},
		{
			name:             "concurrency 2",
			group:            "foo",
			cancelInProgress: true,
			expectedErr:      false,
		},
	}

	for _, tt := range tests {
		s.Run(tt.name, func() {
			s.recordingLogger.Reset()
			setupPullRequestTest(s, false, true, nil)
			setupExpectationsForQueuedRun(s)

			mockTwirpClient := &ghtwirp.MockClient{}

			mockTwirpClient.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)

			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.OptOutOfCacheServiceV2, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(true)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(true)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.EvaluateConcurrencyFlag, mock.Anything).Return(true)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceProximaFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.BlockArtifactsV3Exempted, mock.Anything).Return(false)

			mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(types.GlobalID("id_next"), nil).Times(7)

			s.invoker.data.WorkflowFeatureFlags.ConfigurationVariablesEnabled = true

			mockVarzClient := &varz.MockClient{}
			mockVarzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(
				&varz.RepositoryVariablesResponse{RepositoryVariables: map[string]string{"VAR_KEY": "dmFyX3ZhbA=="}, OrganizationVariables: map[string]string{"VAR_KEY": "dmFyX3ZhbF8w"}}, nil)
			s.invoker.varzClient = mockVarzClient
			s.invoker.ghTwirpClient = mockTwirpClient

			ctx := context.Background()

			cs := &parser.ConcurrencySetting{
				Group:            tt.group,
				CancelInProgress: tt.cancelInProgress,
			}

			s.azpClient = &azpclient.MockRepositoryClient{}
			azpBuild := &azpclient.Build{ID: 123}
			s.azpClient.On("Queue", mock.Anything, mock.Anything, s.invoker.receiverURL, s.invoker.resultsReceiverURL, mock.Anything, mock.Anything, mock.Anything, mock.Anything, cs, mock.Anything, mock.Anything).Return(azpBuild, nil).Once()
			s.invoker.azpClient = s.azpClient

			workflow := `
on: push
name: "simple"
concurrency:
  group: ` + tt.group + `
  cancel-in-progress: ` + strconv.FormatBool(tt.cancelInProgress) + `
jobs:
  thing:
    runs-on: ubuntu-latest
    steps:
    - run: echo "hello"`
			parsed, err := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: ".github/workflows/main.yml"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
			s.Require().NoError(err)
			err = s.invoker.Run(context.Background(), &model.Workflow{
				Identifier: "CI",
				Path:       parsed.Path,
				On: &model.OnEvent{
					Event: flowevents.Push,
				},
				File: parsed.File,
			}, parsed, false)

			if tt.expectedErr {
				s.NotContains(s.recordingLogger.String(), "Queueing build with parsed workflow attached")
			} else {
				s.assertLogged("Queueing build with parsed workflow attached")
			}
		})
	}
}

func (s *buildInvokerTest) TestRunName() {
	tests := []struct {
		desc          string
		runName       string
		parsedRunName string
		errMsg        string
	}{
		{
			desc:          "no expressions",
			runName:       "hello",
			parsedRunName: "hello",
		},
		{
			desc:          "single expression",
			runName:       "${{ 1 == 2 }}",
			parsedRunName: "false",
		},
		{
			desc:          "literal with expression",
			runName:       "hello ${{ 'world' }}",
			parsedRunName: "hello world",
		},
		{
			desc:          "single expression with context",
			runName:       "hello ${{github.event_name}}",
			parsedRunName: "hello pull_request",
		},
		{
			desc:    "unclosed expression",
			runName: "${{",
			errMsg:  "The workflow is not valid. main.yml (Line: 4, Col: 11): The expression is not closed. An unescaped ${{ sequence was found, but the closing }} sequence was not found.",
		},
		{
			desc:    "lexing error",
			runName: "${{ 1 + 'a' }}",
			errMsg:  "The workflow is not valid. main.yml (Line: 4, Col: 11): Unexpected symbol: '+'. Located at position 3 within expression: 1 + 'a'",
		},
		{
			desc:    "undefined function",
			runName: "${{ undefined() }}",
			errMsg:  "The workflow is not valid. main.yml (Line: 4, Col: 11): Unrecognized function: 'undefined'. Located at position 1 within expression: undefined()",
		},
		{
			desc:          "run name evaluates to empty string",
			runName:       "${{ format('') }}",
			parsedRunName: "", // We don't want to see UpdateWorkflowRun called on the twirp client in this case, but it is not an error either
		},
		{
			desc:          "run name evaluates to variable",
			runName:       "${{ vars.VAR_KEY }}",
			parsedRunName: "var_val",
		},
		{
			desc:          "evaluated run name should be truncated",
			runName:       "${{ format('{0}', '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789') }}", // 520 characters long
			parsedRunName: "01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678...",
		},
		{
			desc:          "run name evaluates to whitespace string",
			runName:       "${{ format(' ') }}",
			parsedRunName: "", // We don't want to see UpdateWorkflowRun called on the twirp client in this case, but it is not an error either
		},
		{
			desc:    "empty expression",
			runName: "${{ }}",
			errMsg:  "The workflow is not valid. main.yml (Line: 4, Col: 11): An expression was expected",
		},
		{
			desc:    "error in expression with literal",
			runName: "${{ 1 < }} hello",
			errMsg:  "The workflow is not valid. main.yml (Line: 4, Col: 11): Unexpected end of expression: '<'. Located at position 3 within expression: 1 <",
		},
	}

	for _, tt := range tests {
		s.Run(tt.desc, func() {
			s.recordingLogger.Reset()
			setupPullRequestTest(s, false, true, nil)
			setupExpectationsForQueuedRun(s)

			mockTwirpClient := &ghtwirp.MockClient{}

			mockTwirpClient.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.OptOutOfCacheServiceV2, mock.Anything).Return(false).Maybe()
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceProximaFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.BlockArtifactsV3Exempted, mock.Anything).Return(false)

			if tt.parsedRunName != "" {
				mockTwirpClient.On("UpdateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, tt.parsedRunName).Return(nil).Once()
			}
			mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(types.GlobalID("id_next"), nil).Times(7)

			s.invoker.data.WorkflowFeatureFlags.ConfigurationVariablesEnabled = true
			mockVarzClient := &varz.MockClient{}
			mockVarzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(
				&varz.RepositoryVariablesResponse{RepositoryVariables: map[string]string{"VAR_KEY": "dmFyX3ZhbA=="}, OrganizationVariables: map[string]string{"VAR_KEY": "dmFyX3ZhbF8w"}}, nil)
			s.invoker.varzClient = mockVarzClient
			s.invoker.ghTwirpClient = mockTwirpClient

			ctx := context.Background()

			workflow := `
on: push
name: "simple"
run-name: ` + tt.runName + `
jobs:
  thing:
    steps:
    - uses: owner/repo@master`
			parsed, err := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "main.yml"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
			s.Require().NoError(err)
			err = s.invoker.Run(context.Background(), &model.Workflow{
				Identifier: "CI",
				Path:       parsed.Path,
				On: &model.OnEvent{
					Event: flowevents.Push,
				},
				File:              parsed.File,
				RunNameExpression: tt.runName,
			}, parsed, false)

			if tt.errMsg != "" {
				s.Require().Error(err)
				s.Assert().Equal(tt.errMsg, err.Error())
			} else {
				s.Assert().Nil(err)
				mockTwirpClient.AssertExpectations(s.T())
			}
		})
	}
}

func (s *buildInvokerTest) TestVariablesThresholdBreachEmitsAnnotation() {
	setupPullRequestTest(s, false, true, nil)
	setupExpectationsForQueuedRunWithThresholdExceededAnnotations(s, false)
	repoVariables := generateVariableResponseMap("repo_", 256*1024) // 256KB
	mockTwirpClient := s.ghtwirp

	mockTwirpClient.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)

	mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(types.GlobalID("id_next"), nil)

	s.invoker.data.WorkflowFeatureFlags.ConfigurationVariablesEnabled = true
	s.invoker.data.WorkflowFeatureFlags.SizeRestrictedVarCountEnabled = true

	mockVarzClient := &varz.MockClient{}
	mockVarzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(
		&varz.RepositoryVariablesResponse{RepositoryVariables: repoVariables, OrganizationVariables: map[string]string{"VAR_KEY": "dmFyX3ZhbF8w"}}, nil)
	s.invoker.varzClient = mockVarzClient
	s.invoker.ghTwirpClient = mockTwirpClient
	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient.On("Queue", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)

	ctx := context.Background()
	workflow := `
on: push
name: "simple"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`

	parsed, err := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "main.yml"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	s.Require().NoError(err)
	err = s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       parsed.Path,
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
		File: parsed.File,
	}, parsed, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestVariablesThresholdBreachEmitsAnnotation_GHES() {
	setupPullRequestTest(s, false, true, nil)
	setupExpectationsForQueuedRunWithThresholdExceededAnnotations(s, true)
	repoVariables := generateVariableResponseMap("repo_", 11*1024*1024) // 11 MB
	mockTwirpClient := s.ghtwirp

	mockTwirpClient.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)

	mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false).Maybe()
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	mockTwirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)

	mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(types.GlobalID("id_next"), nil)

	s.invoker.data.WorkflowFeatureFlags.ConfigurationVariablesEnabled = true
	s.invoker.data.WorkflowFeatureFlags.SizeRestrictedVarCountEnabled = true
	s.invoker.isEnterprise = true

	mockVarzClient := &varz.MockClient{}
	mockVarzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(
		&varz.RepositoryVariablesResponse{RepositoryVariables: repoVariables, OrganizationVariables: map[string]string{"VAR_KEY": "dmFyX3ZhbF8w"}}, nil)
	s.invoker.varzClient = mockVarzClient
	s.invoker.ghTwirpClient = mockTwirpClient
	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient.On("Queue", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)

	ctx := context.Background()
	workflow := `
on: push
name: "simple"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`

	parsed, err := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "main.yml"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	s.Require().NoError(err)
	err = s.invoker.Run(context.Background(), &model.Workflow{
		Identifier: "CI",
		Path:       parsed.Path,
		On: &model.OnEvent{
			Event: flowevents.Push,
		},
		File: parsed.File,
	}, parsed, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestRequiredWorkflowExecution() {
	setupExpectationsForQueuedRequiredWorkflowRun(s)
	setupUntrustedAuthorTests(s, true, nil)
	path := "required/1234/required_workflows/lint_workflows/golint.yaml"

	fileReference := types.WorkflowFileReference{
		Path: path,
		Ref:  types.GitRef("refs/heads/main"),
		SHA:  types.CommitSha("936cd8cad458e56910e6480bf786f930f0a5ebe9"),
	}

	mainFile := workflowparser.Workflow{
		Path:          path,
		FileReference: fileReference,
		File: types.ResolvedFile{
			Path: path,
			SHA:  "936cd8cad458e56910e6480bf786f930f0a5ebe9",
			Text: `
name: CI
on: pull_request
name: "simple"
jobs:
	lint:
	steps:
	- uses: owner/repo@master`,
		},
	}

	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(true)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)

	err := s.invoker.Run(context.Background(), &model.Workflow{
		Identifier:    "CI",
		Path:          mainFile.Path,
		FileReference: fileReference,
		On: &model.OnEvent{
			Event: flowevents.PullRequest,
		},
		File: mainFile.File,
	}, &mainFile, false)

	s.Assert().Nil(err)
}

func (s *buildInvokerTest) TestCreateWorkflowRunToResults() {
	type sendWorkflowRunTest struct {
		description string
		expectErr   bool
		isReRun     bool
		setupExpect func()
	}

	setupSuccess := func() {
		s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil).Once()
	}

	setupErr := func() {
		testErr := errors.New("test error")
		s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(testErr).Once()
	}

	tests := []sendWorkflowRunTest{
		{"if non-enterprise, and use twirp, workflow is successfully sent to results via twirp sync call ", false, false, setupSuccess},
		{"if non-enterprise and sending workflow to results throws err, run is not queued", true, false, setupErr},
		{"if non-enterprise, re-run workflow is successfully sent to results once and queued ", false, true, setupSuccess},
	}

	for _, tt := range tests {
		s.Run(tt.description, func() {
			workflow := setupCreateWorkflowRunResultsTest(s, tt.expectErr, tt.isReRun)

			ctx := context.Background()
			parsed, err := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "main.yml"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
			s.Require().NoError(err)

			s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlagForHardCodedHostedLabels, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)

			mockGitHubClient := &ghclient.MockClient{}
			mockGitHubClient.On("CreateCheckSuite",
				mock.Anything,
				mock.Anything,
			).Return(&ghclient.CreateCheckSuiteResponse{
				WorkflowRun: &ghclient.CheckSuiteWorkflowRun{},
			}, nil)

			tt.setupExpect()
			err = s.invoker.Run(context.Background(), &model.Workflow{
				Identifier: "CI",
				Path:       parsed.Path,
				File:       parsed.File,
			}, parsed, false)
			if tt.expectErr {
				s.Require().Error(err)
			} else {
				s.Nil(err)
			}
			s.resultsClient.AssertExpectations(s.T())
			s.mockEmitter.AssertExpectations(s.T())
		})
	}
}

func (s *buildInvokerTest) TestCreateWorkflowRunToResults_ProvideRunStartDelaySLOInfo() {
	type sendWorkflowRunTest struct {
		description      string
		eventName        string
		customerLabel    string
		isReRun          bool
		workflowFilePath string
		setupFunc        func()
	}

	tests := []sendWorkflowRunTest{
		{
			"provide run start delay SLO required info to Results",
			"push",
			"",
			false,
			".github/workflows/main.yml",
			func() {
				s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil).Run(func(args mock.Arguments) {
					sloMetadata := args.Get(4).(*results.RunStartDelaySLOMetadata)
					s.Assert().Equal("push", sloMetadata.EventName)
					s.Assert().Equal("none", sloMetadata.CustomerLabel)
					s.Assert().Equal("", sloMetadata.DynamicWorkflowIntegrator)
					s.Assert().False(sloMetadata.IgnoreFromRunStartDelay)
				}).Once()
			},
		},
		{
			"schedule run should be ignored from run start delay SLO",
			"schedule",
			"",
			false,
			".github/workflows/main.yml",
			func() {
				s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil).Run(func(args mock.Arguments) {
					sloMetadata := args.Get(4).(*results.RunStartDelaySLOMetadata)
					s.Assert().Equal("schedule", sloMetadata.EventName)
					s.Assert().Equal("none", sloMetadata.CustomerLabel)
					s.Assert().Equal("", sloMetadata.DynamicWorkflowIntegrator)
					s.Assert().True(sloMetadata.IgnoreFromRunStartDelay)
				}).Once()
			},
		},
		{
			"provide customer label to Result services",
			"push",
			"top100",
			false,
			".github/workflows/main.yml",
			func() {
				s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil).Run(func(args mock.Arguments) {
					sloMetadata := args.Get(4).(*results.RunStartDelaySLOMetadata)
					s.Assert().Equal("push", sloMetadata.EventName)
					s.Assert().Equal("top100", sloMetadata.CustomerLabel)
					s.Assert().Equal("", sloMetadata.DynamicWorkflowIntegrator)
					s.Assert().False(sloMetadata.IgnoreFromRunStartDelay)
				}).Once()
			},
		},
		{
			"default customer label to none for Result services",
			"pull_request",
			"",
			false,
			".github/workflows/main.yml",
			func() {
				s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil).Run(func(args mock.Arguments) {
					sloMetadata := args.Get(4).(*results.RunStartDelaySLOMetadata)
					s.Assert().Equal("pull_request", sloMetadata.EventName)
					s.Assert().Equal("none", sloMetadata.CustomerLabel)
					s.Assert().Equal("", sloMetadata.DynamicWorkflowIntegrator)
					s.Assert().False(sloMetadata.IgnoreFromRunStartDelay)
				}).Once()
			},
		},
		{
			"rerun ignored from Run Start Delay",
			"pull_request",
			"",
			true,
			".github/workflows/main.yml",
			func() {
				s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil).Run(func(args mock.Arguments) {
					sloMetadata := args.Get(4).(*results.RunStartDelaySLOMetadata)
					s.Assert().Equal("pull_request", sloMetadata.EventName)
					s.Assert().Equal("none", sloMetadata.CustomerLabel)
					s.Assert().Equal("", sloMetadata.DynamicWorkflowIntegrator)
					s.Assert().True(sloMetadata.IgnoreFromRunStartDelay)
				}).Once()
			},
		},
		{
			"dynamic workflow to Results service",
			"dynamic",
			"",
			false,
			"dynamic/pages/pages-build-deployment",
			func() {
				s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil).Run(func(args mock.Arguments) {
					sloMetadata := args.Get(4).(*results.RunStartDelaySLOMetadata)
					s.Assert().Equal("dynamic", sloMetadata.EventName)
					s.Assert().Equal("none", sloMetadata.CustomerLabel)
					s.Assert().Equal("pages", sloMetadata.DynamicWorkflowIntegrator)
					s.Assert().False(sloMetadata.IgnoreFromRunStartDelay)
				}).Once()
			},
		},
		{
			"send event origin time to Results service",
			"push",
			"top100",
			false,
			".github/workflows/main.yml",
			func() {
				s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil).Run(func(args mock.Arguments) {
					sloMetadata := args.Get(4).(*results.RunStartDelaySLOMetadata)
					s.Assert().Equal("push", sloMetadata.EventName)
					s.Assert().Equal("top100", sloMetadata.CustomerLabel)
					s.Assert().Equal("", sloMetadata.DynamicWorkflowIntegrator)
					s.Assert().False(sloMetadata.IgnoreFromRunStartDelay)
					s.Assert().False(sloMetadata.EventCreatedAt.IsZero())
				}).Once()
			},
		},
	}

	for _, tt := range tests {
		s.Run(tt.description, func() {
			workflow := setupCreateWorkflowRunResultsTest(s, false, tt.isReRun)
			s.invoker.invocation.Event = InvokingEvent{
				Name: tt.eventName,
			}

			s.invoker.labeler = customerlabels.NewNoopCustomerLabeler()
			if tt.customerLabel == "top100" {
				s.invoker.labeler, _ = customerlabels.NewCustomerLabeler(s.invoker.data.NWO.Owner, "")
			}

			s.wfb.Backend = types.WorkflowBackendRunService
			runStampURL := "https://run-service.github.app"
			s.runServiceClient.On("StartPlan", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
				Return(uuid.NewString(), runStampURL, nil).Once()
			s.invoker.runServiceClient = s.runServiceClient
			s.ghtwirp.On("UpdateWorkflowRunExecution", mock.Anything, mock.Anything, mock.Anything, runStampURL).Return(nil)
			s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil).Once()

			ctx := context.Background()
			parsed, err := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: tt.workflowFilePath}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
			s.Require().NoError(err)

			s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(true)
			s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
			mockGitHubClient := &ghclient.MockClient{}
			mockGitHubClient.On("CreateCheckSuite",
				mock.Anything,
				mock.Anything,
			).Return(&ghclient.CreateCheckSuiteResponse{
				WorkflowRun: &ghclient.CheckSuiteWorkflowRun{},
			}, nil)

			s.azpClient = &azpclient.MockRepositoryClient{}
			s.azpClient.On("GetRunTenantInfo").Return(&runtwirpv1.TenantInfo{
				Id: "tenant_abc",
				Urls: map[string]string{
					"PipelinesServiceUrl": "https://pipelines.example.com",
					"CacheServiceUrl":     "https://cache.example.com",
				},
			})
			s.invoker.azpClient = s.azpClient

			tt.setupFunc()
			err = s.invoker.Run(context.Background(), &model.Workflow{
				Identifier: "CI",
				Path:       parsed.Path,
				File:       parsed.File,
			}, parsed, false)
			s.Require().Nil(err)
			s.resultsClient.AssertExpectations(s.T())
			s.mockEmitter.AssertExpectations(s.T())
		})
	}
}

func (s *buildInvokerTest) Test_Run_Sets_Environment_URLs() {
	apiHost := "https://api.github.com"
	serverhost := "https://github.com"
	apiPath := "/api/v3"
	graphqlPath := "/graphql"

	expectedServerURL := serverhost
	expectedAPIURL := fmt.Sprintf("%s%s", apiHost, apiPath)
	expectedGraphQLURL := fmt.Sprintf("%s%s", apiHost, graphqlPath)

	stubTenant := ghtenant.GitHubTenant{
		Slug: "i-am-a-tenant",
		ID:   int64(1),
	}

	expectedMultiTenantServerURL := fmt.Sprintf("https://%s.github.com", stubTenant.Slug)
	expectedMultiTenantAPIURL := fmt.Sprintf("https://api.%s.github.com/api/v3", stubTenant.Slug)
	expectedMultiTenantGraphQLURL := fmt.Sprintf("https://api.%s.github.com/graphql", stubTenant.Slug)

	tests := []struct {
		desc               string
		isMultiTenant      bool
		githubTenant       ghtenant.GitHubTenant
		shouldErr          bool
		expectedServerURL  string
		expectedAPIURL     string
		expectedGraphQLURL string
	}{
		{
			desc:               "non_multi_tenant",
			isMultiTenant:      false,
			shouldErr:          false,
			expectedServerURL:  expectedServerURL,
			expectedAPIURL:     expectedAPIURL,
			expectedGraphQLURL: expectedGraphQLURL,
		},
		{
			desc:               "multi_tenant/tenant_slug_set",
			isMultiTenant:      true,
			shouldErr:          false,
			githubTenant:       stubTenant,
			expectedServerURL:  expectedMultiTenantServerURL,
			expectedAPIURL:     expectedMultiTenantAPIURL,
			expectedGraphQLURL: expectedMultiTenantGraphQLURL,
		},
		{
			desc:          "multi_tenant/tenant_slug_not_set",
			isMultiTenant: true,
			shouldErr:     true,
		},
	}

	for _, tt := range tests {
		s.Run(tt.desc, func() {
			r := require.New(s.T())

			s.mockEmitter.On("EmitQueueRun", mock.Anything).Return()

			mockErrorHandler := &MockWorkflowStartErrHandler{}
			mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)

			s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier1, nil)
			s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, mock.Anything, mock.Anything).Return(false)
			s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, mock.Anything, mock.Anything).Return(false)

			s.repo.EXPECT().
				Persist(
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					tt.githubTenant,
				).
				Return(int64(1), types.NewRandomWorkflowExecutionID(), time.Time{}, false, nil)

			s.repo.On(
				"SetCheckSuiteInformation",
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
			).Return(nil)

			s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, mock.Anything).Return(nil)

			ghClient := &ghclient.MockClient{}
			ghClient.On("CreateCheckSuite", mock.Anything, mock.Anything).
				Return(&ghclient.CreateCheckSuiteResponse{WorkflowRun: &ghclient.CheckSuiteWorkflowRun{}}, nil)

			s.mockEmitter.On("EmitQueueRun", mock.Anything).Return()

			filter := &workflowbuild.MockWorkflowFilter{}
			filter.On("ShouldRun", mock.Anything, mock.Anything).Return(true)

			mockTokenFactory := &workflowbuild.MockTokenFactory{}
			mockTokenFactory.On(
				"CalculateRunPermissions", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything,
			).Return(&tokens.PermissionSettings{}, nil)

			urlProviderFactory, err := utils.NewURLProviderFactory(apiHost, apiPath, graphqlPath, serverhost, tt.isMultiTenant)
			r.NoError(err)

			mockAzpClient := &azpclient.MockRepositoryClient{}
			azpQueueCall := mockAzpClient.On("Queue",
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything).Return(&azpclient.Build{}, nil)

			// queueing the workflow build with the azp client is the last step in the run function
			// so this is where we can assert that the build environment urls are set correctly
			azpQueueCall.RunFn = func(args mock.Arguments) {
				build := args.Get(1).(*build.WorkflowBuild)
				r.Equal(tt.expectedServerURL, build.RunEnvironment.ServerURL)
				r.Equal(tt.expectedAPIURL, build.RunEnvironment.APIURL)
				r.Equal(tt.expectedGraphQLURL, build.RunEnvironment.GraphQLURL)
			}

			// minimum set of invocation data to get a build to queue
			invocation := Invocation{
				Event:           InvokingEvent{},
				ExecutingActor:  InvokingActor{},
				TriggeringActor: InvokingActor{},
				Target: invocationTarget{
					RepositoryID: types.NewGlobalID(context.Background(), "R_kgDOAAFjIg"),
					GitHubTenant: tt.githubTenant,
				},
				ExistingCheckSuite:     nil,
				ExistingExecutionID:    nil,
				RerunWebhookDeliveryID: "",
				RerunInfo:              nil,
				EnableDebugLogging:     false,
			}

			invocationData := types.WorkflowInvocationData{
				AllowsAllActions: true,
				PlanOwner: types.WorkflowInvocationPlanOwner{
					GlobalID: "E_kgAB", // global ID for github-inc (databaseID: 1)
				},
				References: types.WorkflowInvocationReferences{
					EventCommit: types.NewWorkflowInvocationReference("sha", "sha"),
				},
			}

			invoker := &buildInvoker{
				obs:                   NewTestObservability(observability.New(s.recordingLogger.Logger, statter.NullStatter())),
				azpClient:             mockAzpClient,
				workflowMetadata:      &metadata.WorkflowMetadata{},
				ghClient:              ghClient,
				ghTwirpClient:         s.ghtwirp,
				data:                  &invocationData,
				invocation:            invocation,
				outcome:               deployer.OrgCreationSuccess,
				filter:                filter,
				repo:                  s.repo,
				repositoryTenants:     &types.RepositoryTenants{},
				tokenFactory:          mockTokenFactory,
				actionsAppGlobalID:    "actions-app-global-id",
				dependabotAppGlobalID: "dependabot-app-global-id",
				kredzClient:           &kredz.MockClient{},
				secretDecryptor:       &earthsmoke.MockDecryptor{},
				keyGenerator:          hkdf.NewKeyGenerator([]byte{}),
				receiverURL:           "example.com",
				resultsReceiverURL:    "example.com/results",
				errorHandler:          mockErrorHandler,
				workflowSource:        workflowparser.NullWorkflowSource{},
				urlProviderFactory:    urlProviderFactory,
				reporter:              slometrics.New(s.mockEmitter),
				labeler:               customerlabels.NewNoopCustomerLabeler(),
				queueBuildRateLimiter: &rate.NullRateLimiter{},
				webhookRateLimiter:    &rate.NullRateLimiter{},
				resultsClient:         s.resultsClient,
			}

			ctx := context.Background()
			workflowText := `
on: push
name: "simple"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`

			parsedWorkflow, err := workflowparser.Parse(ctx,
				types.ResolvedFile{Text: workflowText, Path: "main.yml"},
				types.WorkflowFeatureFlags{},
				workflowparser.NullWorkflowSource{},
				launchutils.NewRuntimeHelper(false, "latest"),
				0,
				observability.NewNullObservability())

			r.NoError(err)

			workflow := model.Workflow{
				Identifier: "CI",
				Path:       parsedWorkflow.Path,
				On: &model.OnEvent{
					Event: flowevents.Push,
				},
				File: parsedWorkflow.File,
			}

			err = invoker.Run(ctx, &workflow, parsedWorkflow, false)
			if tt.shouldErr {
				r.Error(err)
			} else {
				r.Nil(err)
			}
		})
	}
}

func (s *buildInvokerTest) Test_shouldRunParserComparison() {
	tests := []struct {
		desc          string
		compareErrors bool
		comparePlans  bool
		rerunInfo     *types.RerunInfo
		resolvedFiles []types.ResolvedFile
		expect        bool
	}{
		{
			desc:   "all false",
			expect: false,
		},
		{
			desc:          "compareErrors true",
			compareErrors: true,
			expect:        true,
		},
		{
			desc:         "comparePlans true",
			comparePlans: true,
			expect:       true,
		},
		{
			desc:          "compareErrors and comparePlans true",
			compareErrors: true,
			comparePlans:  true,
			expect:        true,
		},
		{
			desc:         "comparePlans true, partial rerun, but only the root resolved workflow file",
			comparePlans: true,
			rerunInfo:    &types.RerunInfo{},
			resolvedFiles: []types.ResolvedFile{
				{
					Path: ".github/workflows/main.yml",
				},
			},
			expect: true,
		},
		{
			desc:         "comparePlans true, partial rerun, with additonal resolved files, should be false",
			comparePlans: true,
			rerunInfo:    &types.RerunInfo{},
			resolvedFiles: []types.ResolvedFile{
				{
					Path: ".github/workflows/main.yml",
				},
				{
					Path: ".github/workflows/called.yml",
				},
			},
			expect: false,
		},
	}

	for _, tt := range tests {
		s.Run(tt.desc, func() {
			b := &build.WorkflowBuild{}
			if tt.rerunInfo != nil {
				b.RerunInfo = tt.rerunInfo
			}
			if tt.resolvedFiles != nil {
				b.ResolvedFiles = tt.resolvedFiles
			}

			out := shouldRunParserComparison(tt.compareErrors, tt.comparePlans, b)
			s.Equal(tt.expect, out)
		})
	}
}

func (s *buildInvokerTest) Test_HandlesCreateCheckSuiteNotFoundErrors() {
	tests := []struct {
		desc string
		err  error
	}{
		{
			desc: "Not Found Error",
			err:  terrors.NewNotFoundError(errors.New("Could not resolve to Repository")),
		},
		{
			desc: "Wrapped Not Found Error",
			err:  errors.Wrap(terrors.NewNotFoundError(errors.New("Could not resolve to Repository")), "wrap wrap"),
		},
	}

	for _, tt := range tests {
		s.Run(tt.desc, func() {
			ctx := context.Background()
			mockErrorHandler := &MockWorkflowStartErrHandler{}
			mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)

			s.invoker.errorHandler = mockErrorHandler

			workflow := `
on: push
name: "simple"
jobs:
  thing:
      steps:
        - uses: owner/repo@main`

			mockTwirpClient := ghtwirp.NewMockClient(s.T())
			mockTwirpClient.EXPECT().GetTrustTier(mock.Anything, mock.Anything).Return(types.RepositoryTier1, nil)
			mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
			mockTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.RunServiceProximaFeatureFlag, mock.Anything).Return(false)

			s.ghtwirp = mockTwirpClient
			s.invoker.ghTwirpClient = mockTwirpClient

			s.repo.EXPECT().
				Persist(
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
					mock.Anything,
				).
				Return(int64(0), types.NewRandomWorkflowExecutionID(), time.Time{}, false, nil)

			mockGitHubClient := ghclient.NewMockClient(s.T())

			mockGitHubClient.On("CreateCheckSuite",
				mock.Anything,
				mock.Anything,
			).Return(&ghclient.CreateCheckSuiteResponse{
				WorkflowRun: &ghclient.CheckSuiteWorkflowRun{},
			}, tt.err)

			s.invoker.ghClient = mockGitHubClient

			wf, err := workflowparser.Parse(ctx, types.ResolvedFile{Text: workflow, Path: "main.yml"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
			s.Require().NoError(err)

			wfStartErr := s.invoker.Run(ctx, &model.Workflow{}, wf, false)
			s.Require().Nil(wfStartErr)
		})
	}
}

// Helper methods
func (s *buildInvokerTest) assertLogged(message string) {
	s.Contains(s.recordingLogger.String(), message)
}

func runWorkflowActivationCycle(s *buildInvokerTest, previousWorkflow *githubgo.Workflow, targetWorkflow *model.Workflow, previousWorkflowRun *githubgo.WorkflowRun) {
	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)

	s.invoker.errorHandler = mockErrorHandler

	s.invoker.invocation = Invocation{
		Event: InvokingEvent{
			Name: "workflow_run",
			Ghe: &githubgo.WorkflowRunEvent{
				Workflow:    previousWorkflow,
				WorkflowRun: previousWorkflowRun,
			},
		},
	}

	s.Nil(s.invoker.Run(context.Background(), targetWorkflow, &workflowparser.Workflow{}, false))
	s.Equal(s.wfb.ExternalID, "", "no checksuite should be created when a cycle is detected.")
}

func setupUntrustedAuthorTests(s *buildInvokerTest, shouldRunWorkflowsResponse bool, shouldRunWorkflowsError error) {
	setupPullRequestTest(s, true, shouldRunWorkflowsResponse, shouldRunWorkflowsError)
}

func setupNonForkPRTests(s *buildInvokerTest) {
	setupPullRequestTest(s, false, false, nil)
}

func setupPullRequestTest(s *buildInvokerTest, setupForkPR bool, shouldRunWorkflowsResponse bool, shouldRunWorkflowsError error) {
	setupPullRequestTestWithOptions(&setupPullRequestOptions{
		testSuite:                  s,
		setupForkPR:                setupForkPR,
		shouldRunWorkflowsResponse: shouldRunWorkflowsResponse,
		shouldRunWorkflowsError:    shouldRunWorkflowsError,
		shouldRunWorkflowsExpected: true,
	})
}

type setupPullRequestOptions struct {
	testSuite   *buildInvokerTest
	setupForkPR bool

	shouldRunWorkflowsResponse       bool
	shouldRunWorkflowsError          error
	shouldRunWorkflowsExpected       bool
	shouldRunWorkflowsExpectedActor  types.GlobalID
	shouldRunWorkflowsExpectedAuthor types.GlobalID

	rerun              bool
	invocationCallback func(i *Invocation)
}

func setupPullRequestTestWithOptions(opts *setupPullRequestOptions) {
	s := opts.testSuite
	setupForkPR := opts.setupForkPR
	shouldRunWorkflowsResponse := opts.shouldRunWorkflowsResponse
	shouldRunWorkflowsError := opts.shouldRunWorkflowsError

	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	mockTokenFactory := &workflowbuild.MockTokenFactory{}
	permissionSettings := &tokens.PermissionSettings{}
	mockTokenFactory.On("CalculateRunPermissions", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(permissionSettings, nil)

	s.invoker.tokenFactory = mockTokenFactory

	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}

	s.ghtwirp.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.SnapshotKeywordEnabledFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, "").Return(types.NilGlobalID, nil)

	repoDatabaseID := int64(16)
	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", repoDatabaseID))

	actorDatabaseID := int64(32)
	actorID := types.GlobalID(testutils.EncodeGlobalID("User", actorDatabaseID))

	if setupForkPR && opts.shouldRunWorkflowsExpected {
		users := ghtwirp.PullRequestEventUsers{Actor: opts.shouldRunWorkflowsExpectedActor}

		if users.Actor == "" {
			users.Actor = actorID
		}

		if opts.shouldRunWorkflowsExpectedAuthor != "" {
			users.Author = opts.shouldRunWorkflowsExpectedAuthor
		}

		s.ghtwirp.EXPECT().ShouldPullRequestWorkflowsRunForUser(mock.Anything, repoID, users).Return(shouldRunWorkflowsResponse, shouldRunWorkflowsError).Once()
	}

	s.invoker.data.PipelineFiles = []types.ResolvedFile{
		{
			Path: "./github/workflows/ci.yaml",
		},
	}
	s.invoker.data.References = types.WorkflowInvocationReferences{
		EventCommit: types.WorkflowInvocationReference{
			CommitSHA: "commitSHA",
		},
		CheckoutCommit: types.WorkflowInvocationReference{
			CommitSHA: "commitSHA2",
		},
	}

	var headID, baseID int64
	if setupForkPR {
		headID = 1
		baseID = 2
	} else {
		headID = 1
		baseID = 1
	}

	headRepoID := "headRepoID"
	author := actorID.String()
	pr := &githubgo.PullRequest{
		Head: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID:     &headID,
				NodeID: &headRepoID,
			},
		},
		Base: &githubgo.PullRequestBranch{
			Repo: &githubgo.Repository{
				ID: &baseID,
			},
		},
		User: &githubgo.User{
			NodeID: &author,
			ID:     &actorDatabaseID,
		},
	}

	s.invoker.invocation = Invocation{
		Event: InvokingEvent{
			Name:    "pull_request",
			Ghe:     &githubgo.PullRequestEvent{PullRequest: pr},
			Payload: []byte("{}"),
		},
		Target: NewTarget(repoID, repoDatabaseID, NewWorkflowSelector("pull_request", pr), types.NilGlobalID, int64(0), defaultGitHubTenant),
		ExecutingActor: InvokingActor{
			ID: actorID,
		},
		TriggeringActor: InvokingActor{
			ID: actorID,
		},
	}

	if opts.invocationCallback != nil {
		opts.invocationCallback(&s.invoker.invocation)
	}

	s.repo.EXPECT().
		Persist(
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
		).
		Return(int64(0), types.NewRandomWorkflowExecutionID(), time.Time{}, false, nil)

	s.repo.On(
		"SetCheckSuiteInformation",
		mock.Anything,
		mock.Anything,
		mock.Anything,
		mock.Anything,
		mock.Anything,
		mock.Anything,
	).Return(nil)

	if opts.rerun {
		s.invoker.invocation.ExistingCheckSuite = &types.CheckSuiteState{
			RepositoryID: repoID,
			CheckSuiteIDPair: types.IDPair{
				GlobalID: types.GlobalID(checkSuiteNodeID),
			},
		}
		executionID := types.NewRandomWorkflowExecutionID()

		s.repo.EXPECT().
			ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
			Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: 2}, nil)

		s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
			return in.PlanID == executionID &&
				in.Attempt == 2
		})).Return(nil)
	}
}

type setupWorkflowRunReuseTestOptions struct {
	testSuite                      *buildInvokerTest
	eventType                      string
	reusePreviousOutcomeKeyPresent bool
	GreenTreesEnabled              bool
}

func setupWorkflowRunReuseTest(opts *setupWorkflowRunReuseTestOptions) string {
	s := opts.testSuite
	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(opts.GreenTreesEnabled)

	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler

	s.repo.EXPECT().
		Persist(
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
		).
		Return(int64(0), types.NewRandomWorkflowExecutionID(), time.Time{}, false, nil)

	s.invoker.invocation = Invocation{
		Event: InvokingEvent{
			Name: opts.eventType,
		},
	}
	s.invoker.invocation.Target.RepositoryID = "abc"

	if opts.reusePreviousOutcomeKeyPresent {
		return `
on:
  ` + opts.eventType + `:
    reuse-previous-outcome: true
jobs:
  thing:
    steps:
    - uses: owner/repo@master`
	}

	return `
on: ` + opts.eventType + `
jobs:
  thing:
    steps:
    - uses: owner/repo@master`
}

func setupCreateWorkflowRunResultsTest(s *buildInvokerTest, errCase, isReRun bool) string {
	testutils.SetAppMode(s.T(), launchconfig.HostedAppMode)
	s.repo.EXPECT().
		Persist(
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
		).
		Return(int64(0), types.NewRandomWorkflowExecutionID(), time.Now().UTC(), false, nil)

	s.repo.On(
		"SetCheckSuiteInformation",
		mock.Anything,
		mock.Anything,
		mock.Anything,
		mock.Anything,
		mock.Anything,
		mock.Anything,
	).Return(nil)

	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}
	executionID := types.NewRandomWorkflowExecutionID()
	attemptNum := int64(3)

	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
	s.ghtwirp.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	s.ghtwirp.On("GetTrustTier", mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("CreateRerunExecution", mock.Anything, mock.MatchedBy(func(in *ghtwirp.RerunExecutionInput) bool {
		return in.RepositoryID == repoID &&
			in.PlanID == executionID &&
			in.Attempt == attemptNum
	})).Return(nil)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.GreenTreesFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserErrorsFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.CompareParserPlansFlag, mock.Anything).Return(false)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, "").Return(types.NilGlobalID, nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(types.GlobalID("id_next"), nil)

	mockKredzClient := &kredz.MockClient{}
	mockKredzClient.On("ListSecretsForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&kredz.RepositorySecretsResponse{}, nil)
	s.invoker.kredzClient = mockKredzClient

	tokenFactory := &workflowbuild.MockTokenFactory{}
	tokenFactory.On("CalculateRunPermissions", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&tokens.PermissionSettings{
		InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
		DefaultPermissions:      tokens.LimitedReadPermissions,
	}, nil)
	s.invoker.tokenFactory = tokenFactory

	s.repo.EXPECT().
		ResetWorkflowBuildState(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&deployer.WorkflowBuildResetContext{WorkflowExecutionID: &executionID, Attempt: attemptNum}, nil)

	mockGitHubClient := &ghclient.MockClient{}
	mockGitHubClient.On("CreateCheckSuite",
		mock.Anything,
		mock.Anything,
	).Return(&ghclient.CreateCheckSuiteResponse{
		WorkflowRun: &ghclient.CheckSuiteWorkflowRun{},
	}, nil)
	s.invoker.ghClient = mockGitHubClient

	mockErrorHandler := &MockWorkflowStartErrHandler{}
	mockErrorHandler.On("handlePanic", mock.Anything, mock.Anything)
	s.invoker.errorHandler = mockErrorHandler
	s.invoker.data.References = types.WorkflowInvocationReferences{
		EventCommit: types.WorkflowInvocationReference{
			CommitSHA: "commitSHA",
		},
		CheckoutCommit: types.WorkflowInvocationReference{
			CommitSHA: "commitSHA2",
		},
	}
	if isReRun {
		s.invoker.invocation = Invocation{
			ExistingCheckSuite: &types.CheckSuiteState{
				RepositoryID: repoID,
				CheckSuiteIDPair: types.IDPair{
					GlobalID: types.GlobalID(checkSuiteNodeID),
				},
			},
		}
	} else {
		s.invoker.invocation = Invocation{
			Event: InvokingEvent{
				Name: "push-test",
			},
		}
	}

	s.invoker.invocation.Target.RepositoryID = types.GlobalID(testutils.EncodeGlobalID("Repository", 16))
	if !errCase {
		azpBuild := &azpclient.Build{ID: 123}
		s.azpClient = &azpclient.MockRepositoryClient{}
		s.azpClient.On("Queue", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)
		s.invoker.azpClient = s.azpClient

		s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, strconv.Itoa(azpBuild.ID)).Return(nil)
		s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
			return msg.Status == hydroV0.QueueRun_SUCCESS
		})).Return()
	}

	return `
on:
  push
jobs:
  thing:
    steps:
    - uses: owner/repo@master
`
}

func setupExpectationsForActionRequiredRun(s *buildInvokerTest) {
	mockGitHubClient := &ghclient.MockClient{}
	mockGitHubClient.On("CreateCheckSuite",
		mock.Anything,
		mock.MatchedBy(func(req ghclient.CreateCheckSuiteRequest) bool {
			return req.Conclusion == ghclient.CheckSuiteActionRequiredConclusion.String() &&
				req.WorkflowFileCheckoutSHA.IsZeroValue()
		}),
	).Return(&ghclient.CreateCheckSuiteResponse{
		WorkflowRun: &ghclient.CheckSuiteWorkflowRun{},
	}, nil)
	s.invoker.ghClient = mockGitHubClient

	s.resultsClient.On("CreateWorkflowRun", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil).Once()

	s.repo.On(
		"Complete",
		mock.Anything,
		mock.Anything,
		mock.Anything,
		mock.Anything,
		build.WorkflowStateSkipped,
	).Return(nil)
}

func setupExpectationsForQueuedRun(s *buildInvokerTest) {
	mockGitHubClient := &ghclient.MockClient{}
	mockGitHubClient.On("CreateCheckSuite",
		mock.Anything,
		mock.MatchedBy(func(req ghclient.CreateCheckSuiteRequest) bool {
			return req.WorkflowFileCheckoutSHA.IsZeroValue() // This field should not be populated for non required workflows
		}),
	).Return(&ghclient.CreateCheckSuiteResponse{
		WorkflowRun: &ghclient.CheckSuiteWorkflowRun{},
	}, nil)
	s.invoker.ghClient = mockGitHubClient

	mockKredzClient := &kredz.MockClient{}
	mockKredzClient.On("ListSecretsForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&kredz.RepositorySecretsResponse{}, nil)
	s.invoker.kredzClient = mockKredzClient

	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("Queue", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceFeatureFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.RunServiceProximaFeatureFlag, mock.Anything).Return(false)
	s.invoker.azpClient = s.azpClient

	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, strconv.Itoa(azpBuild.ID)).Return(nil)
	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()
}

func setupExpectationsForQueuedRequiredWorkflowRun(s *buildInvokerTest) {
	mockGitHubClient := &ghclient.MockClient{}
	mockGitHubClient.On("CreateCheckSuite",
		mock.Anything,
		mock.MatchedBy(func(req ghclient.CreateCheckSuiteRequest) bool {
			return !req.WorkflowFileCheckoutSHA.IsZeroValue()
		}),
	).Return(&ghclient.CreateCheckSuiteResponse{
		WorkflowRun: &ghclient.CheckSuiteWorkflowRun{},
	}, nil)
	s.invoker.ghClient = mockGitHubClient

	mockKredzClient := &kredz.MockClient{}
	mockKredzClient.On("ListSecretsForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&kredz.RepositorySecretsResponse{}, nil)
	s.invoker.kredzClient = mockKredzClient

	mockVarzClient := &varz.MockClient{}
	mockVarzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&varz.RepositoryVariablesResponse{}, nil)
	s.invoker.varzClient = mockVarzClient

	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("Queue", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)
	s.invoker.azpClient = s.azpClient

	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, strconv.Itoa(azpBuild.ID)).Return(nil)
	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.PublicForkPrWorkflowsPolicyFlag, mock.Anything).Return(false)
}

func setupExpectationsForQueuedRunWithThresholdExceededAnnotations(s *buildInvokerTest, isEnterprise bool) {
	mockGitHubClient := &ghclient.MockClient{}
	mockGitHubClient.On("CreateCheckSuite",
		mock.Anything,
		mock.MatchedBy(func(req ghclient.CreateCheckSuiteRequest) bool {
			return req.WorkflowFileCheckoutSHA.IsZeroValue() // This field should not be populated for non required workflows
		}),
	).Return(&ghclient.CreateCheckSuiteResponse{
		WorkflowRun: &ghclient.CheckSuiteWorkflowRun{},
	}, nil)

	mockGitHubClient.On("UpdateCheckSuite", mock.Anything, mock.MatchedBy(func(req github.UpdateCheckSuiteRequest) bool {
		s.Equal(len(req.Annotations), 1)
		s.Equal(req.Annotations[0].Title, "Total variables size limit exceeded")
		if isEnterprise {
			s.Contains(req.Annotations[0].Message, "10 MB")
			s.Contains(req.Annotations[0].Message, "https://docs.github.com/enterprise-server@latest/actions/learn-github-actions/variables#limits-for-configuration-variables")
		} else {
			s.Contains(req.Annotations[0].Message, "256 KB")
			s.Contains(req.Annotations[0].Message, "https://docs.github.com/actions/learn-github-actions/variables#limits-for-configuration-variables")
		}

		return true
	})).Return(&types.IDPair{}, nil)

	s.invoker.ghClient = mockGitHubClient

	mockKredzClient := &kredz.MockClient{}
	mockKredzClient.On("ListSecretsForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(&kredz.RepositorySecretsResponse{}, nil)
	s.invoker.kredzClient = mockKredzClient

	azpBuild := &azpclient.Build{ID: 123}
	s.azpClient = &azpclient.MockRepositoryClient{}
	s.azpClient.On("Queue", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(azpBuild, nil)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsUseResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsStreamLogsViaResultsServiceFlag, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepository", mock.Anything, github.EnableCacheServiceV2, mock.Anything).Return(false)
	s.ghtwirp.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, github.ActionsOptOutResultsServiceRunnerFlag, mock.Anything).Return(false)
	s.invoker.azpClient = s.azpClient

	s.repo.EXPECT().TransitionToQueued(mock.Anything, mock.Anything, strconv.Itoa(azpBuild.ID)).Return(nil)
	s.mockEmitter.On("EmitQueueRun", mock.MatchedBy(func(msg *hydroV0.QueueRun) bool {
		return msg.Status == hydroV0.QueueRun_SUCCESS
	})).Return()
}

func (s *buildInvokerTest) getSecretStore(b *build.WorkflowBuild) build.SecretStore {
	s.setupSecretStoreMocks()

	ss, err := s.invoker.getSecretStore(context.Background(), repoID, b)
	if err != nil {
		panic(fmt.Sprintf("couldn't get secret store: %v", err))
	}

	return ss
}

func (s *buildInvokerTest) setupSecretStoreMocks() {
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, s.invoker.actionsAppGlobalID).Return(types.GlobalID("actions-app-next-global-id"), nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, s.invoker.dependabotAppGlobalID).Return(types.GlobalID("dependabot-app-next-global-id"), nil)
	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(types.GlobalID("next-global-id"), nil)

	s.kredzClient = &kredz.MockClient{}
	s.invoker.kredzClient = s.kredzClient
	s.decryptor = &earthsmoke.MockDecryptor{}
	s.invoker.secretDecryptor = s.decryptor
	s.setupSecretKeyValuesMock(types.GlobalID("next-global-id"), types.GlobalID("actions-app-next-global-id"), workflowbuild.ActionsSecretSource, []SecretKeyValue{
		{"ACTIONS_SECRET_ONE", "one_encrypted", "one"},
		{"ACTIONS_SECRET_TWO", "two_encrypted", "two"},
	})
	s.setupSecretKeyValuesMock(types.GlobalID("next-global-id"), types.GlobalID("dependabot-app-next-global-id"), workflowbuild.DependabotSecretSource, []SecretKeyValue{
		{"DEPENDABOT_SECRET_ONE", "dependabot_one_encrypted", "dependabot_one"},
		{"DEPENDABOT_SECRET_TWO", "dependabot_two_encrypted", "dependabot_two"},
	})
}

type SecretKeyValue struct {
	Key            string
	EncryptedValue string
	DecryptedValue string
}

func (s *buildInvokerTest) setupSecretKeyValuesMock(repoID types.GlobalID, secretAppGlobalID types.GlobalID, secretSource workflowbuild.SecretSource, secretKeyValues []SecretKeyValue) {
	reposityrSecrets := map[string]string{}
	for _, secretKeyValue := range secretKeyValues {
		reposityrSecrets[secretKeyValue.Key] = secretKeyValue.EncryptedValue
		s.decryptor.On("DecryptSecretValue", mock.Anything, secretKeyValue.EncryptedValue, mock.Anything, secretSource, mock.Anything).Return(secretKeyValue.DecryptedValue, true, nil).Once()
	}
	s.kredzClient.On("ListSecretsForRepository", mock.Anything, mock.Anything, mock.Anything, repoID, mock.Anything, secretAppGlobalID).Return(&kredz.RepositorySecretsResponse{
		RepositorySecrets: reposityrSecrets,
	}, nil)
}

func (s *buildInvokerTest) getVariables() map[string]string {
	s.varzClient = &varz.MockClient{}

	repoVariableOne := base64.StdEncoding.EncodeToString([]byte("repo_variable_one"))
	repoVariableTwo := base64.StdEncoding.EncodeToString([]byte("repo_variable_two"))
	orgVariableOne := base64.StdEncoding.EncodeToString([]byte("org_variable_one"))
	orgVariableTwo := base64.StdEncoding.EncodeToString([]byte("org_variable_two"))

	s.varzClient.On("ListVariablesForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, types.GlobalID("actions-app-next-global-id"), mock.Anything).Return(&varz.RepositoryVariablesResponse{
		RepositoryVariables: map[string]string{
			"REPO_VARIABLE_ONE": repoVariableOne,
			"REPO_VARIABLE_TWO": repoVariableTwo,
		},
		OrganizationVariables: map[string]string{
			"ORG_VARIABLE_ONE": orgVariableOne,
			"ORG_VARIABLE_TWO": orgVariableTwo,
		},
	}, nil)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 16))
	vm, err := s.invoker.getVariables(context.Background(), s.varzClient, s.ghtwirp, s.invoker.data, repoID)
	if err != nil {
		panic(fmt.Sprintf("couldn't get variables: %v", err))
	}

	return vm
}
