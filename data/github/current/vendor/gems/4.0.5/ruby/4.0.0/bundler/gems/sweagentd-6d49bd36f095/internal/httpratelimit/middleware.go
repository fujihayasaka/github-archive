// Package httpratelimit provides HTTP rate limiting middleware using
// go-ratelimit's sliding window algorithm backed by cache.Store.
//
// Activation is gated by feature flags.
// Two middleware variants are provided:
//   - Middleware: per-user budgets keyed by user ID. Cache key format: "http_rl:<user_id>:<window_timestamp>".
//   - JobMiddleware: per-job budgets keyed by job ID (from chi URL param). Cache key format: "http_rl:<job_id>:<window_timestamp>".
package httpratelimit

import (
	"context"
	"net/http"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	ratelimiter "github.com/github/go-ratelimit"
	rlstore "github.com/github/go-ratelimit/store"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	chi "github.com/go-chi/chi/v5"
)

const (
	defaultRequestsPerMinute = 600
	rateLimitKeyPrefix       = "http_rl"
)

// RateLimiter provides per-user HTTP request rate limiting as chi middleware.
type RateLimiter struct {
	requestsPerMinute int
	limiter           *ratelimiter.SimpleLimiter
	obsv              observability.Exporters
	ffClient          featureflags.Client
}

// New creates a RateLimiter. Values of requestsPerMinute <= 0 default to 600.
func New(requestsPerMinute int, cacheStore cache.Store, obsv observability.Exporters, ffClient featureflags.Client) *RateLimiter {
	if requestsPerMinute <= 0 {
		requestsPerMinute = defaultRequestsPerMinute
	}

	store := newStoreAdapter(cacheStore)
	limit := ratelimiter.RateLimit{
		Max:    int64(requestsPerMinute),
		Window: time.Minute,
	}

	limiter := ratelimiter.NewSimpleLimiter(
		rateLimitKeyPrefix,
		limit,
		store,
		time.Now,
		obsv.Statter,
		obsv.Logger,
	)

	return &RateLimiter{
		requestsPerMinute: requestsPerMinute,
		limiter:           limiter,
		obsv:              obsv,
		ffClient:          ffClient,
	}
}

// Middleware returns chi middleware that enforces per-user rate limits.
// Fails open on cache errors.
func (rl *RateLimiter) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		logger := rl.obsv.LoggerWithRequestTelemetry(ctx, r)

		user, ok := requestctx.User(ctx)
		if !ok {
			next.ServeHTTP(w, r)
			return
		}

		if !rl.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentHTTPRateLimit, int64(user.ID)) {
			next.ServeHTTP(w, r)
			return
		}

		key := strconv.FormatUint(user.ID, 10)

		retryAfter, err := rl.limiter.CheckLimit(ctx, key)
		if err != nil {
			logger.WithFields(
				kvp.String("rate_limit_key", key),
			).WithError(err).Warn("rate limit check failed, failing open")
			rl.obsv.Increment(ctx, "http_rate_limit.error", stats.Tags{
				"path": r.URL.Path,
			})
			next.ServeHTTP(w, r)
			return
		}

		rl.obsv.Increment(ctx, "http_rate_limit.checked", stats.Tags{
			"path": r.URL.Path,
		})

		if retryAfter > 0 {
			logger.WithFields(
				kvp.String("rate_limit_key", key),
				kvp.String("retry_after", retryAfter.String()),
			).Warn("HTTP rate limit exceeded")
			rl.obsv.Increment(ctx, "http_rate_limit.limited", stats.Tags{
				"path": r.URL.Path,
			})

			retrySeconds := int64(retryAfter.Seconds()) + 1
			w.Header().Set("Retry-After", strconv.FormatInt(retrySeconds, 10))
			w.Header().Set("X-RateLimit-Limit", strconv.Itoa(rl.requestsPerMinute))
			http.Error(w, http.StatusText(http.StatusTooManyRequests), http.StatusTooManyRequests)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// JobMiddleware returns chi middleware that enforces per-job rate limits.
// Expects a {jobID} URL parameter set by the chi router. Fails open on cache
// errors or if the job ID is missing.
func (rl *RateLimiter) JobMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		logger := rl.obsv.LoggerWithRequestTelemetry(ctx, r)

		// TODO: remove user lookup once we promote FF bellow
		user, ok := requestctx.User(ctx)
		if !ok {
			next.ServeHTTP(w, r)
			return
		}

		if !rl.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentHTTPTokensRateLimit, int64(user.ID)) {
			next.ServeHTTP(w, r)
			return
		}

		jobID := chi.URLParam(r, "jobID")
		if jobID == "" {
			next.ServeHTTP(w, r)
			return
		}

		retryAfter, err := rl.limiter.CheckLimit(ctx, jobID)
		if err != nil {
			logger.WithFields(
				kvp.String("rate_limit_key", jobID),
			).WithError(err).Warn("rate limit check failed, failing open")
			rl.obsv.Increment(ctx, "http_rate_limit.error", stats.Tags{
				"path": r.URL.Path,
			})
			next.ServeHTTP(w, r)
			return
		}

		rl.obsv.Increment(ctx, "http_rate_limit.checked", stats.Tags{
			"path": r.URL.Path,
		})

		if retryAfter > 0 {
			logger.WithFields(
				kvp.String("rate_limit_key", jobID),
				kvp.String("retry_after", retryAfter.String()),
			).Warn("HTTP rate limit exceeded")
			rl.obsv.Increment(ctx, "http_rate_limit.limited", stats.Tags{
				"path": r.URL.Path,
			})

			retrySeconds := int64(retryAfter.Seconds()) + 1
			w.Header().Set("Retry-After", strconv.FormatInt(retrySeconds, 10))
			w.Header().Set("X-RateLimit-Limit", strconv.Itoa(rl.requestsPerMinute))
			http.Error(w, http.StatusText(http.StatusTooManyRequests), http.StatusTooManyRequests)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// storeAdapter bridges cache.Store to go-ratelimit's store.Store.
// Both Incr and Get are best-effort so the middleware fails open.
type storeAdapter struct {
	cache cache.Store
}

func newStoreAdapter(c cache.Store) rlstore.Store {
	return &storeAdapter{cache: c}
}

func (a *storeAdapter) Incr(ctx context.Context, kvs []rlstore.KeysValue) error {
	for _, kv := range kvs {
		for _, ke := range kv.Keys {
			// Fallback TTL: sliding window needs ≥2× window duration.
			ttl := ke.Exp
			if ttl <= 0 {
				ttl = 2 * time.Minute
			}
			// Best-effort: skip failures to stay consistent with Get.
			a.cache.Incr(ke.Key, kv.Value, ttl)
		}
	}
	return nil
}

func (a *storeAdapter) Get(ctx context.Context, keys []string) ([]int64, error) {
	vals := make([]int64, len(keys))
	if len(keys) == 0 {
		return vals, nil
	}
	rawVals, _ := a.cache.GetMultiple(keys)
	for i, key := range keys {
		raw, ok := rawVals[key]
		if !ok {
			continue
		}
		v, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			continue
		}
		vals[i] = v
	}
	return vals, nil
}
