package repocheck

import (
	"context"
	"errors"
)

// SanitizeError converts internal errors to user-friendly messages.
func SanitizeError(err error) string {
	if err == nil {
		return ""
	}

	// Check for specific known error types first
	var validationErr *ValidationError
	if errors.As(err, &validationErr) {
		return "Missing required information."
	}

	// Our explicit check timeout takes priority over domain-specific errors,
	// since it wraps whatever sub-operation was running when the timeout fired.
	if errors.Is(err, ErrCheckTimeout) {
		return "The license check timed out."
	}

	// Domain-specific sentinel errors
	if errors.Is(err, ErrCheckJobCreation) {
		return "Unable to start license check."
	}
	if errors.Is(err, ErrCheckJobUpdate) {
		return "Unable to update license check status."
	}
	if errors.Is(err, ErrPolicyNotFound) {
		return "No license policy is configured for this repository."
	}
	if errors.Is(err, ErrPolicyLoad) {
		return "Unable to load license policy."
	}
	if errors.Is(err, ErrSnapshotStatus) {
		return "Unable to check dependency snapshot status."
	}
	if errors.Is(err, ErrDependencyFetch) {
		return "Unable to retrieve dependency information."
	}
	if errors.Is(err, ErrAlertUpdate) {
		return "Unable to update license alerts."
	}

	// Context errors checked after domain-specific errors
	if errors.Is(err, context.DeadlineExceeded) {
		return "A request timed out."
	}
	if errors.Is(err, context.Canceled) {
		return "The request was cancelled."
	}

	return "An unexpected error occurred."
}
