// Package jobutils provides utilities for job error handling.
package jobutils

import (
	"bytes"
	"context"
	_ "embed"
	"errors"
	"fmt"
	"html/template"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
)

// TODO(colbylwilliams): Move some of this to joberrors

// ErrorCommentTemplate represents the type of error comment to generate.
type ErrorCommentTemplate string

// ErrorCommentTemplate constants define the types of error comment templates.
const (
	ErrorCommentTemplateFixComment ErrorCommentTemplate = "error_fix_comment"
	ErrorCommentTemplateDefault    ErrorCommentTemplate = "default"
)

func (t ErrorCommentTemplate) defaultTelemetryKey() string {
	switch t {
	case ErrorCommentTemplateFixComment:
		return "comment-generic-error"
	default:
		return "generic-error"
	}
}

//go:embed error_fix_comment.md
var errorFixCommentTemplate string

// UserVisibleCommentForUnhandledError is an error that occurs when something goes wrong
// that we need to let the end user know about in the best way possible.
//
// IMPORTANT: This error will cause a new comment to be posted to the issue or PR
type UserVisibleCommentForUnhandledError struct {
	RequestID    string
	Err          error
	Assignment   *jobs.Assignment
	ActorLogin   string
	IssueNumber  int
	Template     ErrorCommentTemplate
	RulesResult  *jobservice.CheckRulesResult
	TelemetryKey string
}

// NewUnhandledErrorWithPRComment creates a new UserVisibleCommentForUnhandledError with the given error,
// assignment, and actor login. This error will cause a comment to be posted to the PR.
func NewUnhandledErrorWithPRComment(ctx context.Context, err error, assignment *jobs.Assignment, actorLogin string) *UserVisibleCommentForUnhandledError {
	return &UserVisibleCommentForUnhandledError{
		Err:        err,
		ActorLogin: actorLogin,
		Assignment: assignment,
		RequestID:  requestid.GetGitHubRequestID(ctx),
		Template:   ErrorCommentTemplateDefault,
	}
}

func (e *UserVisibleCommentForUnhandledError) Error() string {
	return fmt.Sprintf("failed to handle assignment: %v", e.Err)
}

// GenerateComment generates the comment body to be posted to the PR or issue.
func (e *UserVisibleCommentForUnhandledError) GenerateComment() (string, error) {
	var tmplMd string

	switch e.Template {
	case ErrorCommentTemplateFixComment:
		tmplMd = errorFixCommentTemplate
	case ErrorCommentTemplateDefault:
		e.Template = ErrorCommentTemplateFixComment
		tmplMd = errorFixCommentTemplate
	default:
		return "", goerrors.Errorf("unknown error template: %s", e.Template)
	}

	tmpl, err := template.New(string(e.Template)).Parse(tmplMd)
	if err != nil {
		return "", goerrors.Errorf("failed to parse template: %w", err)
	}

	if e.TelemetryKey == "" {
		e.TelemetryKey = e.Template.defaultTelemetryKey()
	}

	var buf bytes.Buffer
	err = tmpl.Execute(&buf, &struct {
		RequestID   string
		Login       string
		Error       template.HTML
		IssueNumber int
		RulesResult *jobservice.CheckRulesResult
		Telemetry   template.HTML
	}{
		RequestID:   e.RequestID,
		Login:       e.ActorLogin,
		Error:       template.HTML(fmt.Sprintf("%v", e.Err)), //nolint:gosec // This is controlled input
		IssueNumber: e.IssueNumber,
		RulesResult: e.RulesResult,
		Telemetry:   template.HTML(joberrors.GetTelemetryHTMLComment(e.TelemetryKey)), //nolint:gosec // This is controlled input
	})
	if err != nil {
		return "", goerrors.Errorf("failed to execute template: %w", err)
	}
	body := buf.String()
	if body == "" {
		return "", goerrors.New("failed to generate comment body")
	}

	return body, nil
}

func (e *UserVisibleCommentForUnhandledError) Unwrap() error {
	return e.Err
}

// HandleErrorByType handles an error by its type, performing appropriate actions such as
// logging, creating error comments, or handling rate limits.
func HandleErrorByType(ctx context.Context, obsv observability.Exporters, cf github.ClientFactoryInterface, app sweagentd.AgenticApp, errToHandle error) error {
	tags := obsv.TelemetryTags(ctx)
	logger := obsv.LoggerWithTelemetry(ctx)

	// Keep track of if this error is a known error type
	var knownError bool

	// it's reasonable to assume this might be a github.GitHubAPIError error wrapped
	// in a UserVisibleCommentForUnhandledError error, so we let them fall through.

	var ghAPIErr *github.GitHubAPIError
	if errors.As(errToHandle, &ghAPIErr) {
		// Stat and log here, it will get reported to sentry higher in the stack
		obsv.Statter.Counter("hydro.github_api_error", tags, 1)
		logger.WithError(ghAPIErr).WithFields(kvp.String("gh.api_request_id", ghAPIErr.RequestID())).Error("GitHub API error")
		knownError = true
	}

	var errWith *UserVisibleCommentForUnhandledError
	if errors.As(errToHandle, &errWith) {
		obsv.Statter.Counter("hydro.unhandled_error_with_comment", tags, 1)
		if !limiter.IsAnyLimiterError(errToHandle) {
			err := createErrorComment(ctx, cf, obsv, app, errWith)
			if err != nil {
				// If we fail to create a comment, we don't want to return that error
				// here because we want to make sure the original error bubbles up and
				// gets processed correctly. But we do want to want to log and report it.
				obsv.LogAndReportError(ctx, err, "failed to create comment for error")
			}
		}
		knownError = true
	}

	if !knownError {
		obsv.Statter.Counter("hydro.unknown_error", tags, 1)
		logger.WithError(errToHandle).Error("Unknown error")
	}

	return errToHandle
}

func createErrorComment(ctx context.Context, cf github.ClientFactoryInterface, obsv observability.Exporters, app sweagentd.AgenticApp, errWith *UserVisibleCommentForUnhandledError) error {
	body, err := errWith.GenerateComment()
	if err != nil {
		return goerrors.Errorf("failed to generate comment body: %w", err)
	}

	gh, err := cf.NewClientForRepo(ctx, app, errWith.Assignment)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client: %w", err)
	}

	// Comment on the PR or issue depending on the scenario
	issueOrPRNumber := errWith.Assignment.PullRequestNumber
	if issueOrPRNumber == 0 {
		issueOrPRNumber = errWith.IssueNumber
		if issueOrPRNumber == 0 {
			return goerrors.New("unable to provide comment to user given no issue or PR number was passed")
		}
	}

	err = joberrors.CreateErrorComment(ctx, obsv, gh, errWith.Assignment.RepoID, issueOrPRNumber, body)
	if err != nil {
		return goerrors.Errorf("failed creating comment on PR: %w", err)
	}

	return nil
}
