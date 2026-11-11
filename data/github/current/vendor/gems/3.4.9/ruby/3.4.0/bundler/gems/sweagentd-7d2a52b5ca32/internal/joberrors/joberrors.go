package joberrors

import (
	"context"
	_ "embed"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/go-mark"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

//go:embed error_fix_repo_uninitialized.md
var ErrorRepositoryUninitialized string

const ErrorCommentDefaultType string = "generic-error"
const ErrorCommentTelemetryPrefix string = "copilot-coding-agent-error"

var ErrUnprocessableEntity = errors.New("unprocessable entity") // 422 equivalent - not built into "go-mark", but can be used

var copilotErrorPattern = regexp.MustCompile(fmt.Sprintf(`<!--\s*%s\s*:*\s*(?:[a-zA-Z0-9._-]*\s*)*-->`, ErrorCommentTelemetryPrefix))

// IsCopilotErrorComment checks if the provided body contains a Copilot error comment.
// The comment is identified by the pattern:
//
// <!-- copilot-coding-agent-error: <errorType> -->
//
// where <errorType> can be any alphanumeric string, including spaces and dashes.
func IsCopilotErrorComment(body string) bool {
	return copilotErrorPattern.MatchString(body)
}

// GetTelemetryHTMLComment returns a comment that can be used to track telemetry
// for errors in issues or PRs. The comment will be in the format:
//
// <!-- copilot-coding-agent-error: <errorType> -->
//
// where <errorType> is a lowercased, space-replaced version of the provided error type.
//
// If the errorType is empty, it defaults to "generic-error".
func GetTelemetryHTMLComment(errorType string) string {
	t := errorType
	if t == "" {
		t = ErrorCommentDefaultType
	}

	t = strings.ToLower(strings.ReplaceAll(strings.TrimSpace(t), " ", "-"))

	return fmt.Sprintf("<!-- %s: %s -->", ErrorCommentTelemetryPrefix, t)
}

// CreateErrorComment creates a comment on the issue or PR with the provided body.
func CreateErrorComment(ctx context.Context, obsv observability.Exporters, gh github.ClientInterface, repoID int64, issueOrPRNumber int, body string) error {
	// If the body does not already contain the copilot error HTML comment we add
	// it so we can track the error in telemetry, and ensure it is not duplicated
	if !IsCopilotErrorComment(body) {
		body = fmt.Sprintf("%s\n%s", body, GetTelemetryHTMLComment(ErrorCommentDefaultType))
	}

	tags, _, _ := requestctx.ToTelemetry(ctx, nil)
	obsv.Statter.Counter("errorHandling.createErrorComment", tags, 1)

	_, err := gh.CreateComment(ctx, repoID, issueOrPRNumber, body)
	return err
}

// MinimizeIssueErrorComments minimizes existing Copilot error comments on the issue.
func MinimizeIssueErrorComments(ctx context.Context, obsv observability.Exporters, gh github.ClientInterface, actx *github.IssueContext) {
	if actx.Issue.Comments.Len() > 0 {
		for _, comment := range actx.Issue.Comments.Nodes {
			if !comment.IsMinimized && comment.Author.IsCopilot(gh) && IsCopilotErrorComment(comment.Body) {
				if err := comment.Minimize(ctx, gh, github.GQLReportedContentClassifierOutdated); err != nil {
					obsv.LogAndReportError(ctx, err, "failed to minimize comment")
				}
			}
		}
	}
}

// CreateErrorCommentOnIssue creates an error comment on the issue with the provided body.
// It first minimizes existing Copilot error comments to ensure that the user is
// not overwhelmed with multiple error comments from Copilot on the same issue,
// and only sees the most recent one.
func CreateErrorCommentOnIssue(ctx context.Context, obsv observability.Exporters, gh github.ClientInterface, actx *github.IssueContext, body string) error {
	MinimizeIssueErrorComments(ctx, obsv, gh, actx)
	return CreateErrorComment(ctx, obsv, gh, actx.Repository.ID, actx.Issue.Number, body)
}

// Removes a 👀 reaction from the issue
func RemoveEyesFromIssue(ctx context.Context, obsv observability.Exporters, gh github.ClientInterface, owner, repo string, issueNumber int) {
	if err := gh.RemoveReactionFromIssue(ctx, owner, repo, issueNumber); err != nil {
		obsv.LogAndReportError(ctx, err, "failed to remove reaction")
	}
}

// ClosePullRequest closes a pull request with the given title prefix.
// It updates the title to include the prefix and changes the state to "closed".
//
// The title will be updated to replace "[WIP]" with "[<titlePrefix>]".
//
// Returns an error if the pull request cannot be retrieved or updated.
func ClosePullRequest(ctx context.Context, obsv observability.Exporters, gh github.ClientInterface, repoID int64, prNumber int, titlePrefix string) error {
	pr, err := gh.GetPullRequest(ctx, repoID, prNumber)
	if err != nil {
		return fmt.Errorf("failed to get PR: %w", err)
	}
	updatedTitle := strings.ReplaceAll(*pr.Title, "[WIP]", fmt.Sprintf("[%s]", titlePrefix))
	closedState := "closed"
	pr.Title = &updatedTitle
	pr.State = &closedState
	_, err = gh.UpdatePullRequest(ctx, repoID, pr)
	if err != nil {
		return fmt.Errorf("failed to update PR: %w", err)
	}
	return nil
}

// MarkExistingError creates an error that has been marked using github.com/github/go-mark from an existing error.
// If a message other than "" is provided, a new marked error will be created that includes the message and original
func MarkExistingError(err error, message string) error {
	statusCode := 0
	var ghAPIErr *github.GitHubAPIError
	var azErr *azcore.ResponseError
	var sessionErr *SessionResponseError
	if errors.As(err, &ghAPIErr) {
		statusCode = ghAPIErr.Response.StatusCode
	} else if errors.As(err, &azErr) {
		statusCode = azErr.StatusCode
	} else if errors.As(err, &sessionErr) {
		statusCode = sessionErr.StatusCode
	}
	if message != "" {
		err = fmt.Errorf("%s: %w", message, err)
	}
	return MarkedErrorFromStatusCode(err, statusCode)
}

// MarkedErrorFromStatusCode takes in an error and an HTTP status code and marks the error using github.com/github/go-mark.
func MarkedErrorFromStatusCode(err error, code int) error {
	var marker error
	switch code {
	case http.StatusConflict:
		marker = mark.ErrAlreadyExists
	case http.StatusBadRequest:
		marker = mark.ErrBadRequest
	case http.StatusForbidden:
		marker = mark.ErrForbidden
	case http.StatusNotFound:
		marker = mark.ErrNotFound
	case http.StatusRequestTimeout:
		marker = mark.ErrTimedout
	case http.StatusRequestEntityTooLarge:
		marker = mark.ErrTooLarge
	case http.StatusUnauthorized:
		marker = mark.ErrUnauthorized
	case http.StatusTooManyRequests:
		marker = mark.ErrTooManyRequests
	case http.StatusGone:
		marker = mark.ErrUnavailable
	case http.StatusUnprocessableEntity:
		marker = ErrUnprocessableEntity // 422 equivalent - not built into "go-mark", but can be used
	}
	if marker != nil && !errors.Is(err, marker) {
		return mark.With(marker, err)
	}
	return err
}

// StatusCodeFromMarkedError takes in an error that has been marked using github.com/github/go-mark and returns the corresponding HTTP status code.
func StatusCodeFromMarkedError(err error) int {
	switch {
	case errors.Is(err, mark.ErrAlreadyExists):
		return http.StatusConflict
	case errors.Is(err, mark.ErrCancelled):
		return http.StatusRequestTimeout
	case errors.Is(err, mark.ErrBadRequest):
		return http.StatusBadRequest
	case errors.Is(err, mark.ErrForbidden):
		return http.StatusForbidden
	case errors.Is(err, mark.ErrNotFound):
		return http.StatusNotFound
	case errors.Is(err, mark.ErrTimedout):
		return http.StatusRequestTimeout
	case errors.Is(err, mark.ErrTooLarge):
		return http.StatusRequestEntityTooLarge
	case errors.Is(err, mark.ErrUnauthorized):
		return http.StatusUnauthorized
	case errors.Is(err, mark.ErrTooManyRequests):
		return http.StatusTooManyRequests
	case errors.Is(err, mark.ErrUnavailable):
		return http.StatusGone
	case errors.Is(err, ErrUnprocessableEntity): // 422 equivalent - not built into "go-mark", but can be used
		return http.StatusUnprocessableEntity
	}
	return http.StatusInternalServerError
}

type JobError struct {
	Service string `json:"service"`
	Code    string `json:"code"`
}

func (e *JobError) String() string {
	return fmt.Sprintf("%s:%s", e.Service, e.Code)
}

func (e *JobError) Error() string {
	return e.String()
}

var (
	ErrorInternalError = &JobError{
		Service: "copilot",
		Code:    "500",
	}

	ErrorCAPIPaymentRequired = &JobError{
		Service: "capi",
		Code:    "402",
	}
	ErrorCAPIRateLimited = &JobError{
		Service: "capi",
		Code:    "429",
	}

	ErrorActionsOutOfDiskSpace = &JobError{
		Service: "actions",
		Code:    "out_of_disk_space",
	}
	ErrorActionsTimedOut = &JobError{
		Service: "actions",
		Code:    "timed_out",
	}
	ErrorActionsSetupSteps = &JobError{
		Service: "actions",
		Code:    "setup_steps",
	}
	ErrorActionsNotSupported = &JobError{
		Service: "actions",
		Code:    "not_supported",
	}
)

// MaxErrorMessageSize is the maximum size in characters for error messages.
const MaxErrorMessageSize = 1000

// MaxErrorContentSize is the maximum size in characters for error content.
const MaxErrorContentSize = 5000

// Truncate truncates a string to the given length, appending "..." to the end.
// If the provided length is 0, or the string is already shorter than the given
// length, the string is returned as-is.
func Truncate(s string, n int) string {
	if n <= 0 {
		return s
	}
	runes := []rune(s)
	if len(runes) <= n {
		return s
	}
	return string(runes[:n]) + "..."
}

// SessionResponseError represents an error with unexpected status code and body from sessions API.
type SessionResponseError struct {
	StatusCode int
	Body       string
}

// Error implements the error interface.
func (e *SessionResponseError) Error() string {
	return fmt.Sprintf("unexpected status code %d: %s", e.StatusCode, e.Body)
}
