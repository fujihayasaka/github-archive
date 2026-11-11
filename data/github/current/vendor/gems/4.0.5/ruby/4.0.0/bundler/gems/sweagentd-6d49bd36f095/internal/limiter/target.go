package limiter

import (
	"time"

	"github.com/github/sweagentd/internal/sweagentd"
)

// NewTargetRateLimitError creates a new RateLimitError for the Target with the given
// message and rate.
func NewTargetRateLimitError(target sweagentd.ClientTarget, message string, rate Rate) error {
	return NewRateLimitError(target, message, rate)
}

// NewTargetAbuseRateLimitError creates a new AbuseRateLimitError for the Target with the
// given message and retry duration.
func NewTargetAbuseRateLimitError(target sweagentd.ClientTarget, message string, retryAfter time.Duration) error {
	return NewAbuseRateLimitError(target, message, retryAfter)
}
