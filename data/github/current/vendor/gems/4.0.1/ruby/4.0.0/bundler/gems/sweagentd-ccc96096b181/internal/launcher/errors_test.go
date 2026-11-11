package launcher

import (
	"errors"
	"net/http"
	"testing"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLaunchError_Error(t *testing.T) {
	err := &LaunchError{
		Err:       errors.New("test error"),
		Retriable: true,
	}
	assert.Equal(t, "test error", err.Error())
}

func TestLaunchError_Unwrap(t *testing.T) {
	innerErr := errors.New("inner error")
	err := &LaunchError{
		Err:       innerErr,
		Retriable: true,
	}
	assert.True(t, errors.Is(err, innerErr))
}

func TestLaunchError_IsRetriable(t *testing.T) {
	retriableErr := &LaunchError{
		Err:       errors.New("test"),
		Retriable: true,
	}
	assert.True(t, retriableErr.IsRetriable())

	nonRetriableErr := &LaunchError{
		Err:       errors.New("test"),
		Retriable: false,
	}
	assert.False(t, nonRetriableErr.IsRetriable())
}

func TestNonRetriableLaunchError(t *testing.T) {
	err := NonRetriableLaunchError(errors.New("config error"))

	var launchErr *LaunchError
	require.True(t, errors.As(err, &launchErr))
	assert.False(t, launchErr.IsRetriable())
	assert.Equal(t, "config error", launchErr.Error())
}

func TestRetriableLaunchError(t *testing.T) {
	err := RetriableLaunchError(errors.New("rate limit"))

	var launchErr *LaunchError
	require.True(t, errors.As(err, &launchErr))
	assert.True(t, launchErr.IsRetriable())
	assert.Equal(t, "rate limit", launchErr.Error())
}

// createGitHubAPIError creates a GitHubAPIError for testing with the given status code.
func createGitHubAPIError(statusCode int, message string) error {
	resp := &gg.Response{
		Response: &http.Response{
			StatusCode: statusCode,
		},
	}
	return github.NewGitHubAPIError(resp, message, nil)
}

func TestClassifyLaunchError(t *testing.T) {
	tests := []struct {
		name      string
		err       error
		message   string
		wantRetry bool
	}{
		{
			name:      "nil error returns nil",
			err:       nil,
			message:   "test",
			wantRetry: false,
		},
		{
			name:      "rate limit error is retriable",
			err:       limiter.NewRateLimitError(sweagentd.ClientTarget{}, "rate limited", limiter.Rate{}),
			message:   "failed to call API",
			wantRetry: true,
		},
		{
			name:      "GitHub 429 error is retriable",
			err:       createGitHubAPIError(http.StatusTooManyRequests, "rate limited"),
			message:   "failed to create workflow",
			wantRetry: true,
		},
		{
			name:      "GitHub 500 error is retriable",
			err:       createGitHubAPIError(http.StatusInternalServerError, "server error"),
			message:   "failed to create workflow",
			wantRetry: true,
		},
		{
			name:      "unknown error is retriable by default",
			err:       errors.New("unknown error"),
			message:   "failed to do something",
			wantRetry: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ClassifyLaunchError(tt.err, tt.message)

			if tt.err == nil {
				require.NoError(t, result)
				return
			}

			var launchErr *LaunchError
			require.True(t, errors.As(result, &launchErr), "expected LaunchError, got %T", result)
			assert.Equal(t, tt.wantRetry, launchErr.IsRetriable(), "retriable mismatch")
			assert.Contains(t, launchErr.Error(), tt.message, "message should be in error")
		})
	}
}

func TestIsRetriableLaunchError(t *testing.T) {
	tests := []struct {
		name      string
		err       error
		wantRetry bool
	}{
		{
			name:      "retriable LaunchError returns true",
			err:       RetriableLaunchError(errors.New("test")),
			wantRetry: true,
		},
		{
			name:      "non-retriable LaunchError returns false",
			err:       NonRetriableLaunchError(errors.New("test")),
			wantRetry: false,
		},
		{
			name:      "rate limit error returns true",
			err:       limiter.NewRateLimitError(sweagentd.ClientTarget{}, "rate limited", limiter.Rate{}),
			wantRetry: true,
		},
		{
			name:      "plain error returns false",
			err:       errors.New("plain error"),
			wantRetry: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := IsRetriableLaunchError(tt.err)
			assert.Equal(t, tt.wantRetry, result)
		})
	}
}
