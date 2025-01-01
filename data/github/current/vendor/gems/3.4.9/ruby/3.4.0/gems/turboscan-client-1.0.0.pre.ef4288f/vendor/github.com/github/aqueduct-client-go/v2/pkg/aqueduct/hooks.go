package aqueduct

import (
	"context"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/kvp/fields"
	"github.com/github/github-telemetry-go/kvp/keys"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/twitchtv/twirp"
)

// Context value key for storing client request start time.
type reqStartKey struct{}

// requestStartTime attempts to extract the value for reqStartKey from the
// context.
func requestStartTime(ctx context.Context) (time.Time, bool) {
	startTime, ok := ctx.Value(reqStartKey{}).(time.Time)
	return startTime, ok
}

type clientHooks struct {
	logger log.Logger
	stats  stats.Client
}

func newClientHooks(logger log.Logger, stats stats.Client) *twirp.ClientHooks {
	c := &clientHooks{
		logger: logger,
		stats:  stats,
	}

	return &twirp.ClientHooks{
		RequestPrepared:  c.requestPrepared,
		ResponseReceived: c.responseReceived,
		Error:            c.onError,
	}
}

func (c *clientHooks) requestPrepared(ctx context.Context, request *http.Request) (context.Context, error) {
	kvps := c.buildKvps(ctx)
	c.logger.Debug("Sending request", kvps...)

	ctx = context.WithValue(ctx, reqStartKey{}, time.Now())
	return ctx, nil
}

func (c *clientHooks) responseReceived(ctx context.Context) {
	kvps := c.buildKvps(ctx)
	tags := c.buildTags(ctx)

	status, haveStatus := twirp.StatusCode(ctx)
	if haveStatus {
		kvps = append(kvps, kvp.Any(keys.Http.StatusCode, status))
		tags["http.status"] = status
	}

	c.logger.Debug("Received response", kvps...)

	tags["success"] = "true"
	c.stats.Counter("request.count", tags, 1)

	start, haveReqStart := requestStartTime(ctx)
	if haveReqStart {
		c.stats.Timing("request.time", tags, time.Since(start))
	}
}

func (c *clientHooks) onError(ctx context.Context, err twirp.Error) {
	if ctx.Err() == context.Canceled {
		// The context was canceled, most likely the
		// application just wanted to exit.  We shouldn't
		// count this as an error.
		return
	}
	kvps := c.buildKvps(ctx)
	tags := c.buildTags(ctx)

	code := err.Code()
	kvps = append(kvps, fields.RpcJsonrpc.ErrorMessage(err.Msg()),
		fields.RpcJsonrpc.ErrorCode(twirp.ServerHTTPStatusFromErrorCode(code)))

	c.logger.Error("Error while sending request", kvps...)

	tags["success"] = "false"
	c.stats.Counter("request.count", tags, 1)

	start, haveReqStart := requestStartTime(ctx)
	if haveReqStart {
		c.stats.Timing("request.time", tags, time.Since(start))
	}
}

func (c *clientHooks) buildKvps(ctx context.Context) []kvp.Field {
	kvps := make([]kvp.Field, 0)

	if methodName, ok := twirp.MethodName(ctx); ok {
		kvps = append(kvps, kvp.String("method", methodName))
	}

	if packageName, ok := twirp.PackageName(ctx); ok {
		kvps = append(kvps, kvp.String("package", packageName))
	}

	if serviceName, ok := twirp.ServiceName(ctx); ok {
		kvps = append(kvps, kvp.String("service", serviceName))
	}

	return kvps
}

func (c *clientHooks) buildTags(ctx context.Context) stats.Tags {
	tags := stats.Tags{}

	if methodName, ok := twirp.MethodName(ctx); ok {
		tags["method"] = methodName
	}

	if packageName, ok := twirp.PackageName(ctx); ok {
		tags["package"] = packageName
	}

	if serviceName, ok := twirp.ServiceName(ctx); ok {
		tags["service"] = serviceName
	}

	return tags
}
