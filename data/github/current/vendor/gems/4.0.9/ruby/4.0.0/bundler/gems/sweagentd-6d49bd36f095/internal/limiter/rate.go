package limiter

import (
	"time"
)

// Rate represents the rate limit information from the GitHub API.
type Rate struct {
	// The maximum number of requests that you can make per hour.
	Limit int `json:"limit"`

	// The number of requests remaining in the current rate limit window.
	Remaining int `json:"remaining"`

	// The number of requests you have made in the current rate limit window.
	Used int `json:"used"`

	// The time at which the current rate limit window resets, in UTC epoch seconds.
	Reset time.Time `json:"reset"`

	// The rate limit resource that the request counted against.
	// For more information about the different resources, see REST API endpoints for rate limits.
	// GitHub API docs: https://docs.github.com/en/rest/rate-limit/rate-limit#get-rate-limit-status-for-the-authenticated-user
	Resource string `json:"resource,omitempty"`
}

// IsLimited checks if the rate limit is currently exceeded.
// If the rate limit is exceeded, it returns the duration until the limit resets and true.
// If the rate limit is not exceeded, it returns 0 and false.
func (r *Rate) IsLimited() (time.Duration, bool) {
	if !r.Reset.IsZero() && r.Remaining == 0 && time.Now().Before(r.Reset) {
		return time.Until(r.Reset), true
	}
	return 0, false
}

// Category returns the category code for the rate limit resource.
// Unknown resources (including "core" and empty string) are treated as category 0.
func (r *Rate) Category() uint8 {
	switch r.Resource {
	case "search":
		return 1
	case "graphql":
		return 2
	case "integration_manifest":
		return 3
	case "source_import":
		return 4
	case "code_scanning_upload":
		return 5
	case "actions_runner_registration":
		return 6
	case "scim":
		return 7
	case "dependency_snapshots":
		return 8
	case "code_search":
		return 9
	default:
		// "core", "", and unknown resources default to category 0
		return 0
	}
}
