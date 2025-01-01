package workflowinvoker

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/github/go-kvp"
	githubgo "github.com/google/go-github/v25/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/results/entities/checks"
	"github.com/github/launch/pkg/results/entities/events"
	launchutils "github.com/github/launch/utils"
	"github.com/github/launch/utils/testutils"

	"github.com/github/launch/clients/github"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/workflowparser"
)

func TestWorkflowUserError(t *testing.T) {
	t.Run("Test that isUserError is true for a UserError", func(tt *testing.T) {
		wfError := &WorkflowStartErr{
			stepErr: terrors.NewUserError("This is an Error"),
		}
		assert.True(tt, wfError.IsUserError())
	})
	t.Run("Test that isUserError is false for a non-UserError", func(tt *testing.T) {
		wfError := &WorkflowStartErr{
			stepErr: errors.New("this is an error"),
		}
		assert.False(tt, wfError.IsUserError())
	})
}

func TestParsingErrors(t *testing.T) {
	ctx := context.Background()
	_, err := workflowparser.Parse(ctx, types.ResolvedFile{Text: "\n\n\n<not yaml>", Path: "x.yml"}, types.WorkflowFeatureFlags{}, workflowparser.NullWorkflowSource{}, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	require.Error(t, err)

	annotation := errorToCheckSuiteAnnotation("some.yml", "errID", err, true, false)

	assert.Equal(t, github.CheckSuiteAnnotation{
		Title:           "Invalid workflow file",
		Path:            "some.yml",
		Message:         "You have an error in your yaml syntax on line 4",
		AnnotationLevel: annotationFailureLevel,
		Location: github.CheckAnnotationRange{
			StartLine: 4,
			EndLine:   4,
		},
	}, annotation)
}

func TestInternalErrors(t *testing.T) {
	ctx := context.Background()
	wfsrc := workflowparser.ErrorWorkflowSource{
		Error: terrors.NewInternalError(errors.New("this is an internal error")),
	}
	workflow := types.ResolvedFile{
		Text: `
on: push
jobs:
  thing:
    uses: ./.github/workflows/called.yml`,
		Path: "workflow.yml",
	}
	_, err := workflowparser.ParseWithCalledWorkflows(ctx, workflow, types.WorkflowFeatureFlags{}, wfsrc, launchutils.NewRuntimeHelper(false, "latest"), 0, observability.NewNullObservability())
	require.Error(t, err)

	annotation := errorToCheckSuiteAnnotation("workflow.yml", "errID", err, true, false)

	assert.Equal(t, github.CheckSuiteAnnotation{
		Title:           "Error",
		Path:            ".github",
		Message:         fmt.Sprintf(supportTemplate, fmt.Sprintf(contactSupportTemplate, "errID")),
		AnnotationLevel: annotationFailureLevel,
		Location: github.CheckAnnotationRange{
			StartLine: 1,
			EndLine:   1,
		},
	}, annotation)
}

func TestErrorObfuscation(t *testing.T) {
	checkStatusMessage := "please check whether the Actions service is operating normally at https://githubstatus.com"

	tests := []struct {
		name           string
		ghes           bool
		wantSupportMsg string
	}{
		{
			name:           "Production environments",
			wantSupportMsg: "An unexpected error has occurred and we've been automatically notified. Errors are sometimes temporary, so please try again.\n\nIf the problem persists, please check whether the Actions service is operating normally at https://githubstatus.com. If not, please try again once the outage has been resolved.\n\nShould you need to contact Support, please visit https://support.github.com/contact and include request ID: errID",
		},
		{
			name:           "GHES environment",
			ghes:           true,
			wantSupportMsg: "An unexpected error has occurred. Errors are sometimes temporary, so please try again.\n\nShould you need to contact Support, please visit https://support.github.com/contact and include request ID: errID",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			annotation := errorToCheckSuiteAnnotation("some.yml", "errID", errors.New("error message that we should not show to users"), true, tt.ghes)

			require.NotEqual(t, "error message that we should not show to users", annotation.Message)
			require.Equal(t, annotation.Message, tt.wantSupportMsg)

			if tt.ghes {
				require.NotContains(t, annotation.Message, checkStatusMessage)
			} else {
				require.Contains(t, annotation.Message, checkStatusMessage)
			}
		})
	}
}

func Test_AnyRetryableMakesMultiStartErrRetryable(t *testing.T) {
	tests := []struct {
		name     string
		errs     MultiWorkflowStartErr
		expected bool
	}{
		{
			name: "Any retryable error makes collection retryable",
			errs: NewMultiWorkflowStartError([]*WorkflowStartErr{
				{
					stepErr:   errors.New("some permanent error"),
					retryable: false,
				},
				{
					stepErr:   errors.New("some retryable error"),
					retryable: true,
				},
			}),
			expected: true,
		},
		{
			name: "Any retryable error makes collection retryable",
			errs: NewMultiWorkflowStartError([]*WorkflowStartErr{
				{
					stepErr:   errors.New("some permanent error"),
					retryable: false,
				},
				{
					stepErr:   errors.New("another permanent error"),
					retryable: false,
				},
			}),
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, tt.errs.IsRetryable())
		})
	}
}

func Test_AllUserErrorsMakesMultiStartErrUserError(t *testing.T) {
	tests := []struct {
		name     string
		errs     MultiWorkflowStartErr
		expected bool
	}{
		{
			name: "Some non-user errors makes collection not a user error",
			errs: NewMultiWorkflowStartError([]*WorkflowStartErr{
				{
					stepErr:   errors.New("system error"),
					retryable: false,
				},
				{
					stepErr:   terrors.NewUserError("syntax error"),
					retryable: true,
				},
			}),
			expected: false,
		},
		{
			name: "All user errors makes collection user error",
			errs: NewMultiWorkflowStartError([]*WorkflowStartErr{
				{
					stepErr:   terrors.NewUserError("syntax error in workflow A"),
					retryable: false,
				},
				{
					stepErr:   terrors.NewUserError("syntax error in workflow B"),
					retryable: false,
				},
			}),
			expected: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, tt.errs.IsUserError())
		})
	}
}

type ErrorHandlerTestSuite struct {
	suite.Suite

	testObservability  *Observability
	mockGHClient       *github.MockClient
	mockGHTwirp        *ghtwirp.MockClient
	mockResults        *results.MockClient
	mockEmitter        *slometrics.MockHydroEmitter
	mockWorkflowBuilds *deployer.MockWorkflowBuildsRepository

	fixtures struct {
		workflowBuildID    int64
		repositoryID       types.GlobalID
		actorID            types.GlobalID
		checkSuiteGlobalID types.GlobalID
		invocation         Invocation
	}
}

func TestErrorHandlerTestSuite(t *testing.T) {
	suite.Run(t, new(ErrorHandlerTestSuite))
}

func (s *ErrorHandlerTestSuite) SetupTest() {
	s.testObservability = NewTestObservability(observability.NewTestObservability())
	s.mockGHClient = github.NewMockClient(s.T())
	s.mockGHTwirp = ghtwirp.NewMockClient(s.T())
	s.mockResults = results.NewMockClient(s.T())
	s.mockEmitter = slometrics.NewMockHydroEmitter(s.T())
	s.mockWorkflowBuilds = deployer.NewMockWorkflowBuildsRepository(s.T())

	s.mockEmitter.
		EXPECT().
		EmitQueueRun(mock.Anything).
		Return().
		Maybe()

	s.fixtures.workflowBuildID = 2
	s.fixtures.repositoryID = types.GlobalID(testutils.EncodeGlobalID("Repository", 1))
	s.fixtures.actorID = types.GlobalID(testutils.EncodeGlobalID("User", 32))
	s.fixtures.checkSuiteGlobalID = types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 2))
	s.fixtures.invocation = Invocation{
		ExecutingActor:  InvokingActor{ID: s.fixtures.actorID},
		TriggeringActor: InvokingActor{ID: s.fixtures.actorID},
		Target: invocationTarget{
			RepositoryID: s.fixtures.repositoryID,
		},
		Event: InvokingEvent{
			Name: flowevents.Push,
			Ghe:  &githubgo.PushEvent{},
		},
	}
}

func (s *ErrorHandlerTestSuite) SetupSubTest() {
	s.SetupTest()
}

func (s *ErrorHandlerTestSuite) TestCreateNewCheckSuiteWithError() {
	s.mockWorkflowBuilds.
		EXPECT().
		PersistError(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(int64(2), nil)
	s.mockWorkflowBuilds.
		EXPECT().
		TransitionToError(mock.Anything, mock.Anything, mock.Anything).
		Return(nil)

	invocation := Invocation{
		ExecutingActor:  InvokingActor{ID: actorID},
		TriggeringActor: InvokingActor{ID: actorID},
		Target: invocationTarget{
			RepositoryID: s.fixtures.repositoryID,
		},
		Event: InvokingEvent{
			Name: flowevents.Push,
			Ghe:  &githubgo.PushEvent{},
		}}

	handler := NewErrorHandler(s.testObservability, invocation, s.mockWorkflowBuilds, s.mockGHClient, s.mockGHTwirp, slometrics.New(s.mockEmitter), s.mockResults, false, false)

	errCtx := &WorkflowStartErrorContext{
		data: newWorkflowInvocationData(func(wid *types.WorkflowInvocationData) {
			wid.References = types.WorkflowInvocationReferences{
				EventCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA",
				},
				CheckoutCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA2",
				},
			}
		}),
	}
	err := errors.New("error message")
	workflowStartError := NewWorkflowStartError(errCtx, err, "newSecrets")

	s.mockGHClient.EXPECT().CreateCheckSuite(mock.Anything, mock.Anything).Return(&github.CreateCheckSuiteResponse{
		WorkflowRun: &github.CheckSuiteWorkflowRun{
			DatabaseID: int64(42),
			RunNumber:  int64(4),
		},
		CheckSuiteIDPair: types.IDPair{
			GlobalID: s.fixtures.checkSuiteGlobalID,
		},
	}, nil)

	handler.CreateErrorCheckSuite(newTestContext(), workflowStartError)

	s.Equal(s.fixtures.checkSuiteGlobalID, workflowStartError.checkSuiteID)
}

func (s *ErrorHandlerTestSuite) TestUpdateCheckSuiteWithError() {
	const (
		repositoryID      = types.GlobalID("repo-1")
		commitRef         = types.GitRef("ref/heads/master")
		checkoutSha       = types.CommitSha("commit-2")
		checkoutRef       = types.GitRef("ref/heads/branch")
		workflowFilePath  = ".github/test.workflow"
		workflowRunID     = 1
		workflowRunNumber = 1
	)

	errCtx := &WorkflowStartErrorContext{
		data: newWorkflowInvocationData(func(wid *types.WorkflowInvocationData) {
			wid.References = types.WorkflowInvocationReferences{
				EventCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA",
				},
				CheckoutCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA2",
				},
			}
		}),
	}

	err := errors.New("error message")
	workflowStartError := NewWorkflowStartError(errCtx, err, "newSecrets")
	checkSuiteState, _ := types.NewCheckSuiteState(repositoryID, commitSha, commitRef, checkoutSha, checkoutRef, repositoryID, "test", workflowFilePath, workflowRunID, workflowRunNumber, types.NilGlobalID, "refs/heads/foo")
	checkSuiteState.CheckSuiteIDPair.GlobalID = s.fixtures.checkSuiteGlobalID
	workflowStartError.workflowBuildID = &s.fixtures.workflowBuildID
	workflowStartError.checkSuiteID = s.fixtures.checkSuiteGlobalID

	s.Run("update via graphql", func() {
		testutils.SetAppMode(s.T(), launchconfig.EnterpriseAppMode)

		s.mockGHClient.EXPECT().UpdateCheckSuite(mock.Anything, mock.MatchedBy(func(req github.UpdateCheckSuiteRequest) bool {
			s.Equal(github.CheckSuiteStartupFailureConclusion.String(), req.Conclusion)
			return true
		})).Return(&checkSuiteState.CheckSuiteIDPair, nil)

		s.mockWorkflowBuilds.
			EXPECT().
			TransitionToError(mock.Anything, mock.Anything, mock.Anything).
			Return(nil)

		handler := NewErrorHandler(s.testObservability, s.fixtures.invocation, s.mockWorkflowBuilds, s.mockGHClient, s.mockGHTwirp, slometrics.New(s.mockEmitter), s.mockResults, false, false)
		handler.CreateErrorCheckSuite(newTestContext(), workflowStartError)
	})

	s.Run("update via results", func() {
		s.mockResults.EXPECT().UpdateWorkflowRun(mock.Anything, mock.MatchedBy(func(update *events.WorkflowRunUpdate) bool {
			s.Equal(checks.CheckStatus_STATUS_COMPLETED, update.Status)
			s.Equal(checks.CheckConclusion_CONCLUSION_STARTUP_FAILURE, update.Conclusion)
			s.NotEmpty(update.CompletedAt)
			s.Len(update.Annotations, 1)
			annotation := update.Annotations[0]
			s.Equal("Error", annotation.Title.GetValue())
			s.Equal(checks.CheckAnnotation_LEVEL_FAILURE, annotation.AnnotationLevel)
			s.Equal(".github", annotation.Path.GetValue())
			s.Equal(int64(1), annotation.StartLine.GetValue())
			s.Equal(int64(1), annotation.EndLine.GetValue())
			s.Equal(int64(0), annotation.StartColumn.GetValue())
			s.Equal(int64(0), annotation.EndColumn.GetValue())
			s.NotEmpty(annotation.Message)
			return true
		})).Return(nil)

		s.mockWorkflowBuilds.
			EXPECT().
			TransitionToError(mock.Anything, mock.Anything, mock.Anything).
			Return(nil)

		handler := NewErrorHandler(s.testObservability, s.fixtures.invocation, s.mockWorkflowBuilds, s.mockGHClient, s.mockGHTwirp, slometrics.New(s.mockEmitter), s.mockResults, false, false)
		handler.CreateErrorCheckSuite(newTestContext(), workflowStartError)
	})
}

func (s *ErrorHandlerTestSuite) TestUserParsingErrorsNotGettingReported() {
	s.mockWorkflowBuilds.
		EXPECT().
		PersistError(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(int64(2), nil)
	s.mockWorkflowBuilds.
		EXPECT().
		TransitionToError(mock.Anything, mock.Anything, mock.Anything).
		Return(nil)

	spyLog := testutils.NewRecordingLogger()
	observabilitySpy := NewTestObservability(observability.New(spyLog.Logger, statter.NullStatter()))

	handler := NewErrorHandler(observabilitySpy, s.fixtures.invocation, s.mockWorkflowBuilds, s.mockGHClient, s.mockGHTwirp, slometrics.New(s.mockEmitter), s.mockResults, false, false)

	errCtx := &WorkflowStartErrorContext{
		data: newWorkflowInvocationData(func(wid *types.WorkflowInvocationData) {
			wid.References = types.WorkflowInvocationReferences{
				EventCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA",
				},
				CheckoutCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA2",
				},
			}
		}),
	}

	s.mockGHClient.EXPECT().CreateCheckSuite(mock.Anything, mock.Anything).Return(&github.CreateCheckSuiteResponse{
		WorkflowRun: &github.CheckSuiteWorkflowRun{
			DatabaseID: int64(42),
			RunNumber:  int64(4),
		},
		CheckSuiteIDPair: types.IDPair{
			GlobalID: s.fixtures.checkSuiteGlobalID,
		},
	}, nil)

	s.Run("Test that arbitrary error will be reported", func() {
		err := errors.New("unexpected error")
		workflowStartError := NewWorkflowStartError(errCtx, err, parserErrorErrType)

		handler.CreateErrorCheckSuite(newTestContext(), workflowStartError)

		s.NotContains(spyLog.String(), "workflow invocation skipped because of user error")
		s.Contains(spyLog.String(), "sentry_report=true")
	})

	// Clear logs
	spyLog.Reset()

	s.Run("Test that LineAnnotatedWorkflowError will be logged but not reported", func() {
		err := workflowparser.ParseError{}
		workflowStartError := NewWorkflowStartError(errCtx, err, parserErrorErrType)

		handler.CreateErrorCheckSuite(newTestContext(), workflowStartError)

		s.Contains(spyLog.String(), "workflow invocation skipped because of user error")
		s.NotContains(spyLog.String(), "sentry_report=true")
	})

	// Clear logs
	spyLog.Reset()

	s.Run("Test that ParserError will be logged but not reported", func() {
		err := workflowparser.ParseError{}
		workflowStartError := NewWorkflowStartError(errCtx, err, parserErrorErrType)

		handler.CreateErrorCheckSuite(newTestContext(), workflowStartError)

		s.Contains(spyLog.String(), "workflow invocation skipped because of user error")
		s.NotContains(spyLog.String(), "sentry_report=true")
	})

	// Clear logs
	spyLog.Reset()

	s.Run("Test that WorkflowParserError will be logged but not reported", func() {
		err := workflowparser.ParseError{}
		workflowStartError := NewWorkflowStartError(errCtx, err, parserErrorErrType)

		handler.CreateErrorCheckSuite(newTestContext(), workflowStartError)

		s.Contains(spyLog.String(), "workflow invocation skipped because of user error")
		s.NotContains(spyLog.String(), "sentry_report=true")
	})
}

func (s *ErrorHandlerTestSuite) TestInternalErrorsGettingReported() {
	s.mockWorkflowBuilds.
		EXPECT().
		PersistError(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(int64(2), nil)
	s.mockWorkflowBuilds.
		EXPECT().
		TransitionToError(mock.Anything, mock.Anything, mock.Anything).
		Return(nil)

	obs, mockLogger, mockStatter := observability.NewMockedObservability()

	statKey := "availability.queue_run"
	expectedFields := []kvp.Field{
		kvp.String("stat_key", statKey),
		kvp.String("status", "error"),
		kvp.String("error_type", "parser_error"),
		kvp.String("backend", types.WorkflowBackendInconclusive.String()),
	}
	matchElement := func(field kvp.Field) bool {
		for _, ef := range expectedFields {
			if field.Key == ef.Key {
				return s.Equal(field.Value(), ef.Value())
			}
		}

		return false
	}
	mockLogger.EXPECT().Debug(mock.Anything, "statTags",
		mock.MatchedBy(matchElement), mock.MatchedBy(matchElement),
		mock.MatchedBy(matchElement), mock.MatchedBy(matchElement),
	).Once()
	mockLogger.EXPECT().Debug(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return()
	mockStatter.EXPECT().Counter(mock.Anything, statKey, statter.Tags{"status": "error", "error_type": "parser_error"}, mock.Anything).Return()

	observabilitySpy := NewTestObservability(obs)

	handler := NewErrorHandler(observabilitySpy, s.fixtures.invocation, s.mockWorkflowBuilds, s.mockGHClient, s.mockGHTwirp, slometrics.New(s.mockEmitter), s.mockResults, false, false)

	errCtx := &WorkflowStartErrorContext{
		data: newWorkflowInvocationData(func(wid *types.WorkflowInvocationData) {
			wid.References = types.WorkflowInvocationReferences{
				EventCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA",
				},
				CheckoutCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA2",
				},
			}
		}),
	}

	s.mockGHClient.EXPECT().CreateCheckSuite(mock.Anything, mock.Anything).Return(&github.CreateCheckSuiteResponse{
		WorkflowRun: &github.CheckSuiteWorkflowRun{
			DatabaseID: int64(42),
			RunNumber:  int64(4),
		},
		CheckSuiteIDPair: types.IDPair{
			GlobalID: s.fixtures.checkSuiteGlobalID,
		},
	}, nil)
	err := terrors.NewInternalError(errors.New("internal error"))

	s.Run("Test that internal errors are reported in CreateErrorCheckSuite", func() {
		mockLogger.EXPECT().Report(mock.Anything, mock.Anything).Return().Once()

		workflowStartError := NewWorkflowStartError(errCtx, err, parserErrorErrType)
		handler.CreateErrorCheckSuite(newTestContext(), workflowStartError)
	})

	s.Run("Test that internal errors are reported in notifyInvalidWorkflow", func() {
		mockLogger.EXPECT().Report(mock.Anything, mock.Anything).Return().Once()
		mockLogger.EXPECT().Log(mock.Anything, "created error check suite for invalid workflow file", mock.Anything, mock.Anything, mock.Anything)

		handler.notifyInvalidWorkflow(newTestContext(), "foo/bar/.github/workflows/workflow.yml", err, errCtx.data, &s.fixtures.invocation.Event, "commitSHA")
	})
}

func (s *ErrorHandlerTestSuite) TestInternalParserErrorsNotGettingReported_WhenSkipParserErrorsEnabled() {
	s.mockWorkflowBuilds.
		EXPECT().
		PersistError(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(int64(2), nil)
	s.mockWorkflowBuilds.
		EXPECT().
		TransitionToError(mock.Anything, mock.Anything, mock.Anything).
		Return(nil)

	obs, mockLogger, mockStatter := observability.NewMockedObservability()

	mockLogger.EXPECT().Debug(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return()

	observabilitySpy := NewTestObservability(obs)

	handler := NewErrorHandler(observabilitySpy, s.fixtures.invocation, s.mockWorkflowBuilds, s.mockGHClient, s.mockGHTwirp, slometrics.New(s.mockEmitter), s.mockResults, false, true)

	errCtx := &WorkflowStartErrorContext{
		data: newWorkflowInvocationData(func(wid *types.WorkflowInvocationData) {
			wid.References = types.WorkflowInvocationReferences{
				EventCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA",
				},
				CheckoutCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA2",
				},
			}
		}),
	}

	s.mockGHClient.EXPECT().CreateCheckSuite(mock.Anything, mock.Anything).Return(&github.CreateCheckSuiteResponse{
		WorkflowRun: &github.CheckSuiteWorkflowRun{
			DatabaseID: int64(42),
			RunNumber:  int64(4),
		},
		CheckSuiteIDPair: types.IDPair{
			GlobalID: s.fixtures.checkSuiteGlobalID,
		},
	}, nil)
	err := terrors.NewInternalError(errors.New("internal error"))

	s.Run("Test that internal parser errors are not reported in CreateErrorCheckSuite when skipParserErrors enabled", func() {
		workflowStartError := NewWorkflowStartError(errCtx, err, parserErrorErrType)
		handler.CreateErrorCheckSuite(newTestContext(), workflowStartError)

		mockLogger.AssertNotCalled(s.T(), "Report", mock.Anything, mock.Anything)
		mockStatter.AssertNotCalled(s.T(), "Counter", mock.Anything, "availability.queue_run", mock.Anything, mock.Anything)
	})

	s.Run("Test that internal parser errors are not reported in notifyInvalidWorkflow when skipParserErrors enabled", func() {
		mockLogger.EXPECT().Log(mock.Anything, "created error check suite for invalid workflow file", mock.Anything, mock.Anything, mock.Anything)

		handler.notifyInvalidWorkflow(newTestContext(), "foo/bar/.github/workflows/workflow.yml", err, errCtx.data, &s.fixtures.invocation.Event, "commitSHA")

		mockLogger.AssertNotCalled(s.T(), "Report", mock.Anything, mock.Anything)
		mockStatter.AssertNotCalled(s.T(), "Counter", mock.Anything, "availability.queue_run", mock.Anything, mock.Anything)
	})
}

func (s *ErrorHandlerTestSuite) TestCreateNewCheckSuiteWithErrorOnPRFork() {
	s.mockWorkflowBuilds.
		EXPECT().
		PersistError(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(int64(2), nil)
	s.mockWorkflowBuilds.
		EXPECT().
		TransitionToError(mock.Anything, mock.Anything, mock.Anything).
		Return(nil)

	headRepositoryID := types.GlobalID(testutils.EncodeGlobalID("Repository", 2))
	headRepoNodeID := headRepositoryID.String()

	pullRequestInvocation := s.fixtures.invocation
	pullRequestInvocation.Event = InvokingEvent{
		Name: flowevents.PullRequest,
		Ghe: &githubgo.PullRequestEvent{
			PullRequest: &githubgo.PullRequest{
				Head: &githubgo.PullRequestBranch{
					Repo: &githubgo.Repository{
						NodeID: &headRepoNodeID,
					},
				},
			},
		},
	}

	handler := NewErrorHandler(s.testObservability, pullRequestInvocation, s.mockWorkflowBuilds, s.mockGHClient, s.mockGHTwirp, slometrics.New(s.mockEmitter), s.mockResults, false, false)

	errCtx := &WorkflowStartErrorContext{
		data: newWorkflowInvocationData(func(wid *types.WorkflowInvocationData) {
			wid.References = types.WorkflowInvocationReferences{
				EventCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA",
				},
				CheckoutCommit: types.WorkflowInvocationReference{
					CommitSHA: "commitSHA2",
				},
			}
		}),
	}
	err := errors.New("error message")
	workflowStartError := NewWorkflowStartError(errCtx, err, "newSecrets")

	checkSuiteMatcher := mock.MatchedBy(func(cs github.CreateCheckSuiteRequest) bool {
		s.Equal(s.fixtures.repositoryID, cs.RepositoryID)
		s.Equal(headRepositoryID, cs.HeadRepositoryID)
		return true
	})

	s.mockGHClient.EXPECT().CreateCheckSuite(mock.Anything, checkSuiteMatcher).Return(&github.CreateCheckSuiteResponse{
		WorkflowRun: &github.CheckSuiteWorkflowRun{
			DatabaseID: int64(42),
			RunNumber:  int64(4),
		},
		CheckSuiteIDPair: types.IDPair{
			GlobalID: s.fixtures.checkSuiteGlobalID,
		},
	}, nil)

	handler.CreateErrorCheckSuite(newTestContext(), workflowStartError)

	s.Equal(s.fixtures.checkSuiteGlobalID, workflowStartError.checkSuiteID)
}
