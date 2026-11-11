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
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
)

// TODO(colbylwilliams): Move some of this to joberrors

type ErrorCommentTemplate string

const (
	ErrorCommentTemplateFix           ErrorCommentTemplate = "error_fix"
	ErrorCommentTemplateFixIssue      ErrorCommentTemplate = "error_fix_issue"
	ErrorCommentTemplateFixIssueRules ErrorCommentTemplate = "error_fix_issue_rules"
	ErrorCommentTemplateFixComment    ErrorCommentTemplate = "error_fix_comment"
	ErrorCommentTemplateDefault       ErrorCommentTemplate = "default"
)

func (t ErrorCommentTemplate) defaultTelemetryKey() string {
	switch t {
	case ErrorCommentTemplateFix:
		return "generic-error"
	case ErrorCommentTemplateFixIssue:
		return "issue-generic-error"
	case ErrorCommentTemplateFixIssueRules:
		return "issue-rules-error"
	case ErrorCommentTemplateFixComment:
		return "comment-generic-error"
	default:
		return "generic-error"
	}
}

//go:embed error_fix.md
var errorFixTemplate string

//go:embed error_fix_issue.md
var errorFixIssueTemplate string

//go:embed error_fix_issue_rules.md
var errorFixIssueRulesTemplate string

//go:embed error_fix_comment.md
var errorFixCommentTemplate string

// UnhandledErrorWithComment is an error that occurs when something goes wrong
// that we need to let the end user know about in the best way possible.
//
// IMPORTANT: This error will cause a new comment to be posted to the issue or PR
type UnhandledErrorWithComment struct {
	RequestID    string
	Err          error
	Assignment   *jobs.Assignment
	ActorLogin   string
	IssueNumber  int
	ClosePR      bool
	Template     ErrorCommentTemplate
	RulesResult  *jobservice.CheckRulesResult
	TelemetryKey string
}

func (e *UnhandledErrorWithComment) Error() string {
	return fmt.Sprintf("failed to handle assignment: %v", e.Err)
}

func (e *UnhandledErrorWithComment) GenerateComment() (string, error) {
	var tmplMd string

	switch e.Template {
	case ErrorCommentTemplateFix:
		tmplMd = errorFixTemplate
	case ErrorCommentTemplateFixIssue:
		tmplMd = errorFixIssueTemplate
	case ErrorCommentTemplateFixIssueRules:
		tmplMd = errorFixIssueRulesTemplate
	case ErrorCommentTemplateFixComment:
		tmplMd = errorFixCommentTemplate
	case ErrorCommentTemplateDefault:
		if e.ClosePR {
			e.Template = ErrorCommentTemplateFix
			tmplMd = errorFixTemplate
		} else {
			e.Template = ErrorCommentTemplateFixComment
			tmplMd = errorFixCommentTemplate
		}
	default:
		return "", fmt.Errorf("unknown error template: %s", e.Template)
	}

	tmpl, err := template.New(string(e.Template)).Parse(tmplMd)
	if err != nil {
		return "", fmt.Errorf("failed to parse template: %w", err)
	}

	if e.TelemetryKey == "" {
		e.TelemetryKey = e.Template.defaultTelemetryKey()
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, &struct {
		RequestID   string
		Login       string
		Error       template.HTML
		IssueNumber int
		RulesResult *jobservice.CheckRulesResult
		Telemetry   template.HTML
	}{
		RequestID:   e.RequestID,
		Login:       e.ActorLogin,
		Error:       template.HTML(fmt.Sprintf("%v", e.Err)),
		IssueNumber: e.IssueNumber,
		RulesResult: e.RulesResult,
		Telemetry:   template.HTML(joberrors.GetTelemetryHTMLComment(e.TelemetryKey)),
	}); err != nil {
		return "", fmt.Errorf("failed to execute template: %w", err)
	}
	body := buf.String()
	if len(body) == 0 {
		return "", errors.New("failed to generate comment body")
	}

	return body, nil
}

func (e *UnhandledErrorWithComment) Unwrap() error {
	return e.Err
}

func NewUnhandledErrorWithIssueComment(ctx context.Context, err error, assignment *jobs.Assignment, closePR bool, actorLogin string, issueNumber int) *UnhandledErrorWithComment {
	return &UnhandledErrorWithComment{
		Err:         err,
		ActorLogin:  actorLogin,
		Assignment:  assignment,
		RequestID:   requestid.GetGitHubRequestID(ctx),
		Template:    ErrorCommentTemplateFixIssue,
		ClosePR:     closePR,
		IssueNumber: issueNumber,
	}
}

func NewUnhandledRulesErrorWithIssueComment(ctx context.Context, err error, assignment *jobs.Assignment, actorLogin string, issueNumber int, rulesResult *jobservice.CheckRulesResult) *UnhandledErrorWithComment {
	return &UnhandledErrorWithComment{
		Err:         err,
		ActorLogin:  actorLogin,
		Assignment:  assignment,
		RequestID:   requestid.GetGitHubRequestID(ctx),
		Template:    ErrorCommentTemplateFixIssueRules,
		IssueNumber: issueNumber,
		RulesResult: rulesResult,
	}
}

func NewUnhandledErrorWithPRComment(ctx context.Context, err error, assignment *jobs.Assignment, closePR bool, actorLogin string) *UnhandledErrorWithComment {
	return &UnhandledErrorWithComment{
		Err:        err,
		ActorLogin: actorLogin,
		Assignment: assignment,
		RequestID:  requestid.GetGitHubRequestID(ctx),
		Template:   ErrorCommentTemplateDefault,
		ClosePR:    closePR,
	}
}

func HandleErrorByType(ctx context.Context, obsv observability.Exporters, cf github.ClientFactoryInterface, errToHandle error) error {
	tags := obsv.TelemetryTags(ctx)
	logger := obsv.LoggerWithTelemetry(ctx)

	// Keep track of if this error is a known error type
	var knownError bool

	// it's reasonable to assume this might be a github.GitHubAPIError error wrapped
	// in a a UnhandledErrorWithComment error, so we let them fall through.

	var ghApiErr *github.GitHubAPIError
	if errors.As(errToHandle, &ghApiErr) {
		// Stat and log here, it will get reported to sentry higher in the stack
		obsv.Statter.Counter("hydro.github_api_error", tags, 1)
		logger.WithError(ghApiErr).WithFields(kvp.String("gh.api_request_id", ghApiErr.RequestID())).Error("GitHub API error")
		knownError = true
	}

	var errWith *UnhandledErrorWithComment
	if errors.As(errToHandle, &errWith) {
		obsv.Statter.Counter("hydro.unhandled_error_with_comment", tags, 1)
		if !limiter.IsAnyLimiterError(errToHandle) {
			err := createErrorComment(ctx, cf, obsv, errWith)
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

func createErrorComment(ctx context.Context, cf github.ClientFactoryInterface, obsv observability.Exporters, errWith *UnhandledErrorWithComment) error {
	body, err := errWith.GenerateComment()
	if err != nil {
		return fmt.Errorf("failed to generate comment body: %w", err)
	}

	gh, err := cf.NewClientForRepo(ctx, errWith.Assignment)
	if err != nil {
		return fmt.Errorf("failed to create GitHub client: %w", err)
	}

	// Comment on the PR or issue depending on the scenario
	issueOrPRNumber := errWith.Assignment.PullRequestNumber
	if issueOrPRNumber == 0 {
		issueOrPRNumber = errWith.IssueNumber
		if issueOrPRNumber == 0 {
			return errors.New("unable to provide comment to user given no issue or PR number was passed")
		}
	}

	err = joberrors.CreateErrorComment(ctx, obsv, gh, errWith.Assignment.RepoID, issueOrPRNumber, body)
	if err != nil {
		return fmt.Errorf("failed creating comment on PR: %w", err)
	}

	// When ClosePR is set (e.g. in "fix" scenarios), we should try to comment on and close the PR if possible.
	// However, if we are in this state and do not have a valid PR number we can try to fall back on commenting
	// on an issue if referenced (e.g. "fix" for issue assignment). Otherwise we'll just have to log the result.
	if errWith.ClosePR && errWith.Assignment.PullRequestNumber != 0 {
		// We'll still try to comment even if the PR close failed so don't return
		_ = joberrors.ClosePullRequest(ctx, obsv, gh, errWith.Assignment.RepoID, errWith.Assignment.PullRequestNumber, "Failed")
	}

	return nil
}
