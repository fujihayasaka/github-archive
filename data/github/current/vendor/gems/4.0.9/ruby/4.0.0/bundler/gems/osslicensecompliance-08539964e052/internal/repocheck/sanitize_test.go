package repocheck

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSanitizeError(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected string
	}{
		{
			name:     "nil error",
			err:      nil,
			expected: "",
		},
		{
			name:     "validation error",
			err:      NewValidationError([]string{"repository_id", "commit_sha"}),
			expected: "Missing required information.",
		},
		{
			name:     "context deadline exceeded",
			err:      context.DeadlineExceeded,
			expected: "A request timed out.",
		},
		{
			name:     "explicit check timeout",
			err:      ErrCheckTimeout,
			expected: "The license check timed out.",
		},
		{
			name:     "context canceled",
			err:      context.Canceled,
			expected: "The request was cancelled.",
		},
		{
			name:     "check job creation error",
			err:      ErrCheckJobCreation,
			expected: "Unable to start license check.",
		},
		{
			name:     "check job update error",
			err:      ErrCheckJobUpdate,
			expected: "Unable to update license check status.",
		},
		{
			name:     "snapshot status error",
			err:      fmt.Errorf("%w: %w", ErrSnapshotStatus, errors.New("connection refused")),
			expected: "Unable to check dependency snapshot status.",
		},
		{
			name:     "dependency fetch error",
			err:      fmt.Errorf("%w: %w", ErrDependencyFetch, errors.New("grpc timeout")),
			expected: "Unable to retrieve dependency information.",
		},
		{
			name:     "policy load error",
			err:      fmt.Errorf("%w: %w", ErrPolicyLoad, errors.New("azure blob unavailable")),
			expected: "Unable to load license policy.",
		},
		{
			name:     "policy not found error",
			err:      ErrPolicyNotFound,
			expected: "No license policy is configured for this repository.",
		},
		{
			name:     "alert update error",
			err:      fmt.Errorf("%w: %w", ErrAlertUpdate, errors.New("database connection failed")),
			expected: "Unable to update license alerts.",
		},
		{
			name:     "unknown error",
			err:      errors.New("something completely unexpected"),
			expected: "An unexpected error occurred.",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := SanitizeError(tt.err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestSanitizeError_WrappedErrors(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected string
	}{
		{
			name:     "joined check job creation error",
			err:      errors.Join(ErrCheckJobCreation, errors.New("database connection failed")),
			expected: "Unable to start license check.",
		},
		{
			name:     "double-wrapped snapshot error",
			err:      fmt.Errorf("outer context: %w", fmt.Errorf("%w: %w", ErrSnapshotStatus, errors.New("rpc error"))),
			expected: "Unable to check dependency snapshot status.",
		},
		{
			name:     "wrapped policy load with internal details",
			err:      fmt.Errorf("%w: %w", ErrPolicyLoad, errors.New("azure blob storage unavailable")),
			expected: "Unable to load license policy.",
		},
		{
			name:     "wrapped dependency fetch with grpc error",
			err:      fmt.Errorf("%w: %w", ErrDependencyFetch, errors.New("grpc: connection refused")),
			expected: "Unable to retrieve dependency information.",
		},
		{
			name:     "wrapped context deadline in check job",
			err:      fmt.Errorf("%w: %w", ErrCheckJobUpdate, context.DeadlineExceeded),
			expected: "Unable to update license check status.",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := SanitizeError(tt.err)
			assert.Equal(t, tt.expected, result)
		})
	}
}
