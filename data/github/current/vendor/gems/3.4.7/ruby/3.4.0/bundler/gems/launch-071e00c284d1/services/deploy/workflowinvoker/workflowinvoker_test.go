package workflowinvoker

import (
	"context"
	"errors"
	"testing"
	"time"

	githubgo "github.com/google/go-github/v25/github"
	gogithub "github.com/google/go-github/v25/github"
	"github.com/google/uuid"
	errs "github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	ghactions "github.com/github/launch/proto/monolith/core/v1"
	"github.com/github/launch/workflowparser"

	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/clients/runservice"
	spokesd "github.com/github/launch/clients/spokesd"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/model"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/observability/statter"
	azpc "github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workerpool"
	"github.com/github/launch/workflowbuild"
	"github.com/github/launch/workflowbuild/azp"
)

type WorkflowInvokerTestSuite struct {
	suite.Suite

	invoker    *workflowInvoker
	invocation Invocation

	recordingLogger *testutils.RecordingLogger

	mockBuildInvoker          *MockBuildInvoker
	mockBuildInvokerFactory   *MockBuildInvokerFactory
	mockWorkflowSourceFactory *MockWorkflowSourceFactory
	mockGitHubClient          *github.MockClient
	mockGitHubTwirpClient     *ghtwirp.MockClient
	mockSpokesClient          *spokesd.MockClient
	mockAuthzClient           *authzd.MockClient
	mockErrorHandler          *MockWorkflowStartErrHandler
	mockTenantHandler         *azp.MockTenantHandler
	mockEmitter               *slometrics.MockHydroEmitter
	mockRunServiceClient      *runservice.MockClient
	mockResultsClient         *results.MockClient
}

var actorCreatedAt = timestamppb.Now()

var partialActors = []*ghactions.Actor{
	{
		Id:        0,
		IdString:  "actor",
		GlobalId:  &ghactions.Identity{GlobalId: "actor"},
		Type:      ghactions.Actor_TYPE_USER,
		PlanName:  "free",
		IsPrivate: nil,
		CreatedAt: actorCreatedAt,
		IsHammy:   wrapperspb.Bool(false),
	},
	{
		Id:        0,
		IdString:  "targetRepoOwner",
		GlobalId:  &ghactions.Identity{GlobalId: "targetRepoOwner"},
		Type:      ghactions.Actor_TYPE_ORGANIZATION,
		PlanName:  "enterprise",
		IsPrivate: nil,
		CreatedAt: actorCreatedAt,
		IsHammy:   wrapperspb.Bool(true),
	},
	{
		Id:        0,
		IdString:  "billingPlanOwner",
		GlobalId:  &ghactions.Identity{GlobalId: "billingPlanOwner"},
		Type:      ghactions.Actor_TYPE_ORGANIZATION,
		PlanName:  "enterprise",
		IsPrivate: nil,
		CreatedAt: actorCreatedAt,
		IsHammy:   wrapperspb.Bool(true),
	},
	{
		Id:        0,
		IdString:  "targetRepo",
		GlobalId:  &ghactions.Identity{GlobalId: "targetRepo"},
		Type:      ghactions.Actor_TYPE_REPOSITORY,
		PlanName:  "",
		IsPrivate: wrapperspb.Bool(true),
		CreatedAt: actorCreatedAt,
	},
}

var forkPRPartialActors = append(partialActors,
	&ghactions.Actor{
		Id:        0,
		IdString:  "headRepoOwner",
		GlobalId:  &ghactions.Identity{GlobalId: "headRepoOwner"},
		Type:      ghactions.Actor_TYPE_ORGANIZATION,
		PlanName:  "enterprise",
		IsPrivate: nil,
		CreatedAt: actorCreatedAt,
	},
	&ghactions.Actor{
		Id:        0,
		IdString:  "headRepo",
		GlobalId:  &ghactions.Identity{GlobalId: "headRepo"},
		Type:      ghactions.Actor_TYPE_REPOSITORY,
		PlanName:  "",
		IsPrivate: wrapperspb.Bool(true),
		CreatedAt: actorCreatedAt,
	},
)

func (s *WorkflowInvokerTestSuite) SetupTest() {
	s.mockErrorHandler = NewMockWorkflowStartErrHandler(s.T())
	s.mockErrorHandler.EXPECT().handlePanic(mock.Anything, mock.Anything).Maybe()

	s.mockBuildInvoker = NewMockBuildInvoker(s.T())
	s.mockBuildInvoker.EXPECT().Run(mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil).Maybe()
	s.mockBuildInvokerFactory = NewMockBuildInvokerFactory(s.T())
	s.mockBuildInvokerFactory.EXPECT().
		Build(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(s.mockBuildInvoker).Maybe()

	s.mockWorkflowSourceFactory = NewMockWorkflowSourceFactory(s.T())
	s.mockWorkflowSourceFactory.EXPECT().
		Build(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&workflowparser.NullWorkflowSource{}).Maybe()

	mockRepositoryClient := azpc.NewMockRepositoryClient(s.T())
	s.mockTenantHandler = azp.NewMockTenantHandler(s.T())
	s.mockTenantHandler.EXPECT().
		GetOrCreateTenants(
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
			mock.Anything,
		).Return(mockRepositoryClient, &types.RepositoryTenants{}, deployer.OrgCreationSuccess, nil).Maybe()

	mockFilter := workflowbuild.NewMockWorkflowFilter(s.T())
	mockFilter.EXPECT().ShouldRun(mock.Anything, mock.Anything).Return(true).Maybe()
	mockFilterer := azp.NewMockWorkflowFilterer(s.T())
	mockFilterer.EXPECT().GetWorkflowFilter(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(mockFilter, nil).Maybe()

	s.mockGitHubClient = github.NewMockClient(s.T())
	s.mockGitHubClient.EXPECT().GetReportingMetadata(mock.Anything, mock.Anything, mock.Anything).Return(metadata.WorkflowMetadata{}, nil).Maybe()

	s.mockGitHubTwirpClient = ghtwirp.NewMockClient(s.T())

	s.mockGitHubTwirpClient.EXPECT().GetActorsInfo(mock.Anything, []types.GlobalID{"", "", "", ""}).Return(&ghtwirp.ActorsInfo{Actors: partialActors}, nil).Maybe()
	s.mockGitHubTwirpClient.EXPECT().GetActorsInfo(mock.Anything, []types.GlobalID{"", "", "", "", types.GlobalID(forkRepoOwnerNodeID), types.GlobalID(forkRepoNodeID)}).Return(&ghtwirp.ActorsInfo{Actors: forkPRPartialActors}, nil).Maybe()

	s.mockSpokesClient = spokesd.NewMockClient(s.T())
	s.mockAuthzClient = authzd.NewMockClient(s.T())

	l := testutils.NewRecordingLogger()
	s.recordingLogger = &l

	s.invocation = pushInvocation

	mockEmitter := slometrics.NewMockHydroEmitter(s.T())
	s.mockEmitter = mockEmitter

	s.mockRunServiceClient = runservice.NewMockClient(s.T())
	s.mockResultsClient = results.NewMockClient(s.T())
	s.invoker = &workflowInvoker{
		buildInvokerFactory:   s.mockBuildInvokerFactory,
		workflowSourceFactory: s.mockWorkflowSourceFactory,
		tenantHandler:         s.mockTenantHandler,
		env:                   launchconfig.ProductionAppEnv,
		provider:              azp.NewWorkflowProvider(s.mockSpokesClient, s.mockAuthzClient, s.mockGitHubTwirpClient, observability.New(s.recordingLogger.Logger, statter.NullStatter()), false, launchconfig.ProductionAppEnv),
		filterer:              mockFilterer,
		appMode:               launchconfig.HostedAppMode,
		obs:                   NewTestObservability(observability.New(s.recordingLogger.Logger, statter.NullStatter())),
		ghClient:              s.mockGitHubClient,
		ghTwirpClient:         s.mockGitHubTwirpClient,
		inv:                   s.invocation,
		errorHandler:          s.mockErrorHandler,
		workers:               workerpool.NewInline(logger.NullLogger(), statter.NullStatter()),
		sloReporter:           slometrics.New(mockEmitter),
		runServiceClient:      s.mockRunServiceClient,
		resultsClient:         s.mockResultsClient,
	}
}

func (s *WorkflowInvokerTestSuite) SetupSubTest() {
	s.SetupTest()
}

func (s *WorkflowInvokerTestSuite) TestInvokerSuccess() {
	data := newWorkflowInvocationData()
	err := s.invoker.Start(context.Background(), data, false)
	s.Assert().Nil(err)
	s.mockBuildInvoker.AssertNumberOfCalls(s.T(), "Run", 2)
	s.mockBuildInvoker.AssertCalled(s.T(), "Run", mock.Anything, &model.Workflow{
		Identifier: data.PipelineFiles[0].Path,
		On: &model.OnEvent{
			Event: "push",
		},
		Path:          data.PipelineFiles[0].Path,
		File:          data.PipelineFiles[0],
		FileReference: types.NewWorkflowFileReference(data.PipelineFiles[0].Path),
	}, mock.Anything, mock.Anything)
	s.mockBuildInvoker.AssertCalled(s.T(), "Run", mock.Anything, &model.Workflow{
		Identifier: data.PipelineFiles[1].Path,
		On: &model.OnEvent{
			Event: "push",
		},
		Path:          data.PipelineFiles[1].Path,
		File:          data.PipelineFiles[1],
		FileReference: types.NewWorkflowFileReference(data.PipelineFiles[1].Path),
	}, mock.Anything, mock.Anything)
}

func (s *WorkflowInvokerTestSuite) TestInvokerSuccessWithOldScheduledWebhook() {
	data := newWorkflowInvocationData()

	s.invoker.inv.Event.OriginTime = time.Time{}
	s.invoker.inv.Event.Name = flowevents.ScheduleEventName
	err := s.invoker.Start(context.Background(), data, false)
	s.Assert().Nil(err)
	s.mockBuildInvoker.AssertNumberOfCalls(s.T(), "Run", 2)
	s.mockBuildInvoker.AssertCalled(s.T(), "Run", mock.Anything, &model.Workflow{
		Identifier: data.PipelineFiles[0].Path,
		On: &model.OnEvent{
			Event: "push",
		},
		Path:          data.PipelineFiles[0].Path,
		File:          data.PipelineFiles[0],
		FileReference: types.NewWorkflowFileReference(data.PipelineFiles[0].Path),
	}, mock.Anything, mock.Anything)
	s.mockBuildInvoker.AssertCalled(s.T(), "Run", mock.Anything, &model.Workflow{
		Identifier: data.PipelineFiles[1].Path,
		On: &model.OnEvent{
			Event: "push",
		},
		Path:          data.PipelineFiles[1].Path,
		File:          data.PipelineFiles[1],
		FileReference: types.NewWorkflowFileReference(data.PipelineFiles[1].Path),
	}, mock.Anything, mock.Anything)
}

func (s *WorkflowInvokerTestSuite) TestPanicHandling() {
	s.mockTenantHandler.EXPECT().GetOrCreateTenants(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Panic("test panic")
	data := newWorkflowInvocationData()
	err := s.invoker.Start(context.Background(), data, false)
	s.Require().Nil(err)
}

func (s *WorkflowInvokerTestSuite) TestInvokerSpammyUser() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.Actor.IsSpammy = true
	})
	err := s.invoker.Start(context.Background(), data, false)
	s.Require().NotNil(err)
	s.Assert().Len(err.Errors(), 1)
	s.Assert().Equal(err.Error(), "Actions are disabled for this account. Please contact GitHub Support. https://github.com/contact")
}

func (s *WorkflowInvokerTestSuite) TestInvokerNoLaunchLabFeatureFlag() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.FeatureFlags.LaunchLabEnabled = false
	})
	s.invoker.env = launchconfig.LabAppEnv
	err := s.invoker.Start(context.Background(), data, false)
	s.Require().Nil(err)
	s.assertLogged("launch_lab feature flag is not set")
}

func (s *WorkflowInvokerTestSuite) TestInvokerWithLaunchLabFeatureFlag() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.FeatureFlags.LaunchLabEnabled = true
	})
	s.invoker.env = launchconfig.LabAppEnv
	err := s.invoker.Start(context.Background(), data, false)
	s.Require().Nil(err)
	s.assertNotLogged("launch_lab feature flag is not set")
}

func (s *WorkflowInvokerTestSuite) TestInvokerBlocked() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.Actor.ActionInvocationBlocked = true
	})

	err := s.invoker.Start(context.Background(), data, false)
	s.Require().Nil(err)
	s.assertLogged("invocation has been blocked for the actor")
}

func (s *WorkflowInvokerTestSuite) TestInvokerHandlesMissingOrDisabledWorkflowFiles() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.PipelineFiles = []types.ResolvedFile{}
	})

	err := s.invoker.Start(context.Background(), data, false)
	s.Require().Nil(err)
	s.assertLogged("ignoring this event, because there are no active workflow files")
}

func (s *WorkflowInvokerTestSuite) TestInvokerInvalidWorkflowSyntax() {
	s.mockErrorHandler.EXPECT().notifyInvalidWorkflow(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)

	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.PipelineFiles = []types.ResolvedFile{
			{
				Path: ".github/workflows/workflow.yml",
				Text: "foobar",
				SHA:  "",
			},
		}
	})
	err := s.invoker.Start(context.Background(), data, false)
	s.Require().Nil(err)
	s.assertLogged("invalid workflow file")
	s.mockErrorHandler.AssertNumberOfCalls(s.T(), "notifyInvalidWorkflow", 1)
}

func (s *WorkflowInvokerTestSuite) TestInvokerDoesNotReportInvalidWorkflowSyntaxForNormalWorkflowsTriggeredByPREvent() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.PipelineFiles = []types.ResolvedFile{
			{
				Path: ".github/workflows/workflow.yml",
				Text: "foobar",
				SHA:  "c7cfbd75232e114c14ca613hh7d48c3499a1b1be",
			},
		}
	})

	mockWorkflowProvider := &azp.MockWorkflowProvider{}
	s.invoker.provider = mockWorkflowProvider

	mockWorkflowProvider.EXPECT().GetWorkflows(mock.Anything, mock.Anything, mock.Anything, data).Return(data.PipelineFiles)

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
	s.invoker.inv = NewInvocation(pullRequestEvent, actor, actor, pullRequestTarget)

	err := s.invoker.Start(context.Background(), data, false)
	s.Require().Nil(err)
	s.assertLogged("invalid workflow file")
	s.mockErrorHandler.AssertNumberOfCalls(s.T(), "notifyInvalidWorkflow", 0)
}

func (s *WorkflowInvokerTestSuite) TestInvokerInvalidWorkflowSyntaxForRequiredWorkflows() {
	sha := "7385e4b18473d3f8daa525da1ec7512868582cad"
	path := "required/12345/workflows/workflow.yml"
	ref := "refs/heads/main"

	fileReference := types.NewRulesetWorkflowFileReference(path, types.GitRef(ref), types.CommitSha(sha))

	s.mockErrorHandler.EXPECT().notifyInvalidWorkflow(mock.Anything, fileReference.Path, mock.Anything, mock.Anything, mock.Anything, types.CommitSha(sha)).Once()
	data := newWorkflowInvocationData()

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
	s.invoker.inv = NewInvocation(pullRequestEvent, actor, actor, pullRequestTarget)

	mockWorkflowProvider := &azp.MockWorkflowProvider{}
	s.invoker.provider = mockWorkflowProvider
	pipelineFiles := []types.ResolvedFile{
		{
			Path: path,
			Text: "foobar",
			SHA:  sha,
			Ref:  ref,
		},
	}
	mockWorkflowProvider.EXPECT().GetWorkflows(mock.Anything, s.invoker.inv.Event.Name, s.invoker.inv.Event.Ghe, data).Return(pipelineFiles)

	err := s.invoker.Start(context.Background(), data, false)
	s.Require().Nil(err)
	s.assertLogged("invalid workflow file")
}

func (s *WorkflowInvokerTestSuite) TestInvokerInvalidWorkflowSyntaxForRequiredWorkflowsInGHES() {
	sha := "7385e4b18473d3f8daa525da1ec7512868582cad"
	path := "required/12345/workflows/workflow.yml"
	ref := "refs/heads/main"

	fileReference := types.NewRulesetWorkflowFileReference(path, types.GitRef(ref), types.CommitSha(sha))

	s.mockErrorHandler.EXPECT().notifyInvalidWorkflow(mock.Anything, fileReference.Path, mock.Anything, mock.Anything, mock.Anything, types.CommitSha(sha)).Once()
	data := newWorkflowInvocationData()

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
	s.invoker.inv = NewInvocation(pullRequestEvent, actor, actor, pullRequestTarget)

	mockWorkflowProvider := &azp.MockWorkflowProvider{}
	s.invoker.provider = mockWorkflowProvider
	pipelineFiles := []types.ResolvedFile{
		{
			Path: path,
			Text: "foobar",
			SHA:  sha,
			Ref:  ref,
		},
	}
	mockWorkflowProvider.EXPECT().GetWorkflows(mock.Anything, s.invoker.inv.Event.Name, s.invoker.inv.Event.Ghe, data).Return(pipelineFiles)
	s.invoker.isEnterprise = true

	err := s.invoker.Start(context.Background(), data, false)
	s.Require().Nil(err)
	s.assertLogged("invalid workflow file")
}

func (s *WorkflowInvokerTestSuite) TestInvokerActionsIneligible() {
	cases := []struct {
		name          string
		isProxima     bool
		expectUserErr bool
	}{
		{
			name:          "ineligible dotcom",
			isProxima:     false,
			expectUserErr: true,
		},
		{
			name:          "ineligible proxima",
			isProxima:     true,
			expectUserErr: false,
		},
	}

	for _, c := range cases {
		s.Run(c.name, func() {
			testutils.SetIsMultiTenant(s.T(), c.isProxima)
			data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
				data.FeatureFlags.IsActionsEligible = false
			})

			err := s.invoker.Start(context.Background(), data, false)
			s.Require().NotNil(err)
			s.Assert().Len(err.Errors(), 1)
			s.Assert().Equal(err.Error(), "The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings.")
			s.Assert().Equal(c.expectUserErr, err.IsUserError())
		})
	}
}

func (s *WorkflowInvokerTestSuite) TestInvokerVerifiedEmailRequired() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.Actor.NoVerifiedEmail = true
	})
	err := s.invoker.Start(context.Background(), data, false)
	s.Require().NotNil(err)
	s.Assert().Len(err.Errors(), 1)
	s.Assert().Equal(err.Error(), "Please verify your email address to run GitHub Actions workflows. https://github.com/settings/emails")
}

func (s *WorkflowInvokerTestSuite) TestInvokerVerifiedEmailNotRequiredInEnterprise() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.Actor.NoVerifiedEmail = true
	})
	s.invoker.appMode = launchconfig.EnterpriseAppMode
	err := s.invoker.Start(context.Background(), data, false)
	s.Assert().Nil(err)
}

func (s *WorkflowInvokerTestSuite) TestInvokerWhenActionsDisabledOnlyAtRepoButAllowedByOwner() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.IsActionsDisabledAtAnyLevel = true
		data.IsActionsDisabledByOwner = false
		data.PipelineFiles = []types.ResolvedFile{
			{
				Path: ".github/workflows/workflow.yml",
				Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				SHA:  "",
			},
		}
	})
	err := s.invoker.Start(context.Background(), data, false)
	// when actions are totally disallowed, don't create a check suite. to a user check-suite = build, so
	// reporting these as errors caused confusion (see https://github.com/github/pe-actions-experience/issues/1313)
	s.Require().Nil(err)
	// implicitly we're asserting that buildInvoker was never called

	s.assertLogged("Ignoring this event, because Actions has been disabled in the repo, org, or enterprise settings and no required workflows are present")
}

func (s *WorkflowInvokerTestSuite) TestIgnoreActionsDisabledForRequiredWorkflows() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.IsActionsDisabledAtAnyLevel = true
		data.IsActionsDisabledByOwner = true
		data.PipelineFiles = []types.ResolvedFile{
			{
				Path: ".github/workflows/workflow.yml",
				Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				SHA:  "",
			},
		}
	})

	mockWorkflowProvider := &azp.MockWorkflowProvider{}
	s.invoker.provider = mockWorkflowProvider
	pipelineFiles := []types.ResolvedFile{
		{
			Path: "required/1234/workflows/abc.yml",
			Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
			SHA:  "123",
			Ref:  "refs/head/main",
		},
		{
			Path: "required/4567/workflows/abc.yml",
			Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foobar",
			SHA:  "456",
			Ref:  "refs/head/main",
		},
		{
			Path: ".github/workflows/workflow.yml",
			Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
			SHA:  "",
		},
	}
	mockWorkflowProvider.EXPECT().GetWorkflows(mock.Anything, s.invoker.inv.Event.Name, s.invoker.inv.Event.Ghe, data).Return(pipelineFiles)

	err := s.invoker.Start(context.Background(), data, false)
	s.assertLogged("Filtering only required workflows if actions is disabled, but not at the level that the ruleset was created")
	s.Assert().Nil(err)
	s.mockBuildInvoker.AssertNumberOfCalls(s.T(), "Run", 2)
	s.mockBuildInvoker.AssertCalled(s.T(), "Run", mock.Anything, &model.Workflow{
		Identifier: pipelineFiles[0].Path,
		On: &model.OnEvent{
			Event: "push",
		},
		Path:          pipelineFiles[0].Path,
		File:          pipelineFiles[0],
		FileReference: types.NewRulesetWorkflowFileReference(pipelineFiles[0].Path, types.GitRef(pipelineFiles[0].Ref), types.CommitSha(pipelineFiles[0].SHA)),
	}, mock.Anything, mock.Anything)
	s.mockBuildInvoker.AssertCalled(s.T(), "Run", mock.Anything, &model.Workflow{
		Identifier: pipelineFiles[1].Path,
		On: &model.OnEvent{
			Event: "push",
		},
		Path:          pipelineFiles[1].Path,
		File:          pipelineFiles[1],
		FileReference: types.NewRulesetWorkflowFileReference(pipelineFiles[1].Path, types.GitRef(pipelineFiles[1].Ref), types.CommitSha(pipelineFiles[1].SHA)),
	}, mock.Anything, mock.Anything)
}

func (s *WorkflowInvokerTestSuite) TestInvokerWhenActionsDisabledOnlyAtRepoButAllowedByOwnerAndRequiredWorkflowsArePresent() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.IsActionsDisabledAtAnyLevel = true
		data.IsActionsDisabledByOwner = false
		data.PipelineFiles = []types.ResolvedFile{
			{
				Path: ".github/workflows/workflow.yml",
				Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				SHA:  "",
			},
		}
	})

	mockWorkflowProvider := &azp.MockWorkflowProvider{}
	s.invoker.provider = mockWorkflowProvider
	pipelineFiles := []types.ResolvedFile{
		{
			Path: "required/1234/workflows/abc.yml",
			Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
			SHA:  "123",
			Ref:  "refs/head/main",
		},
		{
			Path: "required/4567/workflows/abc.yml",
			Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foobar",
			SHA:  "456",
			Ref:  "refs/head/main",
		},
		{
			Path: ".github/workflows/workflow.yml",
			Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
			SHA:  "",
		},
	}
	mockWorkflowProvider.EXPECT().GetWorkflows(mock.Anything, s.invoker.inv.Event.Name, s.invoker.inv.Event.Ghe, data).Return(pipelineFiles)

	err := s.invoker.Start(context.Background(), data, false)
	s.assertLogged("Filtering only required workflows if actions is disabled, but not at the level that the ruleset was created")
	s.Assert().Nil(err)
	s.mockBuildInvoker.AssertNumberOfCalls(s.T(), "Run", 2)
	s.mockBuildInvoker.AssertCalled(s.T(), "Run", mock.Anything, &model.Workflow{
		Identifier: pipelineFiles[0].Path,
		On: &model.OnEvent{
			Event: "push",
		},
		Path:          pipelineFiles[0].Path,
		File:          pipelineFiles[0],
		FileReference: types.NewRulesetWorkflowFileReference(pipelineFiles[0].Path, types.GitRef(pipelineFiles[0].Ref), types.CommitSha(pipelineFiles[0].SHA)),
	}, mock.Anything, mock.Anything)
	s.mockBuildInvoker.AssertCalled(s.T(), "Run", mock.Anything, &model.Workflow{
		Identifier: pipelineFiles[1].Path,
		On: &model.OnEvent{
			Event: "push",
		},
		Path:          pipelineFiles[1].Path,
		File:          pipelineFiles[1],
		FileReference: types.NewRulesetWorkflowFileReference(pipelineFiles[1].Path, types.GitRef(pipelineFiles[1].Ref), types.CommitSha(pipelineFiles[1].SHA)),
	}, mock.Anything, mock.Anything)
}

func (s *WorkflowInvokerTestSuite) TestInvokerActionsDisabledFail() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.IsActionsDisabledAtAnyLevel = true
		data.IsActionsDisabledByOwner = true
		data.PipelineFiles = []types.ResolvedFile{
			{
				Path: ".github/workflows/workflow.yml",
				Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				SHA:  "",
			},
		}
	})

	err := s.invoker.Start(context.Background(), data, false)
	// when actions are totally disallowed, don't create a check suite. to a user check-suite = build, so
	// reporting these as errors caused confusion (see https://github.com/github/pe-actions-experience/issues/1313)
	s.Require().Nil(err)
	// implicitly we're assserting that buildInvoker was never called
	// s.assertLogged("Ignoring this event, because Actions has been disabled in the repo, org or enterprise settings")
	s.assertLogged("Ignoring this event, because Actions has been disabled in the repo, org, or enterprise settings and no required workflows are present")
}

func (s *WorkflowInvokerTestSuite) TestInvokerActionsDisabledFailWithFlag() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.IsActionsDisabledAtAnyLevel = true
		data.IsActionsDisabledByOwner = true
		data.FeatureFlags = types.InvokerFeatureFlags{
			IsActionsEligible: true,
			LaunchLabEnabled:  true,
		}
		data.PipelineFiles = []types.ResolvedFile{
			{
				Path: ".github/workflows/workflow.yml",
				Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				SHA:  "",
			},
		}
	})

	err := s.invoker.Start(context.Background(), data, false)
	// when actions are totally disallowed, don't create a check suite. to a user check-suite = build, so
	// reporting these as errors caused confusion (see https://github.com/github/pe-actions-experience/issues/1313)
	s.Require().Nil(err)
	// implicitly we're assserting that buildInvoker was never called
}

func (s *WorkflowInvokerTestSuite) TestInvokerWithActionInvocationBlocked() {
	data := newWorkflowInvocationData(func(data *types.WorkflowInvocationData) {
		data.ActionInvocationBlocked = true
	})
	s.invoker.env = launchconfig.LabAppEnv
	err := s.invoker.Start(context.Background(), data, false)
	s.Require().Nil(err)
	s.assertLogged("action invocation has been blocked for the repository")
}

func (s *WorkflowInvokerTestSuite) TestInvokerReturnsRetryableErrorOnWorkflowFilterNotFoundError() {
	wrappedNotFoundErr := errs.Wrap(&terrors.NotFoundError{Err: errors.New("NOT_FOUND")}, "better luck next time")

	mockFilterer := &azp.MockWorkflowFilterer{}
	mockFilterer.EXPECT().GetWorkflowFilter(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, wrappedNotFoundErr)
	s.invoker.filterer = mockFilterer

	data := newWorkflowInvocationData()
	err := s.invoker.Start(context.Background(), data, false)
	s.Require().NotNil(err)
	s.Assert().Len(err.Errors(), 1)
	s.Assert().True(terrors.IsRetryable(err))
}

func (s *WorkflowInvokerTestSuite) TestInvokerDoesNotFailWhenAbusePayloadIncomplete() {
	s.mockGitHubTwirpClient.EXPECT().GetActorsInfo(mock.Anything, mock.Anything).Return(&ghtwirp.ActorsInfo{
		Actors: []*ghactions.Actor{{}, {}, {}, {}},
	}, nil)
	_, err := s.invoker.buildPartialAbuseContext(
		context.Background(),
		pushEvent,
		"actor",
		"targetRepoOwner",
		"billingPlanOwner",
		"targetRepo",
	)
	s.Require().Nil(err)

}

func (s *WorkflowInvokerTestSuite) TestInvokerAssemblesAbusePayloadCorrectlyWhenNotPR() {
	expected := &types.PartialAbuseTriggerInfo{
		TriggerEvent:       "push",
		TriggerEventAction: "",
		Actor: &types.ActionsAbuseUser{
			ID:        "actor",
			Name:      "actor",
			Type:      "User",
			Plan:      "free",
			CreatedAt: actorCreatedAt.AsTime(),
			IsHammy:   false,
		},
		TargetRepoOwner: &types.ActionsAbuseUser{
			ID:        "targetRepoOwner",
			Name:      "targetRepoOwner",
			Type:      "Organization",
			Plan:      "enterprise",
			CreatedAt: actorCreatedAt.AsTime(),
			IsHammy:   true,
		},
		HeadRepoOwner: nil,
		BillingPlanOwner: &types.ActionsAbuseUser{
			ID:        "billingPlanOwner",
			Name:      "billingPlanOwner",
			Type:      "Organization",
			Plan:      "enterprise",
			CreatedAt: actorCreatedAt.AsTime(),
			IsHammy:   true,
		},
		TargetRepository: &types.ActionsAbuseRepository{
			ID:        "targetRepo",
			Private:   true,
			NWO:       "targetRepo",
			CreatedAt: actorCreatedAt.AsTime(),
		},
		HeadRepository: nil,
	}
	s.mockGitHubTwirpClient.EXPECT().GetActorsInfo(mock.Anything, []types.GlobalID{
		"actor",
		"targetRepoOwner",
		"billingPlanOwner",
		"targetRepo",
	}).Return(&ghtwirp.ActorsInfo{Actors: partialActors}, nil)
	actual, err := s.invoker.buildPartialAbuseContext(
		context.Background(),
		pushEvent,
		"actor",
		"targetRepoOwner",
		"billingPlanOwner",
		"targetRepo",
	)
	s.Require().Nil(err)
	s.EqualValues(expected, actual)
}

func (s *WorkflowInvokerTestSuite) TestInvokerSendNilAbusePayloadForGHES() {
	s.invoker.appMode = launchconfig.EnterpriseAppMode
	r, err := s.invoker.buildPartialAbuseContext(
		context.Background(),
		pushEvent,
		"actor",
		"targetRepoOwner",
		"billingPlanOwner",
		"targetRepo",
	)
	s.Require().Nil(err)
	s.Assert().Nil(r)
}

func (s *WorkflowInvokerTestSuite) TestInvokerAssemblesAbusePayloadCorrectlyWhenPR() {
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")

	webhookDeliveryID := uuid.New().String()
	var pullRequestEvent = NewEvent(
		&webhookDeliveryID,
		types.DefaultBranch,
		commitSha,
		"",
		"pull_request",
		"opened",
		nil,
		time.Time{},
		eventOriginTime,
		stubPullRequestEvent,
	)

	prEvent, _ := pullRequestEvent.Ghe.(*githubgo.PullRequestEvent)
	headRepoGID := types.GlobalID(prEvent.GetPullRequest().GetHead().GetRepo().GetNodeID())
	s.mockGitHubTwirpClient.EXPECT().GetActorsInfo(mock.Anything, []types.GlobalID{
		actorID,
		"targetRepoOwner",
		"billingPlanOwner",
		"targetRepo",
		actorID,
		headRepoGID,
	}).Return(&ghtwirp.ActorsInfo{Actors: forkPRPartialActors}, nil)

	expected := &types.PartialAbuseTriggerInfo{
		TriggerEvent:       "pull_request",
		TriggerEventAction: "opened",
		Actor: &types.ActionsAbuseUser{
			ID:        "actor",
			Name:      "actor",
			Type:      "User",
			Plan:      "free",
			CreatedAt: actorCreatedAt.AsTime(),
			IsHammy:   false,
		},
		TargetRepoOwner: &types.ActionsAbuseUser{
			ID:        "targetRepoOwner",
			Name:      "targetRepoOwner",
			Type:      "Organization",
			Plan:      "enterprise",
			CreatedAt: actorCreatedAt.AsTime(),
			IsHammy:   true,
		},
		HeadRepoOwner: &types.ActionsAbuseUser{
			ID:        "headRepoOwner",
			Name:      "headRepoOwner",
			Type:      "Organization",
			Plan:      "enterprise",
			CreatedAt: actorCreatedAt.AsTime(),
		},
		BillingPlanOwner: &types.ActionsAbuseUser{
			ID:        "billingPlanOwner",
			Name:      "billingPlanOwner",
			Type:      "Organization",
			Plan:      "enterprise",
			CreatedAt: actorCreatedAt.AsTime(),
			IsHammy:   true,
		},
		TargetRepository: &types.ActionsAbuseRepository{
			ID:        "targetRepo",
			Private:   true,
			NWO:       "targetRepo",
			CreatedAt: actorCreatedAt.AsTime(),
		},
		HeadRepository: &types.ActionsAbuseRepository{
			ID:        "headRepo",
			Private:   true,
			NWO:       "headRepo",
			CreatedAt: actorCreatedAt.AsTime(),
		},
	}
	actual, err := s.invoker.buildPartialAbuseContext(
		context.Background(),
		pullRequestEvent,
		actorID,
		"targetRepoOwner",
		"billingPlanOwner",
		"targetRepo",
	)
	s.Require().Nil(err)
	s.EqualValues(expected, actual)
}

func (s *WorkflowInvokerTestSuite) TestInvokerAssemblesAbusePayloadCorrectlyWhenMissingAllData() {
	s.mockGitHubTwirpClient.EXPECT().GetActorsInfo(mock.Anything, []types.GlobalID{
		"missingActor",
		"missingTargetRepoOwner",
		"missingBillingPlanOwner",
		"missingTargetRepo",
	}).Return(&ghtwirp.ActorsInfo{
		Actors: []*ghactions.Actor{{}, {}, {}, {}},
	}, nil)
	expected := &types.PartialAbuseTriggerInfo{
		TriggerEvent: "push",
	}

	actual, err := s.invoker.buildPartialAbuseContext(
		context.Background(),
		pushEvent,
		"missingActor",
		"missingTargetRepoOwner",
		"missingBillingPlanOwner",
		"missingTargetRepo",
	)
	s.Require().Nil(err)
	s.EqualValues(expected, actual)
}

func (s *WorkflowInvokerTestSuite) TestInvokerAssemblesAbusePayloadCorrectlyWhenPRAndMissingHead() {
	commitSha := types.CommitSha("c8cfbd75232e224c14ca613ff7d48c3499a1b1be")

	webhookDeliveryID := uuid.New().String()
	var pullRequestEvent = NewEvent(
		&webhookDeliveryID,
		types.DefaultBranch,
		commitSha,
		"",
		"pull_request",
		"opened",
		nil,
		time.Time{},
		eventOriginTime,
		stubPullRequestEvent,
	)

	prEvent, _ := pullRequestEvent.Ghe.(*githubgo.PullRequestEvent)
	prEvent.PullRequest.Head = nil
	s.mockGitHubTwirpClient.EXPECT().GetActorsInfo(mock.Anything, []types.GlobalID{
		actorID,
		"targetRepoOwner",
		"billingPlanOwner",
		"targetRepo",
	}).Return(&ghtwirp.ActorsInfo{
		Actors: partialActors,
	}, nil)
	expected := &types.PartialAbuseTriggerInfo{
		TriggerEvent:       "pull_request",
		TriggerEventAction: "opened",
		Actor: &types.ActionsAbuseUser{
			ID:        "actor",
			Name:      "actor",
			Type:      "User",
			Plan:      "free",
			CreatedAt: actorCreatedAt.AsTime(),
			IsHammy:   false,
		},
		TargetRepoOwner: &types.ActionsAbuseUser{
			ID:        "targetRepoOwner",
			Name:      "targetRepoOwner",
			Type:      "Organization",
			Plan:      "enterprise",
			CreatedAt: actorCreatedAt.AsTime(),
			IsHammy:   true,
		},
		HeadRepoOwner: nil,
		BillingPlanOwner: &types.ActionsAbuseUser{
			ID:        "billingPlanOwner",
			Name:      "billingPlanOwner",
			Type:      "Organization",
			Plan:      "enterprise",
			CreatedAt: actorCreatedAt.AsTime(),
			IsHammy:   true,
		},
		TargetRepository: &types.ActionsAbuseRepository{
			ID:        "targetRepo",
			Private:   true,
			NWO:       "targetRepo",
			CreatedAt: actorCreatedAt.AsTime(),
		},
		HeadRepository: nil,
	}

	actual, err := s.invoker.buildPartialAbuseContext(
		context.Background(),
		pullRequestEvent,
		actorID,
		"targetRepoOwner",
		"billingPlanOwner",
		"targetRepo",
	)
	s.Require().Nil(err)
	s.EqualValues(expected, actual)
}

var dependabotPRTRef = "some/branch/possibly/created/by/dependabot"

func (s *WorkflowInvokerTestSuite) TestDependabotPRTSupplyChainAttack_RefFilter() {
	// explanation of test cases in this issues discussion https://github.com/github/c2c-actions/issues/3481#issuecomment-999073243
	testCases := []struct {
		ref      string
		expected bool
	}{
		{
			ref:      dependabotPRTRef,
			expected: true,
		},
		{
			ref:      "25d1dependabot/nuget",
			expected: true,
		},
		{
			ref:      "dependabot/something/something",
			expected: true,
		},
		{
			ref:      "canary",
			expected: false,
		},
	}

	for _, tc := range testCases {
		s.Run(tc.ref, func() {
			s.mockGitHubTwirpClient.EXPECT().IsDependabotAssociatedRef(mock.Anything, mock.Anything, mock.Anything).Return(true, nil).Maybe()
			s.invoker.inv.Event.Ghe = buildDependabotPRTRef(tc.ref)
			s.invoker.inv.Event.Name = flowevents.PullRequestTarget

			vulnerable, err := s.invoker.isDependabotAssociatedRef(context.Background(), s.invoker.inv.Event.Name, s.invoker.inv.Event.Ghe)
			s.Assert().Nil(err)
			s.Assert().Equal(tc.expected, vulnerable)
		})
	}
}

func (s *WorkflowInvokerTestSuite) TestDependabotPRTSupplyChainAttack_Positive() {
	data := newWorkflowInvocationData()

	s.invoker.inv.Event.Ghe = buildDependabotPRTRef(dependabotPRTRef)
	s.invoker.inv.Event.Name = flowevents.PullRequestTarget

	s.mockGitHubTwirpClient.EXPECT().IsDependabotAssociatedRef(mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.mockGitHubTwirpClient.EXPECT().GetAdditionalWorkflows(mock.Anything, mock.Anything, mock.Anything).Return(&ghtwirp.AdditionalWorkflows{}, nil)
	s.mockGitHubTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.MatchEnvPathLabRulesetWorkflows, mock.Anything).Return(true)

	err := s.invoker.Start(context.Background(), data, false)
	s.Assert().Nil(err)
	s.mockGitHubTwirpClient.AssertCalled(s.T(), "IsDependabotAssociatedRef", mock.Anything, mock.Anything, dependabotPRTRef)
	s.mockBuildInvoker.AssertNumberOfCalls(s.T(), "Run", 0)
}

func (s *WorkflowInvokerTestSuite) TestDependabotPRTSupplyChainAttack_Negative() {
	data := newWorkflowInvocationData()

	s.invoker.inv.Event.Ghe = buildDependabotPRTRef(dependabotPRTRef)
	s.invoker.inv.Event.Name = flowevents.PullRequestTarget

	s.mockGitHubTwirpClient.EXPECT().IsDependabotAssociatedRef(mock.Anything, mock.Anything, mock.Anything).Return(false, nil)
	s.mockGitHubTwirpClient.EXPECT().GetAdditionalWorkflows(mock.Anything, mock.Anything, mock.Anything).Return(&ghtwirp.AdditionalWorkflows{}, nil)
	s.mockGitHubTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, github.MatchEnvPathLabRulesetWorkflows, mock.Anything).Return(true)

	err := s.invoker.Start(context.Background(), data, false)
	s.Assert().Nil(err)
	s.mockGitHubTwirpClient.AssertCalled(s.T(), "IsDependabotAssociatedRef", mock.Anything, mock.Anything, dependabotPRTRef)
	s.mockBuildInvoker.AssertNumberOfCalls(s.T(), "Run", 2)
}

func (s *WorkflowInvokerTestSuite) TestDependabotPRTSupplyChainAttack_Error() {
	data := newWorkflowInvocationData()

	mockWorkflowProvider := &azp.MockWorkflowProvider{}
	s.invoker.provider = mockWorkflowProvider

	mockWorkflowProvider.EXPECT().GetWorkflows(mock.Anything, mock.Anything, mock.Anything, data).Return(data.PipelineFiles)

	s.invoker.inv.Event.Ghe = buildDependabotPRTRef(dependabotPRTRef)
	s.invoker.inv.Event.Name = flowevents.PullRequestTarget

	internalErr := errs.New("some error")

	s.mockGitHubTwirpClient.EXPECT().IsDependabotAssociatedRef(mock.Anything, mock.Anything, mock.Anything).Return(false, internalErr)

	err := s.invoker.Start(context.Background(), data, false)
	s.Assert().Error(err)
	s.Assert().Equal(err.Errors()[0].errorType, dependabotRefCheckErrType)
	s.mockGitHubTwirpClient.AssertCalled(s.T(), "IsDependabotAssociatedRef", mock.Anything, mock.Anything, mock.Anything)
	s.mockBuildInvoker.AssertNumberOfCalls(s.T(), "Run", 0)
}

type invDataOption func(*types.WorkflowInvocationData)

func newWorkflowInvocationData(opts ...invDataOption) *types.WorkflowInvocationData {
	nwo, _ := types.ParseNWO("user/repo")
	data := &types.WorkflowInvocationData{
		IsActionsDisabledAtAnyLevel: false,
		IsActionsDisabledByOwner:    false,
		AllowsAllActions:            true,
		NWO:                         nwo,
		FeatureFlags: types.InvokerFeatureFlags{
			IsActionsEligible: true,
			LaunchLabEnabled:  true,
		},
		RepoIsPrivate: false,
		PipelineFiles: []types.ResolvedFile{
			{
				Path: ".github/workflows/workflow.yml",
				Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				SHA:  "",
			},
			{
				Path: ".github/workflows/other.yml",
				Text: "on: push\njobs:\n  build:\n    steps:\n    - uses: ./ci/foo",
				SHA:  "",
			},
		},
		Owner: types.WorkflowInvocationOwner{
			GlobalID:   types.NilGlobalID,
			DatabaseID: 0,
			Type:       "User",
		},
		PlanOwner: types.WorkflowInvocationPlanOwner{
			GlobalID: types.NilGlobalID,
			Name:     "user",
			PlanName: "Pro",
			Type:     "User",
		},
		RepoDatabaseID: 0,
		RepoGlobalID:   types.NilGlobalID,
		RepoGitURL:     "www.example.com/user/repo.git",
		Actor: types.WorkflowInvocationActorData{
			ActionInvocationBlocked: false,
			IsSpammy:                false,
			NoVerifiedEmail:         false,
			Type:                    "User",
			DatabaseID:              0,
			GlobalID:                types.NilGlobalID,
		},
	}
	for _, opt := range opts {
		opt(data)
	}
	return data
}

func (s *WorkflowInvokerTestSuite) assertLogged(message string) {
	s.Assert().Contains(s.recordingLogger.String(), message)
}

func (s *WorkflowInvokerTestSuite) assertNotLogged(message string) {
	s.Assert().NotContains(s.recordingLogger.String(), message)
}

func TestWorkflowInvokerTestSuite(t *testing.T) {
	suite.Run(t, new(WorkflowInvokerTestSuite))
}

func buildDependabotPRTRef(ref string) flowevents.HasPullRequest {
	repositoryA := int64(1)
	repositoryB := int64(2)
	dependabotRef := ref
	dependabotPRTAttackStub := &gogithub.PullRequestEvent{
		PullRequest: &gogithub.PullRequest{
			Head: &gogithub.PullRequestBranch{
				Ref: &forkedRef,
				Repo: &gogithub.Repository{
					ID:     &repositoryA,
					NodeID: &forkRepoNodeID,
					Name:   &forkRepoName,
					Owner: &gogithub.User{
						Login:  &forkRepoOwner,
						NodeID: &forkRepoOwnerNodeID,
					},
				},
			},
			Base: &gogithub.PullRequestBranch{
				Ref: &dependabotRef,
				Repo: &gogithub.Repository{
					ID: &repositoryB,
				},
			},
		},
	}
	return NewEvent(
		&webhookDeliveryID,
		types.DefaultBranch,
		commitSha,
		"",
		"pull_request",
		"opened",
		nil,
		time.Time{},
		eventOriginTime,
		dependabotPRTAttackStub,
	).Ghe.(flowevents.HasPullRequest)
}
