package aqueduct

import (
	"time"

	"github.com/github/sweagentd/internal/cache"
)

// ClientOption configures an Aqueduct client.
type ClientOption func(*Client)

// WithAqueductURL sets the Aqueduct URL for the client.
func WithAqueductURL(url string) ClientOption {
	return func(a *Client) {
		a.aqueductURL = url
	}
}

// WithAPIKey sets the API key for the client.
func WithAPIKey(apiKey string) ClientOption {
	return func(a *Client) {
		a.apiKey = apiKey
	}
}

// WithAPIKeyVersion sets the API key version for the client.
func WithAPIKeyVersion(version int) ClientOption {
	return func(a *Client) {
		a.apiKeyVersion = version
	}
}

// defaultRedeliveryDelaySeconds is the default delay in seconds for requeued jobs.
const defaultRedeliveryDelaySeconds int = 5

// WithDefaultRedeliveryDelay sets the default redelivery delay in seconds for jobs
// that are requeued.
//   - If not set, it defaults to 5 seconds.
//   - If set to 0, no delay is applied.
//   - If set to a negative value, it will use the default delay.
func WithDefaultRedeliveryDelay(seconds int) ClientOption {
	return func(a *Client) {
		if seconds < 0 {
			seconds = defaultRedeliveryDelaySeconds
		}
		a.defaultRedeliveryDelaySeconds = seconds
	}
}

// WithQueueDepthCache enables caching of `QueueDepth` lookups against the
// supplied cache store with the given TTL. Recommended for any call site that
// reads queue depth on a regular cadence (e.g. a scheduler tick) — bounds
// Twirp load on Aqueduct independent of tick frequency. Pass a zero or
// negative TTL to disable caching (the default).
func WithQueueDepthCache(store cache.Store, ttl time.Duration) ClientOption {
	return func(a *Client) {
		if ttl <= 0 {
			return
		}
		a.queueDepthCache = store
		a.queueDepthCacheTTL = ttl
	}
}
