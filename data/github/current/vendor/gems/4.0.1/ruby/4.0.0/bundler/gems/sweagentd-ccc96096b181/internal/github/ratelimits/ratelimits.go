// Package ratelimits provides a custom RoundTripper that works with the limiter
// package to handle rate limits for GitHub API requests.
package ratelimits

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

const (
	headerRateLimit     = "X-Ratelimit-Limit"
	headerRateRemaining = "X-Ratelimit-Remaining"
	headerRateUsed      = "X-Ratelimit-Used"
	headerRateReset     = "X-Ratelimit-Reset"
	headerRateResource  = "X-Ratelimit-Resource"

	headerRetryAfter = "Retry-After"
)

// RoundTripper wraps an HTTP RoundTripper to track and update rate limits.
type RoundTripper struct {
	base    http.RoundTripper
	limiter limiter.RateLimiter
	target  sweagentd.ClientTarget
}

// NewRoundTripper creates a new RoundTripper with the given base transport.
func NewRoundTripper(base http.RoundTripper, limiter limiter.RateLimiter, target sweagentd.ClientTarget) *RoundTripper {
	if base == nil {
		base = http.DefaultTransport
	}
	return &RoundTripper{
		base:    base,
		limiter: limiter,
		target:  target,
	}
}

// RoundTrip implements the http.RoundTripper interface.
func (rt *RoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	category := uint8(gg.GetRateLimitCategory(req.Method, req.URL.Path))

	resp, err := rt.base.RoundTrip(req)
	if err != nil {
		return resp, err
	}

	// Don't update the rate limits if this was a cached response.
	if resp.Header.Get("X-From-Cache") != "" {
		return resp, nil
	}

	if rt.limiter == nil {
		return resp, nil
	}

	// If the response is successful, parse the rate limit headers ourselves
	// and avoid the overhead of [gg.CheckResponse], which reads the body.
	// The secondary rate limits are only provided in the response headers for
	// secondary rate limit errors, so we don't need to parse them here.
	if c := resp.StatusCode; 200 <= c && c <= 299 {
		if rt.target.Type != sweagentd.ClientTargetTypeApp {
			rate := parseRate(resp)
			rt.limiter.SetRate(req.Context(), rt.target, category, rate)
		}
		return resp, nil
	}

	// Use [gg.CheckResponse] to check for and parse errors, then update the
	// limiter if necessary. We do this because it handles checking for specific
	// items in the response body, such as documentation links and error messages.
	err = gg.CheckResponse(resp)
	if err != nil {
		// but we only care about rate limit errors.
		var primaryRateLimitErr *gg.RateLimitError
		var secondaryRateLimitErr *gg.AbuseRateLimitError
		switch {
		case errors.As(err, &primaryRateLimitErr): // installation user limit
			// TODO (colbylwilliams): Should we do this?
			if rt.target.Type != sweagentd.ClientTargetTypeApp {
				rate := ToLimiterRate(primaryRateLimitErr.Rate)
				rt.limiter.SetRate(req.Context(), rt.target, category, rate)
			}
		case errors.As(err, &secondaryRateLimitErr): // global rate limit
			retryAfter := secondaryRateLimitErr.GetRetryAfter()
			if retryAfter != 0 {
				retry := time.Now().Add(retryAfter)
				rt.limiter.SetSecondaryRateLimitReset(req.Context(), rt.target.App, retry)
			}
		default:
			// Other error types are ignored
		}
		// don't return the error, allow the downstream client to handle it.
	}

	return resp, nil
}

// parseRate parses the rate limit related headers.
//
// https://github.com/google/go-github/blob/69dc04b020795fda00434d98b5ee3d50baa4c43c/github/github.go#L769-L790
func parseRate(r *http.Response) limiter.Rate {
	var rate limiter.Rate
	if limit := r.Header.Get(headerRateLimit); limit != "" {
		rate.Limit, _ = strconv.Atoi(limit)
	}
	if remaining := r.Header.Get(headerRateRemaining); remaining != "" {
		rate.Remaining, _ = strconv.Atoi(remaining)
	}
	if used := r.Header.Get(headerRateUsed); used != "" {
		rate.Used, _ = strconv.Atoi(used)
	}
	if reset := r.Header.Get(headerRateReset); reset != "" {
		if v, _ := strconv.ParseInt(reset, 10, 64); v != 0 {
			rate.Reset = time.Unix(v, 0)
		}
	}
	if resource := r.Header.Get(headerRateResource); resource != "" {
		rate.Resource = resource
	}
	return rate
}

// parseSecondaryRate parses the secondary rate limit related headers,
// and returns the time to retry after.
//
// https://github.com/google/go-github/blob/69dc04b020795fda00434d98b5ee3d50baa4c43c/github/github.go#L792-L814
//
// Note: Unused now, but will be used when graphql support is added.
func parseSecondaryRate(r *http.Response) *time.Duration {
	// According to GitHub support, the "Retry-After" header value will be
	// an integer which represents the number of seconds that one should
	// wait before resuming making requests.
	if v := r.Header.Get(headerRetryAfter); v != "" {
		retryAfterSeconds, _ := strconv.ParseInt(v, 10, 64) // Error handling is noop.
		retryAfter := time.Duration(retryAfterSeconds) * time.Second
		return &retryAfter
	}

	// According to GitHub support, endpoints might return x-ratelimit-reset instead,
	// as an integer which represents the number of seconds since epoch UTC,
	// representing the time to resume making requests.
	if v := r.Header.Get(headerRateReset); v != "" {
		secondsSinceEpoch, _ := strconv.ParseInt(v, 10, 64) // Error handling is noop.
		retryAfter := time.Until(time.Unix(secondsSinceEpoch, 0))
		return &retryAfter
	}

	return nil
}

// ToLimiterRate converts a [gg.Rate] to a [limiter.Rate].
func ToLimiterRate(rate gg.Rate) limiter.Rate {
	return limiter.Rate{
		Limit:     rate.Limit,
		Remaining: rate.Remaining,
		Used:      rate.Used,
		Reset:     rate.Reset.Time,
		Resource:  rate.Resource,
	}
}

// ToLimiterRates converts a [gg.RateLimits] object to a [limiter.Rate] map.
func ToLimiterRates(rates *gg.RateLimits) map[uint8]limiter.Rate {
	result := make(map[uint8]limiter.Rate)

	if rates.Core != nil {
		result[uint8(gg.CoreCategory)] = ToLimiterRate(*rates.Core)
	}
	if rates.Search != nil {
		result[uint8(gg.SearchCategory)] = ToLimiterRate(*rates.Search)
	}
	if rates.GraphQL != nil {
		result[uint8(gg.GraphqlCategory)] = ToLimiterRate(*rates.GraphQL)
	}
	if rates.IntegrationManifest != nil {
		result[uint8(gg.IntegrationManifestCategory)] = ToLimiterRate(*rates.IntegrationManifest)
	}
	if rates.SourceImport != nil {
		result[uint8(gg.SourceImportCategory)] = ToLimiterRate(*rates.SourceImport)
	}
	if rates.CodeScanningUpload != nil {
		result[uint8(gg.CodeScanningUploadCategory)] = ToLimiterRate(*rates.CodeScanningUpload)
	}
	if rates.ActionsRunnerRegistration != nil {
		result[uint8(gg.ActionsRunnerRegistrationCategory)] = ToLimiterRate(*rates.ActionsRunnerRegistration)
	}
	if rates.SCIM != nil {
		result[uint8(gg.ScimCategory)] = ToLimiterRate(*rates.SCIM)
	}
	if rates.DependencySnapshots != nil {
		result[uint8(gg.DependencySnapshotsCategory)] = ToLimiterRate(*rates.DependencySnapshots)
	}
	if rates.CodeSearch != nil {
		result[uint8(gg.CodeSearchCategory)] = ToLimiterRate(*rates.CodeSearch)
	}
	if rates.AuditLog != nil {
		result[uint8(gg.AuditLogCategory)] = ToLimiterRate(*rates.AuditLog)
	}
	return result
}
