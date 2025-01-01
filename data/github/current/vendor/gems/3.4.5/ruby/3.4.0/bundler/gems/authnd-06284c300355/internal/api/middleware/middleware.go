package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	reqmeta "github.com/github/go-reqmeta/v2"
	"github.com/justinas/alice"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
)

type catalogServiceKey struct{}

func GetCatalogService(ctx context.Context) string {
	if catalogService, ok := ctx.Value(catalogServiceKey{}).(string); ok {
		return catalogService
	}
	return ""
}

func WithCatalogService(ctx context.Context, catalogService string) context.Context {
	return context.WithValue(ctx, catalogServiceKey{}, catalogService)
}

// context key whose value is the hash of the hmac which was used for validating
// the incoming request to the server.
type validatingHMACKey struct{}

func GetValidatingHMAC(ctx context.Context) string {
	if hash, ok := ctx.Value(validatingHMACKey{}).(string); ok {
		return hash
	}
	return ""
}

func WithValidatingHMAC(ctx context.Context, hash string) context.Context {
	return context.WithValue(ctx, validatingHMACKey{}, hash)
}

func DiagnosticHandler(logger log.Logger, statter stats.Client) alice.Constructor {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
			ctx := r.Context()
			userAgent := r.Header.Get("User-Agent")
			catalogService := r.Header.Get("Catalog-Service")

			// Twirp requests _must_ have the User-Agent AND Catalog-Service headers
			if strings.HasPrefix(r.URL.Path, "/twirp/") && (catalogService == "" || userAgent == "") {
				rw.Header().Set("Content-Type", "text/plain")
				rw.WriteHeader(http.StatusBadRequest)

				// We honestly don't care about errors writing an error
				_, _ = rw.Write([]byte("both the 'Catalog-Service' and 'User-Agent' headers must be provided"))
				return
			}

			// add stat tags to request metadata so they get attached to metrics in twstats server hooks. we have to
			// initialize the request metadata here because the twirp server hooks happen after this HTTP middleware
			meta, ok := reqmeta.GetRequestMetadata(ctx)
			if !ok || meta == nil {
				meta = reqmeta.NewRequestMetadata()
			}

			// Put a logger in the context that has the request ID and other HTTP metadata in place
			fields := []kvp.Field{
				kvp.String("gh.request_id", requestid.GetGitHubRequestID(r.Context())),
				// Always add user agent to logs, unlike stats (see below).
				// Logs don't have the same concern about tags with lots of values.
				kvp.String("user_agent.original", userAgent),
				kvp.String("gh.request.calling_service", catalogService),
			}
			l := logger.WithFields(fields...)
			meta = reqmeta.LogWith(meta, fields...)

			// For stats, we don't arbitrarily add the user agent because it could have any value the client desires.
			// Stats tags with a large set of possible values costs $$$.
			// We only add it to the metrics if it's a "known" user-agent (one of our clients).
			// If it's "unknown", we use the string "unknown" in stats
			statsUserAgent := "unknown"
			if strings.HasPrefix(userAgent, "authnd-") {
				statsUserAgent = userAgent
			}

			// "validating_hmac" represents the metric label used for identifying which HMAC key was used for authenticating
			// the incoming request.  The value present in the metric is the hash of the key.
			tags := stats.Tags{
				"user_agent":      statsUserAgent,
				"catalog_service": catalogService,
				"validating_hmac": GetValidatingHMAC(r.Context()),
			}
			s := statter.WithTags(tags)
			meta = reqmeta.TagStatsWith(meta, tags)

			if r.Close {
				statter.Counter("http.connection.close", nil, 1)
			}

			// add logger, statter, and request metadata into the request context
			ctx = diagnostics.WithLogger(ctx, l)
			ctx = diagnostics.WithStatter(ctx, s)
			ctx = reqmeta.WithRequestMetadata(ctx, meta)
			ctx = WithCatalogService(ctx, catalogService)

			next.ServeHTTP(rw, r.WithContext(ctx))
		})
	}
}
