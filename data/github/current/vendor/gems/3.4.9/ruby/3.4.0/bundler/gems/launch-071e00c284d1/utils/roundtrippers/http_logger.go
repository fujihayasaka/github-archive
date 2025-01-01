package roundtrippers

import (
	"net/http"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/launchhttp"
)

// These field names are based on https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/http.md, with underscores in place of periods.
const (
	rlhLogMsg            = "http.outgoing"
	rlhMethod            = "http_method"
	rlhHost              = "http_host"
	rlhStatusCode        = "http_code"
	rlhTarget            = "http_target"
	rlhUserAgent         = "http_user_agent"
	rlhWroteHeaders      = "http_wheaders_sec"
	rlhWroteRequest      = "http_wrequest_sec"
	rlhFirstResponseByte = "http_response_sec"
	rlhTotalLatency      = "http_duration_sec"
	rlhError             = "http_error"
	rlhErrorType         = "http_error_type"
	rlhErrorMessage      = "http_error_msg"
	rlhRequestID         = "gh.request_id"
	rlhAqueductJobID     = ctxstash.AqueductJobIDKey
	rlhOrigAqueductJobID = ctxstash.OrigAqueductJobIDKey
	rlhOrchestrationID   = ctxstash.VSSOrchestrationIDKey
	rlhReqVSSID          = ctxstash.VSSReqE2EIDKey
	rlhRespVSSID         = ctxstash.VSSRespE2EIDKey
	rlhVSSID             = ctxstash.VSSCorrelationIDKey
)

func RequestLoggingHook(logger logger.Logger) Hook {
	return func(req *http.Request, resp *http.Response, timings *Timings, reqErr error) {
		reqCtx := req.Context()
		stash := ctxstash.From(reqCtx)
		fields := extractCorrelationFields(stash.Correlations())

		fields = append(fields,
			kvp.String(rlhMethod, req.Method),
			kvp.String(rlhHost, req.URL.Hostname()),
			kvp.String(rlhTarget, req.URL.RequestURI()),
			kvp.String(rlhUserAgent, req.UserAgent()),
			kvp.Duration(rlhWroteHeaders, timings.WroteHeaders),
			kvp.Duration(rlhWroteRequest, timings.WroteRequest),
			kvp.Duration(rlhFirstResponseByte, timings.FirstResponseByte),
			kvp.Duration(rlhTotalLatency, timings.TotalLatency),
		)

		if resp != nil {
			httpErrRespCode := resp.StatusCode >= 400
			respFields := []kvp.Field{
				kvp.Int(rlhStatusCode, resp.StatusCode),
				kvp.Bool(rlhError, httpErrRespCode),
			}
			if httpErrRespCode {
				respFields = append(respFields, kvp.String(rlhErrorType, prettyPrintStatusCode(resp.StatusCode)))
			}
			respFields = append(respFields, extractCorrelationRespHeaders(resp)...)
			fields = append(fields, respFields...)
		}

		if reqErr != nil {
			fields = append(fields,
				kvp.String(rlhErrorMessage, reqErr.Error()),
				kvp.String(rlhErrorType, launchhttp.GetLowCardinalityErrorCategory(reqErr)),
				kvp.Bool(rlhError, true),
			)
		}

		logCtx := cleanCtx(reqCtx)

		logger.Debug(logCtx, rlhLogMsg, fields...)
	}
}
