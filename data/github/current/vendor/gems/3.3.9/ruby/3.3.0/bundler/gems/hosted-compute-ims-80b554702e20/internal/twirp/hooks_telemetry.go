package twirp

import (
	"context"
	"fmt"

	"github.com/github/go-stats"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/codes"
	"go.uber.org/zap/zapcore"
)

func statsReporterHook(statter stats.Client) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		ResponseSent: func(ctx context.Context) {
			statter.Counter("twirp.request.total", twstats.DefaultTags(ctx), 1)
		},
		Error: func(ctx context.Context, twerr twirp.Error) context.Context {
			if isUserError(twerr) {
				return ctx
			}
			statter.Counter("twirp.request.error", twstats.DefaultTags(ctx), 1)
			return ctx
		},
	}
}

func logReporterHook(logger *telemetry.ReportingLogger) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		Error: func(ctx context.Context, twerr twirp.Error) context.Context {
			if isUserError(twerr) {
				return ctx
			}
			fields := make([]zapcore.Field, 0)
			for key, value := range twstats.DefaultTags(ctx) {
				fields = append(fields, zapcore.Field{Key: key, Type: zapcore.StringType, String: value})
			}

			logger.ErrorWithReport("request failed", twerr, fields...)
			return ctx
		},
	}
}

func tracerIntercepter(telem *telemetry.Telemetry) twirp.Interceptor {
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

			spanCtx, span := telem.Tracer.Tracer.Start(ctx, fmt.Sprintf("%s.%s", packageName, method))
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
