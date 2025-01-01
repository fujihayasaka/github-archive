package ratelimit

import (
	"context"
	"net/http"

	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

// ResponseValidator returns a ResponseValidator function that checks for GitHub rate limit responses.
// If a rate limit response is detected, the function returns an error that implements the RateLimited interface.
// If a rate limit response isn't detected, the next ResponseValidator in the chain is called, if supplied.
func ResponseValidator(ctx context.Context, obs *observability.Observability, opname string, scopedToCustomer bool, next httpclient.ResponseValidator) httpclient.ResponseValidator {
	return func(r *http.Response) (bool, error) {
		if !RateLimited(r.StatusCode, r.Header) {
			if next != nil {
				return next(r)
			}
			return false, nil
		}

		ReportRateLimiting(ctx, obs, r, opname, scopedToCustomer)
		return false, ErrorFromResponse(r)
	}
}
