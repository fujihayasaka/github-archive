package twirp

import (
	"context"
	"fmt"
	"net/http"
	"slices"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/requestid"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twlog "github.com/github/go-twirp/v2/server/hooks/log"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
	"github.com/github/hosted-compute-ims/internal/telemetry/tracer"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/codes"
)

const (
	HeaderXCorrelationID = "X-Correlation-Id"
	HeaderXClientID      = "X-Client-Id"
)

func requestStatterHook() *twirp.ServerHooks {
	return &twirp.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			statter.Increment(ctx, twhooks.RequestCountLabel)
			return ctx, nil
		},
		RequestRouted: func(ctx context.Context) (context.Context, error) {
			statter.DistributionMs(ctx, twhooks.RequestRoutedDurationLabel, twhooks.RoutingDuration(ctx))
			return ctx, nil
		},
		ResponsePrepared: func(ctx context.Context) context.Context {
			statter.DistributionMs(ctx, twhooks.ResponsePreparedDurationLabel, twhooks.ResponsePreparationDuration(ctx))
			return ctx
		},
		ResponseSent: func(ctx context.Context) {
			statter.Increment(ctx, "twirp.request.total")
			statter.DistributionMs(ctx, twhooks.ResponseSentDurationLabel, twhooks.ResponseSendingDuration(ctx))
			statter.DistributionMs(ctx, twhooks.RequestDurationLabel, twhooks.RequestDuration(ctx))
		},
		Error: func(ctx context.Context, twerr twirp.Error) context.Context {
			if !isUserError(twerr) {
				statter.Increment(ctx, "twirp.request.error")
			}
			return ctx
		},
	}
}

func requestLoggerHook() *twirp.ServerHooks {
	return &twirp.ServerHooks{
		ResponseSent: func(ctx context.Context) {
			logger.Info(ctx, "request finished", kvp.Duration(twhooks.RequestDurationLabel, twhooks.RequestDuration(ctx)))
		},
		Error: func(ctx context.Context, twerr twirp.Error) context.Context {
			// user errors are only reported to Splunk
			// server errors are reported to Splunk and Sentry
			if isUserError(twerr) {
				logger.WithError(twerr).Error(ctx, "request failed")
			} else {
				logger.ErrorWithReport(ctx, "request failed", twerr)
			}

			return ctx
		},
	}
}

func requestTwirpMetadataHook() *twirp.ServerHooks {
	return &twirp.ServerHooks{
		RequestRouted: func(ctx context.Context) (context.Context, error) {
			twirpLoggingFields := twlog.DefaultFields(ctx)
			// exclude the request_id from the log fields because it is already tracked by requestMetadataHandler
			twirpLoggingFields = slices.DeleteFunc(twirpLoggingFields, func(field kvp.Field) bool { return field.Key == requestid.GitHubRequestIDLabel })

			twirpStatterTags := twstats.DefaultTags(ctx)
			twirpStatterFields := stash.MapToKvpFields(twirpStatterTags)

			ctx = stash.WithLoggingFields(ctx, twirpLoggingFields...)
			ctx = stash.WithStatterFields(ctx, twirpStatterFields...)

			return ctx, nil
		},
	}
}

func requestMetadataHandler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID := r.Header.Get(headers.GitHubRequestID)
		correlationID := r.Header.Get(HeaderXCorrelationID)
		if requestID == "" {
			// all requests from other GitHub services should have the X-GitHub-Request-ID header
			// Runner service sets the X-Correlation-Id header instead
			// If both headers are not set, generate a new request ID to correlate all logs related to specific request
			if correlationID != "" {
				requestID = correlationID
			} else {
				requestID = requestid.NewGitHubRequestID()
			}
		}

		fields := []kvp.Field{
			kvp.String(requestid.GitHubRequestIDLabel, requestID),
		}
		if correlationID != "" {
			fields = append(fields, kvp.String("header.x_correlation_id", correlationID))
		}
		if clientID := r.Header.Get(HeaderXClientID); clientID != "" {
			fields = append(fields, kvp.String("header.x_client_id", clientID))
		}
		if tenant := r.Header.Get(headers.Tenant); tenant != "" {
			fields = append(fields, kvp.String("header.x_github_tenant", tenant))
		}
		if tenantID := r.Header.Get(headers.TenantID); tenantID != "" {
			fields = append(fields, kvp.String("header.x_github_tenant_id", tenantID))
		}

		r = r.WithContext(
			stash.WithLoggingFields(r.Context(), fields...),
		)

		next.ServeHTTP(w, r)
	})
}

func requestTracerIntercepter() twirp.Interceptor {
	return func(next twirp.Method) twirp.Method {
		return func(ctx context.Context, req interface{}) (interface{}, error) {
			packageName, ok := twirp.PackageName(ctx)
			if !ok {
				packageName = "unknown"
			}

			method, ok := twirp.MethodName(ctx)
			if !ok {
				method = "unknown"
			}

			spanCtx, span := tracer.StartSpan(ctx, fmt.Sprintf("%s.%s", packageName, method))
			defer span.End()

			res, err := next(spanCtx, req)
			if err != nil {
				span.SetStatus(codes.Error, err.Error())
			}

			return res, err
		}
	}
}

// skip reporting user-caused errors as server errors
func isUserError(twerr twirp.Error) bool {
	switch twerr.Code() {
	case twirp.AlreadyExists, twirp.InvalidArgument, twirp.ResourceExhausted, twirp.NotFound, twirp.Unauthenticated:
		return true
	default:
		return false
	}
}
