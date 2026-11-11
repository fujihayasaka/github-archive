package limiter

import (
	"errors"
	"time"
)

// ErrActorExceededMaxQueuedJobs is returned when an actor has exceeded the
// maximum number of queued jobs allowed.
var ErrActorExceededMaxQueuedJobs = errors.New("actor has exceeded the maximum number of queued jobs")

// IsQueuedJobsExceededError reports whether err or any errors in the chain is a
// ErrActorExceededMaxQueuedJobs.
func IsQueuedJobsExceededError(err error) bool {
	return errors.Is(err, ErrActorExceededMaxQueuedJobs)
}

// RateLimitErrorResetBuffer is the additional buffer time added to the reset
// time for a RateLimitError to ensure that the rate limit has actually reset
// before retrying.
const RateLimitErrorResetBuffer = time.Second

// DefaultRateLimitErrorMessage is the default message for a RateLimitError when
// no message is provided.
const DefaultRateLimitErrorMessage = "rate limit exceeded"

// DefaultRateLimitErrorResetDuration is the default duration to wait before
// retrying when no reset time is provided.
const DefaultRateLimitErrorResetDuration = 3 * time.Second

// RateLimitError represents a primary rate limit error from GitHub.
//
// The primary rate limit is scoped to the installation, user, or IP address
// making the request. If the primary rate limit is exceeded, the caller should
// wait until the reset time before making additional requests.
//
// IMPORTANT: Callers should NOT block or sleep while waiting during this time,
// because this limit is scoped to a single installation or actor. Blocking
// would prevent work for other installations or actors from being processed
// during this time. Instead, callers should defer processing until the reset
// or return an error if deferred processing is not possible.
type RateLimitError struct {
	Target  string
	Message string
	Rate    Rate
}

// NewRateLimitError creates a new RateLimitError.
func NewRateLimitError(target string, message string, rate Rate) *RateLimitError {
	msg := DefaultRateLimitErrorMessage
	if message != "" {
		msg = message
	}

	return &RateLimitError{
		Target:  target,
		Message: msg,
		Rate:    rate,
	}
}

// Error implements the error interface.
func (e *RateLimitError) Error() string {
	return e.Message
}

// DurationUntilReset returns the duration until the rate limit resets. If the
// reset time is not set, it returns a default duration.
func (e *RateLimitError) DurationUntilReset() time.Duration {
	if !e.Rate.Reset.IsZero() && time.Now().Before(e.Rate.Reset) {
		return time.Until(e.Rate.Reset) + RateLimitErrorResetBuffer
	}
	return DefaultRateLimitErrorResetDuration
}

// AbuseRateLimitErrorResetBuffer is the additional buffer time added to the
// reset time for an AbuseRateLimitError to ensure that the rate limit has
// actually reset before retrying.
const AbuseRateLimitErrorResetBuffer = time.Second

// DefaultAbuseRateLimitErrorMessage is the default message for an
// AbuseRateLimitError when no message is provided.
const DefaultAbuseRateLimitErrorMessage = "secondary rate limit exceeded"

// DefaultAbuseRateLimitResetDuration is the default duration to wait before
// retrying when no reset time is provided.
const DefaultAbuseRateLimitResetDuration = 3 * time.Second

// AbuseRateLimitError represents a secondary rate limit error from GitHub.
//
// The secondary (or abuse) rate limit is a global limit that spans all
// installations and actors. If the secondary rate limit is exceeded, ALL
// callers should wait until the reset time before making additional requests.
//
// IMPORTANT: This limit is global and affects ALL installations and actors. If
// the secondary rate limit is exceeded, callers should wait until the reset time
// before making additional requests.
type AbuseRateLimitError struct {
	Message string
	Reset   time.Time
}

// NewAbuseRateLimitError creates a new AbuseRateLimitError.
// RetryAfter is provided with some abuse rate limit errors. If present,
// it is the amount of time that the client should wait before retrying.
// Otherwise, the client should try again later (after an unspecified amount of time).
func NewAbuseRateLimitError(message string, retryAfter time.Duration) *AbuseRateLimitError {
	msg := DefaultAbuseRateLimitErrorMessage
	if message != "" {
		msg = message
	}

	reset := time.Now().Add(retryAfter)

	return &AbuseRateLimitError{
		Message: msg,
		Reset:   reset,
	}
}

// Error implements the error interface.
func (e *AbuseRateLimitError) Error() string {
	return e.Message
}

// DurationUntilReset returns the duration until the rate limit resets. If the
// reset time is not set, it returns a default duration.
func (e *AbuseRateLimitError) DurationUntilReset() time.Duration {
	if !e.Reset.IsZero() && time.Now().Before(e.Reset) {
		return time.Until(e.Reset) + AbuseRateLimitErrorResetBuffer
	}
	return DefaultAbuseRateLimitResetDuration
}

// IsRateLimitError reports whether err or any errors in the chain is a
// RateLimitError.
func IsRateLimitError(err error) bool {
	var rateLimitErr *RateLimitError
	return errors.As(err, &rateLimitErr)
}

// IsAbuseRateLimitError reports whether err or any errors in the chain is an
// AbuseRateLimitError.
func IsAbuseRateLimitError(err error) bool {
	var abuseRateLimitErr *AbuseRateLimitError
	return errors.As(err, &abuseRateLimitErr)
}

// IsAnyRateLimitError reports whether err or any errors in the chain is a
// RateLimitError or an AbuseRateLimitError.
func IsAnyRateLimitError(err error) bool {
	return IsRateLimitError(err) || IsAbuseRateLimitError(err)
}

// IsAnyLimiterError reports whether err or any errors in the chain is a
// RateLimitError, an AbuseRateLimitError, or ErrActorExceededMaxQueuedJobs.
func IsAnyLimiterError(err error) bool {
	return IsAnyRateLimitError(err) || IsQueuedJobsExceededError(err)
}
