// Package joberrors provides utilities for handling and categorizing errors
// related to job processing in the sweagentd service.
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
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

const (
	// ErrorCommentDefaultType is the default error type used in telemetry.
	ErrorCommentDefaultType string = "generic-error"
	// ErrorCommentTelemetryPrefix is the prefix used for CCA errors in telemetry.
	ErrorCommentTelemetryPrefix string = "copilot-coding-agent-error"
)

// ErrUnprocessableEntity represents an error for unprocessable entity (HTTP 422).
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

// MarkExistingError creates an error that has been marked using github.com/github/go-mark from an existing error.
// If a message other than "" is provided, a new marked error will be created that includes the message and original
func MarkExistingError(err error, message string) error {
	statusCode := 0
	var ghAPIErr *github.GitHubAPIError
	var azErr *azcore.ResponseError
	var sessionErr *SessionResponseError
	var capiErr *CAPIError
	switch {
	case errors.As(err, &ghAPIErr):
		statusCode = http.StatusInternalServerError
		if ghAPIErr.Response != nil {
			statusCode = ghAPIErr.Response.StatusCode
		}
	case errors.As(err, &azErr):
		statusCode = azErr.StatusCode
	case errors.As(err, &sessionErr):
		statusCode = sessionErr.StatusCode
	case errors.As(err, &capiErr):
		statusCode = capiErr.StatusCode()
	default:
		// handled below
	}
	if message != "" {
		err = goerrors.Errorf("%s: %w", message, err)
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
	default:
		// no marker
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

// JobError represents a standardized error with a service and code.
type JobError struct {
	Service string `json:"service"`
	Code    string `json:"code"`
}

// String returns the string representation of the JobError in the format "service:code".
func (e *JobError) String() string {
	return fmt.Sprintf("%s:%s", e.Service, e.Code)
}

// Error implements the error interface.
func (e *JobError) Error() string {
	return e.String()
}

var (
	// ErrCAPICustomerNotSelected represents a CAPI error when no customer is selected.
	ErrCAPICustomerNotSelected = &JobError{
		Service: "capi",
		Code:    "customer_not_selected",
	}

	// ErrCAPIPaymentRequired represents a CAPI error when payment is required or
	// the user does not have an active subscription.
	ErrCAPIPaymentRequired = &JobError{
		Service: "capi",
		Code:    "402",
	}

	// ErrCAPIRateLimited represents a CAPI error mapped from the HTTP 429 status code.
	ErrCAPIRateLimited = &JobError{
		Service: "capi",
		Code:    "429",
	}

	// ErrCAPIRateLimit represents a CAPI error using the string error code "rate_limited".
	ErrCAPIRateLimit = &JobError{
		Service: "capi",
		Code:    "rate_limited",
	}

	// ErrCAPIUserModelRateLimited represents a CAPI error when the user exceeds the per-model rate limit.
	ErrCAPIUserModelRateLimited = &JobError{
		Service: "capi",
		Code:    "user_model_rate_limited",
	}

	// ErrCAPIUserWeeklyRateLimited represents a CAPI error when the user exceeds the weekly rate limit.
	ErrCAPIUserWeeklyRateLimited = &JobError{
		Service: "capi",
		Code:    "user_weekly_rate_limited",
	}

	// ErrUpstreamRateLimit represents a rate limit from the upstream model API,
	// surfaced by the runtime's shared RATE_LIMIT_PATTERN (custom-agent-error.ts)
	// which matches "rate limit" / "rate_limit" / "too many requests" in error messages.
	ErrUpstreamRateLimit = &JobError{
		Service: "codex",
		Code:    "rate_limit",
	}

	// ErrCAPIQuotaExceeded represents a CAPI error when the request exceeds the quota.
	ErrCAPIQuotaExceeded = &JobError{
		Service: "capi",
		Code:    "quota_exceeded",
	}

	// ErrActionsOutOfDiskSpace represents an Actions error when the runner is
	// out of disk space.
	ErrActionsOutOfDiskSpace = &JobError{
		Service: "actions",
		Code:    "out_of_disk_space",
	}

	// ErrActionsOutOfMemory represents an Actions error when the job process was
	// killed due to memory constraints (e.g., exit code 137 indicating SIGKILL from OOM).
	ErrActionsOutOfMemory = &JobError{
		Service: "actions",
		Code:    "out_of_memory",
	}

	// ErrActionsTerminated represents an Actions error when the job process was
	// terminated unexpectedly (e.g., exit code 143 indicating SIGTERM).
	ErrActionsTerminated = &JobError{
		Service: "actions",
		Code:    "terminated",
	}

	// ErrActionsTimedOut represents an Actions error when the job times out.
	ErrActionsTimedOut = &JobError{
		Service: "actions",
		Code:    "timed_out",
	}

	// ErrActionsSetupSteps represents an Actions error during setup steps.
	ErrActionsSetupSteps = &JobError{
		Service: "actions",
		Code:    "setup_steps",
	}

	// ErrActionsNotSupported represents an Actions error when the requested
	// operation is not supported.
	ErrActionsNotSupported = &JobError{
		Service: "actions",
		Code:    "not_supported",
	}

	// ErrActionsBillingLocked represents an Actions error when the job fails to
	// start because the account is locked due to a billing issue.
	ErrActionsBillingLocked = &JobError{
		Service: "actions",
		Code:    "billing_locked",
	}

	// ErrActionsBillingOwnerDestroyed represents an Actions error when the job is
	// cancelled because the billing owner account has been destroyed.
	ErrActionsBillingOwnerDestroyed = &JobError{
		Service: "actions",
		Code:    "billing_owner_destroyed",
	}

	// ErrActionsDisabled represents an Actions error when GitHub Actions hosted runners
	// are disabled for the repository.
	ErrActionsDisabled = &JobError{
		Service: "actions",
		Code:    "disabled",
	}

	// ErrActionsExitCode6 represents an Actions error when the process exits with code 6.
	ErrActionsExitCode6 = &JobError{
		Service: "actions",
		Code:    "exit_code_6",
	}

	// ErrActionsLaunchFailure represents an Actions error when the job fails to launch.
	ErrActionsLaunchFailure = &JobError{
		Service: "actions",
		Code:    "launch_failure",
	}

	// ErrActionsMissingConclusion represents an Actions error when the workflow
	// completes but the conclusion is not available
	ErrActionsMissingConclusion = &JobError{
		Service: "actions",
		Code:    "missing_conclusion",
	}

	// ErrActionsOperationCancelled represents an Actions error when the operation was cancelled.
	ErrActionsOperationCancelled = &JobError{
		Service: "actions",
		Code:    "operation_cancelled",
	}

	// ErrActionsRepositoryArchived represents an Actions error when the job is
	// cancelled because the repository was archived.
	ErrActionsRepositoryArchived = &JobError{
		Service: "actions",
		Code:    "repository_archived",
	}

	// ErrActionsRepositoryTransferred represents an Actions error when the job is
	// cancelled because the repository was transferred.
	ErrActionsRepositoryTransferred = &JobError{
		Service: "actions",
		Code:    "repository_transferred",
	}

	// ErrActionsRunnerNotAcquired represents an Actions error when the job was not
	// acquired by a runner even after multiple attempts.
	ErrActionsRunnerNotAcquired = &JobError{
		Service: "actions",
		Code:    "runner_not_acquired",
	}

	// ErrActionsSelfHostedRunnerLost represents an error when a self-hosted runner loses communication with the server.
	ErrActionsSelfHostedRunnerLost = &JobError{
		Service: "actions",
		Code:    "self_hosted_runner_lost",
	}

	// ErrActionsWaitingTimedOut represents an Actions error when the job times out
	// waiting for a runner (e.g. misconfigured runner label).
	ErrActionsWaitingTimedOut = &JobError{
		Service: "actions",
		Code:    "waiting_timed_out",
	}

	// ErrInternalError represents a generic internal error.
	ErrInternalError = &JobError{
		Service: "sweagentd",
		Code:    "500",
	}

	// ErrRuntimeUnclassified represents an unclassified error from the runtime.
	ErrRuntimeUnclassified = &JobError{
		Service: "runtime",
		Code:    "unclassified",
	}

	// ErrInvalidCustomAgentConfig represents an error when the custom agent
	// configuration is invalid.
	ErrInvalidCustomAgentConfig = &JobError{
		Service: "sweagentd",
		Code:    "invalid_custom_agent_config",
	}

	// ErrInsufficientPermissions represents an error when there are insufficient
	// permissions to perform an operation.
	ErrInsufficientPermissions = &JobError{
		Service: "sweagentd",
		Code:    "insufficient_permissions",
	}

	// ErrAgenticAppUnauthorized represents an error when the user hasn't authorized the agentic app
	// assigned to a job.
	ErrAgenticAppUnauthorized = &JobError{
		Service: "sweagentd",
		Code:    "agentic_app_unauthorized",
	}

	// ErrPullRequestClosed represents an error when attempting to operate on a
	// closed pull request.
	ErrPullRequestClosed = &JobError{
		Service: "sweagentd",
		Code:    "pull_request_closed",
	}

	// ErrUserCancelled represents an error when the user cancels the operation.
	ErrUserCancelled = &JobError{
		Service: "sweagentd",
		Code:    "user_cancelled",
	}

	// ErrRateLimitExceeded represents an error when the rate limit is exceeded.
	ErrRateLimitExceeded = &JobError{
		Service: "sweagentd",
		Code:    "rate_limit_exceeded",
	}

	// ErrQueueFailure represents an error when queuing a job fails.
	ErrQueueFailure = &JobError{
		Service: "sweagentd",
		Code:    "queue_failure",
	}

	// ErrLaunchOptionsFailure represents an error when gathering launch options like getting agentic app details.
	ErrLaunchOptionsFailure = &JobError{
		Service: "sweagentd",
		Code:    "launch_options_failure",
	}

	// ErrRulesViolation represents an error when there is a repository rules violation.
	ErrRulesViolation = &JobError{
		Service: "sweagentd",
		Code:    "rules_violation",
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

// CAPIError represents an error with unexpected status code and response from CAPI.
type CAPIError struct {
	Response *http.Response
	Message  string
}

// NewCAPIError creates a new CAPIError with the provided HTTP response and message.
func NewCAPIError(resp *http.Response, msg string) *CAPIError {
	return &CAPIError{resp, msg}
}

// Error implements the error interface.
func (e *CAPIError) Error() string {
	message := e.Message
	if message == "" {
		message = "CAPI error"
	}

	statusCode := e.StatusCode()
	return fmt.Sprintf("%s: %d", message, statusCode)
}

// StatusCode returns the HTTP status code from the CAPIError.
func (e *CAPIError) StatusCode() int {
	if e.Response != nil {
		return e.Response.StatusCode
	}
	return 0
}
