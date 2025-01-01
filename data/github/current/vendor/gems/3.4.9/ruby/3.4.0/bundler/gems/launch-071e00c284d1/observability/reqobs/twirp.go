package reqobs

import (
	"context"
	"strconv"
	"time"

	"github.com/twitchtv/twirp"

	"github.com/github/launch/observability/statter"
)

const unavail = "unavail"

func NewTwirpMetricsHooks(client statter.Statter) *TwirpHooks {
	return &TwirpHooks{
		OnBeginRPC: func(ctx context.Context, pkgname, svcname, opname string) {
			tags := buildOnBeginRPCTags("twirp", svcname, pkgname, opname)
			emitOnAttemptCounter(ctx, client, tags)
		},
		OnEndRPC: func(ctx context.Context, pkgname, svcname, opname string, res *TwirpRPCResult) {
			tags := buildOnBeginRPCTags("twirp", svcname, pkgname, opname)
			tags[AttemptErrorMetricTag] = strconv.FormatBool(res.Err != nil)

			if res.Err != nil {
				switch terr := res.Err.(type) {
				case twirp.Error:
					tags[AttemptErrorCodeMetricTag] = string(terr.Code())
				default:
					tags[AttemptErrorCodeMetricTag] = unavail
				}
			}

			emitOnEndRPC(ctx, client, res.Duration, tags, res.Err != nil)
		},
	}
}

type TwirpHooks struct {
	OnBeginRPC func(ctx context.Context, pkg, svc, method string)
	OnEndRPC   func(ctx context.Context, pkg, svc, method string, res *TwirpRPCResult)
}

type TwirpRPCResult struct {
	Duration time.Duration
	Err      error
}

func AdaptTwirpHooksToClientOptions(hooks *TwirpHooks, timeNow func() time.Time) []twirp.ClientOption {
	iceptor := func(next twirp.Method) twirp.Method {
		return func(ctx context.Context, req any) (any, error) {
			pkgName, ok := twirp.PackageName(ctx)
			if !ok {
				pkgName = unavail
			}
			svcName, ok := twirp.ServiceName(ctx)
			if !ok {
				svcName = unavail
			}
			methodName, ok := twirp.MethodName(ctx)
			if !ok {
				methodName = unavail
			}

			startAt := timeNow()
			hooks.OnBeginRPC(ctx, pkgName, svcName, methodName)
			res, err := next(ctx, req)
			hooks.OnEndRPC(ctx, pkgName, svcName, methodName, &TwirpRPCResult{
				Duration: timeNow().Sub(startAt),
				Err:      err,
			})

			return res, err
		}
	}

	return []twirp.ClientOption{twirp.WithClientInterceptors(iceptor)}
}
