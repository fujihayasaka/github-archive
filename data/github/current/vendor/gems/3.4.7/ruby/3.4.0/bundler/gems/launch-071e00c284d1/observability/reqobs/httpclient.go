package reqobs

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

func NewHTTPClientHooks(obs *observability.Observability) *httpclient.ClientHooks {
	return &httpclient.ClientHooks{
		OnBeginRPC: func(ctx context.Context, svcname, pkgname, opname string) *httpclient.HookContext {
			tags := buildOnBeginRPCTags("rest", svcname, pkgname, opname)
			emitOnAttemptCounter(ctx, obs.Statter, tags)
			return &httpclient.HookContext{
				Tags:         tags,
				RPCStartTime: time.Now(),
				Service:      svcname,
				Package:      pkgname,
				Operation:    opname,
			}
		},
		OnBeginCacheGet: func(ctx context.Context, hc *httpclient.HookContext) {
			hc.CacheGetStart = time.Now()
		},
		OnEndCacheGet: func(ctx context.Context, hc *httpclient.HookContext) {
			hc.Tags = hc.Tags.Merge(statter.Tags{
				"cache_hit":     strconv.FormatBool(hc.CacheGetHit),
				"cache_get_err": strconv.FormatBool(hc.CacheGetErr != nil),
			})
			obs.Statter.Distribution(ctx, "rpc.cache.get.duration_ms", hc.Tags, float64(time.Since(hc.CacheGetStart).Milliseconds()))

			if hc.CacheGetErr != nil {
				obs.Report(ctx, hc.CacheGetErr, hc.Fields...)
			}
		},
		OnBeginCacheSet: func(ctx context.Context, hc *httpclient.HookContext) {
			hc.CacheSetStart = time.Now()
		},
		OnEndCacheSet: func(ctx context.Context, hc *httpclient.HookContext) {
			hc.Tags = hc.Tags.Merge(statter.Tags{
				"cache_set_err": strconv.FormatBool(hc.CacheSetErr != nil),
			})
			obs.Statter.Distribution(ctx, "rpc.cache.set.duration_ms", hc.Tags, float64(time.Since(hc.CacheSetStart).Milliseconds()))

			if hc.CacheSetErr != nil {
				obs.Report(ctx, hc.CacheSetErr, hc.Fields...)
			}
		},
		OnStartPerformRequest: func(_ context.Context, attempt int, req *http.Request, hc *httpclient.HookContext) {
			hc.Attempt = attempt
			hc.Tags = cleanupTags(hc.Tags)
			hc.Fields = cleanupFields()
			hc.ReqStartTime = time.Now()
			if hc.Attempt > 0 {
				hc.Tags = hc.Tags.Merge(statter.Tags{"attempt": strconv.Itoa(hc.Attempt)})
			}
			hc.Fields = append(hc.Fields, requestFields(req, hc.Operation)...)
		},
		OnDonePerformRequest: func(ctx context.Context, err error, hc *httpclient.HookContext) {
			hc.Error = err
			hc.Tags = hc.Tags.Merge(tagForError(hc.Error))

			if hc.Error != nil {
				emitOnDonePerformRequest(ctx, obs.Statter, time.Since(hc.ReqStartTime), hc.Error, hc.Tags)
				logOutgoingRequest(ctx, obs, hc)

				// <legacy>
				obs.RecordHTTPResult(ctx, hc.Service, hc.Operation, 0, hc.Error)
				// </legacy>
			}
		},
		OnStartHandleResponse: func(ctx context.Context, resp *http.Response, hc *httpclient.HookContext) {
			hc.RespStartTime = time.Now()
			if resp != nil {
				hc.Tags = hc.Tags.Merge(statter.Tags{AttemptStatusCodeMetricTag: strconv.Itoa(resp.StatusCode)})
				hc.Fields = append(hc.Fields, responseFields(resp)...)
				logOutgoingRequest(ctx, obs, hc)

				// <legacy>
				obs.RecordHTTPResult(ctx, hc.Service, hc.Operation, resp.StatusCode, nil)
				// </legacy>
			}
		},
		OnDoneHandleResponse: func(ctx context.Context, hc *httpclient.HookContext) {
			tag := tagForError(hc.Error)
			hc.Tags = hc.Tags.Merge(tag)
			if strings.HasPrefix(tag["AttemptErrorCodeMetricTag"], launchhttp.ErrCategoryAZP+"_"+azperrors.ActionsScaleUnitUnavailable) {
				obs.Statter.Counter(ctx, "rpc.azp.actions_scale_unit_unavailable", hc.Tags, 1)
			}
			emitOnDoneHandleResponse(ctx, obs.Statter, time.Since(hc.ReqStartTime), hc.Tags)
		},
		OnEndRPC: func(ctx context.Context, hc *httpclient.HookContext) {
			emitOnEndRPC(ctx, obs.Statter, time.Since(hc.RPCStartTime), hc.Tags, hc.Error != nil)
		},
	}
}

func responseFields(resp *http.Response) []kvp.Field {
	return []kvp.Field{
		kvp.Int("http.response.status_code", resp.StatusCode),
		kvp.String("gh.launch.http.response_status_category", observability.HTTPStatusToCategoryName(resp.StatusCode)),
	}
}

func requestFields(req *http.Request, operation string) []kvp.Field {
	return []kvp.Field{
		kvp.String("gh.launch.operation.name", operation),
		kvp.String("user_agent.original", req.Header.Get(azpcorrelation.UserAgentHeaderName)),
		kvp.String("http.request.method", req.Method),
		kvp.String("http.request.host", req.URL.String()),
	}
}

func cleanupFields() []kvp.Field {
	return []kvp.Field{}
}

func tagForError(err error) statter.Tags {
	if err == nil {
		return statter.Tags{
			AttemptErrorMetricTag: "false",
		}
	}
	return statter.Tags{
		AttemptErrorMetricTag:     "true",
		AttemptErrorCodeMetricTag: launchhttp.GetLowCardinalityErrorCategory(err),
	}
}

func cleanupTags(tags statter.Tags) statter.Tags {
	nt := tags
	delete(nt, AttemptErrorMetricTag)
	delete(nt, AttemptErrorCodeMetricTag)
	delete(nt, AttemptStatusCodeMetricTag)
	return nt
}
