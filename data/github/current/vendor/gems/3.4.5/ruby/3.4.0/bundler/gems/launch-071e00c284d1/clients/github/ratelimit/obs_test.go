package ratelimit

import (
	"context"
	"net/http"
	"testing"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
)

func makeHttpResponse(statusCode int, headers map[string]string) *http.Response {
	res := &http.Response{
		StatusCode: statusCode,
		Header:     make(http.Header),
	}
	for k, v := range headers {
		res.Header.Set(k, v)
	}
	return res
}

func TestReportRateLimiting(t *testing.T) {
	opname := "test"

	tests := []struct {
		desc              string
		res               *http.Response
		scopedToCustomer  bool
		wantTelemetry     bool
		wantException     bool
		wantRateLimitType string
		wantTags          statter.Tags
	}{
		{
			desc: "logs customer scoped primary rate limiting",
			res: makeHttpResponse(http.StatusForbidden, map[string]string{
				"X-RateLimit-Limit":     "60",
				"X-RateLimit-Remaining": "0",
			}),
			scopedToCustomer:  true,
			wantTelemetry:     true,
			wantException:     false,
			wantRateLimitType: "primary",
			wantTags: statter.Tags{
				"operation":          opname,
				"scoped_to_customer": "true",
				"rate_limit_type":    "primary",
			},
		},
		{
			desc: "reports App-wide primary rate limiting",
			res: makeHttpResponse(http.StatusForbidden, map[string]string{
				"X-RateLimit-Limit":     "60",
				"X-RateLimit-Remaining": "0",
			}),
			scopedToCustomer:  false,
			wantTelemetry:     true,
			wantException:     true,
			wantRateLimitType: "primary",
			wantTags: statter.Tags{
				"operation":          opname,
				"scoped_to_customer": "false",
				"rate_limit_type":    "primary",
			},
		},
		{
			desc: "logs customer scoped secondary rate limiting",
			res: makeHttpResponse(http.StatusForbidden, map[string]string{
				"Retry-After": "1",
			}),
			scopedToCustomer:  true,
			wantTelemetry:     true,
			wantException:     false,
			wantRateLimitType: "secondary",
			wantTags: statter.Tags{
				"operation":          opname,
				"scoped_to_customer": "true",
				"rate_limit_type":    "secondary",
			},
		},
		{
			desc: "reports App-wide secondary rate limiting",
			res: makeHttpResponse(http.StatusForbidden, map[string]string{
				"Retry-After": "1",
			}),
			scopedToCustomer:  false,
			wantTelemetry:     true,
			wantException:     true,
			wantRateLimitType: "secondary",
			wantTags: statter.Tags{
				"operation":          opname,
				"scoped_to_customer": "false",
				"rate_limit_type":    "secondary",
			},
		},
		{
			desc: "does not report non-rate-limiting",
			res: makeHttpResponse(http.StatusForbidden, map[string]string{
				"X-RateLimit-Limit":     "60",
				"X-RateLimit-Remaining": "1",
			}),
			wantTelemetry: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			obs, log, stat := observability.NewMockedObservability()
			ctx := context.Background()

			if tt.wantTelemetry {
				stat.EXPECT().Counter(ctx, "github_rate_limit_exceeded", tt.wantTags, int64(1)).Once()

				if tt.wantException {
					log.EXPECT().Report(ctx, ErrorFromResponse(tt.res),
						kvp.String("gh.launch.rate_limit_type", tt.wantRateLimitType),
						kvp.String("gh.launch.operation.name", opname),
						kvp.Bool("gh.launch.scoped_to_customer", tt.scopedToCustomer),
					).Once()
				} else {
					log.EXPECT().Error(ctx, "GitHub rate limit exceeded",
						kvp.String("gh.launch.rate_limit_type", tt.wantRateLimitType),
						kvp.String("gh.launch.operation.name", opname),
						kvp.Bool("gh.launch.scoped_to_customer", tt.scopedToCustomer),
					).Once()
				}
			}

			ReportRateLimiting(ctx, obs, tt.res, opname, tt.scopedToCustomer)

			log.AssertExpectations(t)
			stat.AssertExpectations(t)
		})
	}
}
