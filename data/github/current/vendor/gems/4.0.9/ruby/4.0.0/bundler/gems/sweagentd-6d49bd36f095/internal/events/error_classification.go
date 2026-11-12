package events

import (
	"errors"
	"net"
	"strings"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/limiter"
)

// Error class constants for the error_class metric tag.
// These are low-cardinality values used to categorize errors
// on the events.handler_duration_ms metric for SLO attribution.
const (
	ErrorClassGraphQLResourceLimit = "graphql_resource_limit"
	ErrorClassGraphQLRateLimit     = "graphql_rate_limit"
	ErrorClassRateLimit            = "rate_limit"
	ErrorClassJobNotFound          = "job_not_found"
	ErrorClassNoActionableComments = "no_actionable_comments"
	ErrorClassGitHubAPITransient   = "github_api_transient"
	ErrorClassGitHubAPIClient      = "github_api_client"
	ErrorClassOther                = "other"
)

// classifyError returns a low-cardinality error class string for metric tagging.
// Only called when outcome == "error" to keep tag cardinality bounded.
func classifyError(err error) string {
	if err == nil {
		return ""
	}

	// GraphQL resource limit ("Resource limits for this query exceeded")
	if github.IsResourceLimitError(err) {
		return ErrorClassGraphQLResourceLimit
	}

	// GraphQL rate limits (primary or secondary) — distinguished from REST
	// rate limits by the Rate.Resource field set to "graphql".
	var rateLimitErr *limiter.RateLimitError
	if errors.As(err, &rateLimitErr) {
		if rateLimitErr.Rate.Resource == "graphql" {
			return ErrorClassGraphQLRateLimit
		}
		return ErrorClassRateLimit
	}
	var abuseRateLimitErr *limiter.AbuseRateLimitError
	if errors.As(err, &abuseRateLimitErr) {
		return ErrorClassGraphQLRateLimit
	}

	// Queued jobs exceeded (a limiter error but not a rate limit)
	if limiter.IsQueuedJobsExceededError(err) {
		return ErrorClassRateLimit
	}

	// Builder already finalized the job (rules violation, model unavailable, etc.)
	// These are terminal states that don't represent system failures.
	if jobservice.IsBuilderFinalizedJobError(err) {
		return ErrorClassOther
	}

	// Job not found for workflow run
	if strings.Contains(err.Error(), "failed to find job for workflow run") {
		return ErrorClassJobNotFound
	}

	// No actionable comments found
	if strings.Contains(err.Error(), "no actionable comments found") {
		return ErrorClassNoActionableComments
	}

	// GitHub API errors — split transient (5xx/network) vs client (4xx)
	var apiErr *github.GitHubAPIError
	if errors.As(err, &apiErr) {
		if isTransientStatusCode(apiErr.StatusCode()) || isTransientNetworkErr(apiErr.Unwrap()) {
			return ErrorClassGitHubAPITransient
		}
		return ErrorClassGitHubAPIClient
	}

	// Check for transient network errors not wrapped in GitHubAPIError
	if isTransientNetworkErr(err) {
		return ErrorClassGitHubAPITransient
	}

	return ErrorClassOther
}

// isTransientStatusCode returns true for HTTP status codes that indicate
// transient server-side failures.
func isTransientStatusCode(code int) bool {
	return code == 502 || code == 503 || code == 504
}

// isTransientNetworkErr checks for network-level transient failures such as
// timeouts, connection resets, and DNS errors.
func isTransientNetworkErr(err error) bool {
	if err == nil {
		return false
	}

	// Check for net.Error (timeouts, etc.)
	var netErr net.Error
	if errors.As(err, &netErr) {
		return true
	}

	msg := err.Error()
	return strings.Contains(msg, "connection reset") ||
		strings.Contains(msg, "connection refused") ||
		strings.Contains(msg, "i/o timeout") ||
		strings.Contains(msg, "context deadline exceeded")
}
