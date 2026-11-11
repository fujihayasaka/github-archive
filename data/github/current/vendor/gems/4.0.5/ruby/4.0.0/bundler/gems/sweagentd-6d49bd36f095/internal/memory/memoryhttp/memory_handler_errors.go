package memoryhttp

import (
	"context"
	"errors"
	"net/http"

	"github.com/github/sweagentd/internal/memory/core"
)

// handleDomainError resolves expected errors to their appropriate HTTP responses.
// If the error is not recognized, it returns a generic internal server error.
// The expected error codes are:
// - ErrEmptyRepoNWO - 400 Bad Request
// - ErrEmptyRepoOwner - 400 Bad Request
// - ErrEmptyRepoName - 400 Bad Request
// - ErrInvalidRepoNWO - 400 Bad Request
// - ErrNoMemoriesNotFound - 204 No Content
// - ErrRepositoryAccessDenied - 403 Forbidden
// - ErrRepositoryOAuthAccessRestriction - 403 Forbidden
// Other errors will return a 500 Internal Server Error.
func (h *MemoryHandler) handleDomainError(ctx context.Context, w http.ResponseWriter, err error) {
	errorName, message := h.errorToNameAndMessage(err)
	statusCode := h.errorToStatusCode(err)

	// Record telemetry for known errors
	if errorName != "" {
		h.obsv.Increment(ctx, "MemoryHandler.handleDomainError", memoryRequestMetricTags(ctx, map[string]string{"error": errorName}))
	}

	// For 204 No Content, return without a body
	if statusCode == http.StatusNoContent {
		w.WriteHeader(statusCode)
		return
	}

	// For unknown errors, log them for debugging but return a generic message to clients
	// to avoid leaking internal system details.
	if message == "" {
		h.requestLogger(ctx).WithError(err).Error("unhandled domain error")
		h.obsv.Increment(ctx, "MemoryHandler.handleDomainError", memoryRequestMetricTags(ctx, map[string]string{"error": "unknown"}))
		message = "An internal error occurred"
	}

	// Report server errors to Sentry/Failbot for visibility in Splunk prod-exceptions.
	if statusCode >= http.StatusInternalServerError {
		h.reportException(ctx, err)
	}

	http.Error(w, message, statusCode)
}

// reportException reports an error to the exception reporter (Sentry/Failbot)
// so it appears in Splunk's prod-exceptions index. Cancellation and timeout
// errors are skipped to avoid noisy alerts from client disconnects.
func (h *MemoryHandler) reportException(ctx context.Context, err error) {
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return
	}
	_ = h.obsv.Reporter.Report(context.WithoutCancel(ctx), err, nil)
}

// errorToNameAndMessage maps domain errors to their telemetry names and user-facing messages.
func (h *MemoryHandler) errorToNameAndMessage(err error) (errorName, message string) {
	switch {
	case errors.Is(err, core.ErrEmptyRepoNWO):
		return "ErrEmptyRepoNWO", "repository NWO cannot be empty"
	case errors.Is(err, core.ErrEmptyRepoOwner):
		return "ErrEmptyRepoOwner", "repository owner cannot be empty"
	case errors.Is(err, core.ErrEmptyRepoName):
		return "ErrEmptyRepoName", "repository name cannot be empty"
	case errors.Is(err, core.ErrInvalidRepoNWO):
		return "ErrInvalidRepoNWO", "invalid repository NWO format"
	case errors.Is(err, core.ErrNoMemoriesNotFound):
		return "ErrNoMemoriesNotFound", ""
	case errors.Is(err, core.ErrFeatureNotEnabled):
		// Return 404 to avoid leaking information about the existence of the repository or user
		return "ErrFeatureNotEnabled", "Resource not found"
	case errors.Is(err, core.ErrMemoryContainsSecrets):
		return "ErrMemoryContainsSecrets", "Memory contains secrets and cannot be saved"
	case errors.Is(err, core.ErrMemoryNotFound):
		return "ErrMemoryNotFound", "Memory not found"
	case errors.Is(err, core.ErrMemoryFactNotFound):
		return "ErrMemoryFactNotFound", "A memory with the specified fact and scope was not found."
	case errors.Is(err, core.ErrRepositoryNotFound):
		return "ErrRepositoryNotFound", "Repository not found"
	case errors.Is(err, core.ErrSecretScanningRepositoryNotFound):
		// Use generic message to avoid exposing internal system details to users.
		// The error name is still specific for telemetry purposes.
		return "ErrSecretScanningRepositoryNotFound", "Repository not found"
	case errors.Is(err, core.ErrSecretScanningServiceUnavailable):
		return "ErrSecretScanningServiceUnavailable", "An upstream service is temporarily unavailable"
	case errors.Is(err, core.ErrRepositoryOAuthAccessRestriction):
		return "ErrRepositoryOAuthAccessRestriction", "Access to repository denied due to OAuth App access restrictions. An organization administrator must enable access for the app you're using. For more details, see <https://docs.github.com/organizations/managing-oauth-access-to-your-organizations-data/about-oauth-app-access-restrictions>."
	case errors.Is(err, core.ErrRepositoryAccessDenied):
		return "ErrRepositoryAccessDenied", "Access to repository denied"
	case errors.Is(err, core.ErrConcurrencyConflict):
		return "ErrConcurrencyConflict", "Conflict occurred, please try again"
	case errors.Is(err, core.ErrInvalidVoteDirection):
		return "ErrInvalidVoteDirection", "Invalid vote direction"
	case errors.Is(err, core.ErrBillingEntityUnresolved):
		return "ErrBillingEntityUnresolved", "a default billing entity has not been selected. Select a \"Usage billed to\" option in your Copilot settings, then try again."
	case errors.Is(err, core.ErrBillingEntityResolutionFailed):
		return "ErrBillingEntityResolutionFailed", "failed to resolve billing entity"
	default:
		return "", ""
	}
}

// errorToStatusCode maps domain errors to HTTP status codes for telemetry purposes.
func (h *MemoryHandler) errorToStatusCode(err error) int {
	switch {
	case errors.Is(err, core.ErrEmptyRepoNWO),
		errors.Is(err, core.ErrEmptyRepoOwner),
		errors.Is(err, core.ErrEmptyRepoName),
		errors.Is(err, core.ErrInvalidRepoNWO),
		errors.Is(err, core.ErrMemoryContainsSecrets),
		errors.Is(err, core.ErrInvalidVoteDirection):
		return http.StatusBadRequest
	case errors.Is(err, core.ErrNoMemoriesNotFound):
		return http.StatusNoContent
	case errors.Is(err, core.ErrMemoryFactNotFound):
		return http.StatusUnprocessableEntity
	case errors.Is(err, core.ErrFeatureNotEnabled),
		errors.Is(err, core.ErrMemoryNotFound),
		errors.Is(err, core.ErrRepositoryNotFound),
		errors.Is(err, core.ErrSecretScanningRepositoryNotFound):
		return http.StatusNotFound
	case errors.Is(err, core.ErrRepositoryAccessDenied),
		errors.Is(err, core.ErrRepositoryOAuthAccessRestriction):
		return http.StatusForbidden
	case errors.Is(err, core.ErrConcurrencyConflict):
		return http.StatusConflict
	case errors.Is(err, core.ErrBillingEntityUnresolved):
		return http.StatusUnprocessableEntity
	case errors.Is(err, core.ErrSecretScanningServiceUnavailable):
		return http.StatusBadGateway
	default:
		return http.StatusInternalServerError
	}
}
