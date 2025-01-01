package middleware

import (
	"context"
	"crypto/sha256"
	"encoding/base64"

	apiConfig "github.com/github/authnd/internal/api/config"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"

	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twauth "github.com/github/go-twirp/v2/server/hooks/auth"
	twlog "github.com/github/go-twirp/v2/server/hooks/log"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"

	"github.com/github/otel-instrumentation-go/oteltwirp"
	tw "github.com/twitchtv/twirp"
)

func NewServerHooks(
	cfg *apiConfig.Config,
	logger log.Logger,
	statter stats.Client,
	hmacKeys ...string,
) *tw.ServerHooks {
	hooks := []*tw.ServerHooks{
		oteltwirp.NewServerHooks(),
		twhooks.TimingHooks(),
		updateStatterWithDefaultTags(),
		tw.ChainHooks(
			twlog.CustomTimingHooks(logger, twlog.DefaultFields, requestIDField),
			twstats.CustomResponseSentDurationHooks(statter, twstats.DefaultTags),
			twstats.CustomRequestDurationHooks(statter, twstats.DefaultTags),
			customRequestCountHooks(statter),
		),
	}

	if cfg.HMACAuthRequired() {
		logger.Info("hmac auth is enabled")

		var foundValidHMAC bool
		for _, key := range hmacKeys {
			if len(key) > 0 {
				foundValidHMAC = true
				break
			}
		}
		if !foundValidHMAC {
			panic("no valid hmac keys found")
		}

		// validate HMAC for inbound requests
		hooks = append(hooks, verifyRequestHMACHooks(hmacKeys...))
	} else {
		logger.Info("hmac auth is disabled")
	}

	hooks = append(hooks, errorReporterHook())

	return tw.ChainHooks(hooks...)
}

// customRequestCountHooks is a copy from twstats.CustomRequestCountHooks
// We customized this so that we could set the twirp_method dimension on the request_count,
// which isn't available before the RequestRouted life cycle hook is called.
func customRequestCountHooks(record stats.Client) *tw.ServerHooks {
	return &tw.ServerHooks{
		RequestRouted: func(ctx context.Context) (context.Context, error) {
			record.Counter(twhooks.RequestCountLabel, twstats.DefaultTags(ctx), 1)
			return ctx, nil
		},
	}
}

// requestIDField is a log.FieldsFunc helper function to log the request_id for
// incoming requests. This helper function is meant to be used with twirp's
// github.com/github/go-twirp/v2/server/hooks/log package
func requestIDField(ctx context.Context) []kvp.Field {
	return []kvp.Field{
		kvp.String("gh.request_id", requestid.GetGitHubRequestID(ctx)),
	}
}

// updateStatterWithDefaultTags updates the statter embedded in the context with the default tags
// added by the twirp server.  This merges any existing tags (e.g. applied by the DiagnosticHandler
// HTTP middleware) with the tags automatically applied by the twirp server.
func updateStatterWithDefaultTags() *tw.ServerHooks {
	return &tw.ServerHooks{
		RequestRouted: func(ctx context.Context) (context.Context, error) {
			nCtx := diagnostics.WithStatterTags(ctx, twstats.DefaultTags(ctx))
			return nCtx, nil
		},
	}
}

// verifyRequestHMACHooks verifies the HMAC in the authentication request header on incoming requests
// to the server based on the provided HMAC key(s).  Adds the hash of the HMAC key used for validating
// the request to the context.
func verifyRequestHMACHooks(hmacKeys ...string) *tw.ServerHooks {
	// compute the has of each provide hmac key to be used as the identifier in server metrics up the call stack.
	// this allows us to identify which HMAC key different services are using.
	keyHashes := make([]string, 0, len(hmacKeys))
	hashFn := sha256.New()
	for _, key := range hmacKeys {
		hash := hashFn.Sum([]byte(key))
		encodedHash := base64.StdEncoding.EncodeToString(hash)
		keyHashes = append(keyHashes, encodedHash[:20])
		hashFn.Reset()
	}

	return &tw.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			var nCtx context.Context
			var err error
			for ix, hmacKey := range hmacKeys {
				if len(hmacKey) < 1 {
					continue
				}

				nCtx, err = twauth.VerifyRequestHMACHooks(hmacKey).RequestReceived(ctx)
				if err == nil {
					nCtx = WithValidatingHMAC(nCtx, keyHashes[ix])
					return nCtx, nil
				}
			}
			return nCtx, err
		},
	}
}

// errorReportHook reports, logs and publishes internal errors we don't want to
// expose to the user.
func errorReporterHook() *tw.ServerHooks {
	return &tw.ServerHooks{
		Error: func(ctx context.Context, twerr tw.Error) context.Context {
			tags := stats.Tags{}

			if m, ok := tw.MethodName(ctx); ok {
				tags["http.request.method"] = m
			}
			if m, ok := tw.PackageName(ctx); ok {
				tags["http.request.package"] = m
			}
			if m, ok := tw.ServiceName(ctx); ok {
				tags["http.request.service"] = m
			}
			if m, ok := tw.StatusCode(ctx); ok {
				tags["http.response.status"] = m
			}

			if m := GetCatalogService(ctx); m != "" {
				tags["gh.request.calling_service"] = m
			}

			twirpErrorCode := twerr.Code()
			tags["http.request.error"] = string(twirpErrorCode)

			// we use a separate payload for the exception report to include
			// high cardinality information that we don't want to publish to
			// DataDog
			requestID := requestid.GetGitHubRequestID(ctx)
			payload := map[string]string{
				"gh.request_id": requestID,
			}
			for k, v := range tags {
				payload[k] = v
			}

			// always stat the twirp error
			diagnostics.Statter(ctx).Counter("server.unhandled.error", tags, 1)

			// conditionally report twirp errors based on the twirp error code
			if shouldReportError(twirpErrorCode) {
				diagnostics.ReportError(ctx, twerr, "authnd internal error", payload)
			}
			return ctx
		},
	}
}

// shouldReportError is used to determine if a twirp error should be reported
// based on the twirp error code
func shouldReportError(twirpErrorCode tw.ErrorCode) bool {
	switch twirpErrorCode {
	case tw.InvalidArgument:
		return false
	}
	return true
}
