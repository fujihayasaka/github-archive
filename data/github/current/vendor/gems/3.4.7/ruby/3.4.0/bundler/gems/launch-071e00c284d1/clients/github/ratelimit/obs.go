package ratelimit

import (
	"context"
	"net/http"
	"strconv"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
)

// ReportRateLimiting reports a GitHub rate limit exceeded error to DataDog and Sentry.
// Pass false for scopedToCustomer when secondary rate limiting will apply to the Actions App as a whole (or App + client IP address), regardless of customer / installation.
func ReportRateLimiting(ctx context.Context, obs *observability.Observability, res *http.Response, opname string, scopedToCustomer bool) {
	ok, rltype := rateLimitedWithType(res.StatusCode, res.Header)
	if !ok {
		return
	}

	obs.Counter(ctx, "github_rate_limit_exceeded", statter.Tags{
		"operation":          opname,
		"scoped_to_customer": strconv.FormatBool(scopedToCustomer),
		"rate_limit_type":    string(rltype),
	}, 1)

	fields := []kvp.Field{
		kvp.String("gh.launch.rate_limit_type", string(rltype)),
		kvp.String("gh.launch.operation.name", opname),
		kvp.Bool("gh.launch.scoped_to_customer", scopedToCustomer),
	}

	body, err := readBodyRepeatable(res)
	if err != nil && body != nil {
		fields = append(fields, kvp.String("http.response.body", string(body)))
	}

	if scopedToCustomer {
		obs.Error(ctx, ErrorFromResponse(res).Error(), fields...)
	} else {
		obs.Report(ctx, ErrorFromResponse(res), fields...)
	}
}
