package telemetry

import (
	"net/http"
	"strconv"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/report"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
)

// reporter is used in middelware to log request stats and send stats to the statsd server.
// Middleware source code: https://github.com/github/go-http/blob/main/middleware/report/report.go
type reporter struct {
	Stats  stats.Client
	Logger *Logger
}

func NewReporter(telem *Telemetry) *reporter {
	return &reporter{
		Stats:  telem.Stats,
		Logger: telem.Logger,
	}
}

var _ report.Logger = (*reporter)(nil)
var _ report.ConnectionCountRecorder = (*reporter)(nil)

func (r *reporter) RecordConnectionCount(value int64) {
	r.Stats.Gauge(HttpConnections_StatsKey, nil, value)
}

// Log the results of the request and send stats to the statsd server.
func (r *reporter) LogRequest(req *http.Request, i report.ResponseInfo) {
	ctx := req.Context()
	requestid := requestid.GetGitHubRequestID(ctx)
	loggerFields := []kvp.Field{
		kvp.String(OtelHttpMethod, req.Method),
		kvp.String(OtelHttpTarget, req.URL.RequestURI()),
		kvp.Duration(OtelHttpDuration, i.Duration),
		kvp.Int(OtelHttpSize, i.Size),
		kvp.Int(OtelHttpStatusCode, i.StatusCode),
		kvp.String(GitHubRequestIDKey, requestid),
	}
	logger := r.Logger.WithContext(ctx).WithFields(loggerFields...)
	logger.Info("Request stats")

	// Record the stats of the request
	statsTags := stats.Tags{
		HttpTargetKey:     req.URL.RequestURI(),
		HttpMethodKey:     req.Method,
		HttpStatusCodeKey: strconv.Itoa(i.StatusCode),
	}
	r.Stats.Counter(HttpResponseCount_StatsKey, statsTags, 1)
	r.Stats.Distribution(HttpRequestDuration_StatsKey, statsTags, float64(i.Duration.Milliseconds()))
	r.Stats.Distribution(HttpResponseSize_StatsKey, statsTags, float64(i.Size))
}
