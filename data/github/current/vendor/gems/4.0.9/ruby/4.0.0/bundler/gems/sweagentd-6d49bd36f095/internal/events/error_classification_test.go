package events

import (
	"errors"
	"net"
	"net/http"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/limiter"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
)

func TestClassifyError(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected string
	}{
		{
			name:     "nil error returns empty",
			err:      nil,
			expected: "",
		},
		{
			name:     "graphql resource limit error",
			err:      errors.New("Resource limits for this query exceeded"),
			expected: ErrorClassGraphQLResourceLimit,
		},
		{
			name:     "graphql resource limit wrapped",
			err:      errors.New("failed to get pull request context: Resource limits for this query exceeded"),
			expected: ErrorClassGraphQLResourceLimit,
		},
		{
			name:     "graphql primary rate limit",
			err:      newGraphQLRateLimitError(),
			expected: ErrorClassGraphQLRateLimit,
		},
		{
			name:     "graphql secondary rate limit (abuse)",
			err:      newAbuseRateLimitError(),
			expected: ErrorClassGraphQLRateLimit,
		},
		{
			name:     "REST rate limit",
			err:      newRESTRateLimitError(),
			expected: ErrorClassRateLimit,
		},
		{
			name:     "queued jobs exceeded",
			err:      limiter.ErrActorExceededMaxQueuedJobs,
			expected: ErrorClassRateLimit,
		},
		{
			name:     "job not found",
			err:      errors.New("failed to find job for workflow run"),
			expected: ErrorClassJobNotFound,
		},
		{
			name:     "no actionable comments",
			err:      errors.New("no actionable comments found to determine actor"),
			expected: ErrorClassNoActionableComments,
		},
		{
			name:     "github api transient 502",
			err:      newGitHubAPIError(502),
			expected: ErrorClassGitHubAPITransient,
		},
		{
			name:     "github api transient 503",
			err:      newGitHubAPIError(503),
			expected: ErrorClassGitHubAPITransient,
		},
		{
			name:     "github api transient 504",
			err:      newGitHubAPIError(504),
			expected: ErrorClassGitHubAPITransient,
		},
		{
			name:     "github api client 404",
			err:      newGitHubAPIError(404),
			expected: ErrorClassGitHubAPIClient,
		},
		{
			name:     "github api client 422",
			err:      newGitHubAPIError(422),
			expected: ErrorClassGitHubAPIClient,
		},
		{
			name:     "github api with network timeout",
			err:      newGitHubAPIErrorWithNetErr(&timeoutError{}),
			expected: ErrorClassGitHubAPITransient,
		},
		{
			name:     "github api with connection reset",
			err:      newGitHubAPIErrorWithNetErr(errors.New("read: connection reset by peer")),
			expected: ErrorClassGitHubAPITransient,
		},
		{
			name:     "bare network timeout error",
			err:      &timeoutError{},
			expected: ErrorClassGitHubAPITransient,
		},
		{
			name:     "builder finalized job error",
			err:      &jobservice.BuilderFinalizedJobError{Err: errors.New("rules violation")},
			expected: ErrorClassOther,
		},
		{
			name:     "unknown error",
			err:      errors.New("something unexpected happened"),
			expected: ErrorClassOther,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := classifyError(tt.err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestClassifyError_WrappedErrors(t *testing.T) {
	t.Run("wrapped graphql rate limit", func(t *testing.T) {
		inner := newGraphQLRateLimitError()
		assert.Equal(t, ErrorClassGraphQLRateLimit, classifyError(inner))
	})

	t.Run("wrapped github api error", func(t *testing.T) {
		apiErr := newGitHubAPIError(503)
		assert.Equal(t, ErrorClassGitHubAPITransient, classifyError(apiErr))
	})
}

// Helper functions to construct test errors

func newGraphQLRateLimitError() error {
	return &limiter.RateLimitError{
		Message: "API rate limit exceeded",
		Rate: limiter.Rate{
			Resource: "graphql",
			Reset:    time.Now().Add(time.Minute),
		},
	}
}

func newRESTRateLimitError() error {
	return &limiter.RateLimitError{
		Message: "API rate limit exceeded",
		Rate: limiter.Rate{
			Resource: "core",
			Reset:    time.Now().Add(time.Minute),
		},
	}
}

func newAbuseRateLimitError() error {
	return &limiter.AbuseRateLimitError{
		Message: "You have exceeded a secondary rate limit",
		Reset:   time.Now().Add(time.Minute),
	}
}

func newGitHubAPIError(statusCode int) *github.GitHubAPIError {
	resp := &gg.Response{
		Response: newHTTPResponse(statusCode),
	}
	return github.NewGitHubAPIError(resp, "test error", errors.New("api error"))
}

func newGitHubAPIErrorWithNetErr(err error) *github.GitHubAPIError {
	resp := &gg.Response{
		Response: newHTTPResponse(200),
	}
	return github.NewGitHubAPIError(resp, "test error", err)
}

// timeoutError implements net.Error with Timeout() returning true.
type timeoutError struct{}

func (e *timeoutError) Error() string   { return "i/o timeout" }
func (e *timeoutError) Timeout() bool   { return true }
func (e *timeoutError) Temporary() bool { return true }

var _ net.Error = &timeoutError{}

func newHTTPResponse(statusCode int) *http.Response {
	return &http.Response{
		StatusCode: statusCode,
		Header:     http.Header{},
	}
}
