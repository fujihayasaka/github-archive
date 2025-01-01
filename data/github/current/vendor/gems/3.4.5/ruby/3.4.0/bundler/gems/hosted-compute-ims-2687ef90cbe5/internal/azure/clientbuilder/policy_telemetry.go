package clientbuilder

import (
	"net/http"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
)

type telemetryPolicy struct{}

func newTelemetryPolicy() telemetryPolicy {
	return telemetryPolicy{}
}

func (p telemetryPolicy) Do(req *policy.Request) (*http.Response, error) {
	requestStartTime := time.Now()

	res, err := req.Next()

	requestDuration := time.Since(requestStartTime)
	statusCode := -1
	if res != nil {
		statusCode = res.StatusCode
	}

	ctx := req.Raw().Context()
	fields := []kvp.Field{
		kvp.String("method", req.Raw().Method),
		kvp.String("url", req.Raw().URL.String()),
		kvp.Int("status_code", statusCode),
	}
	statter.Increment(ctx, "azure.request", fields...)
	statter.DistributionMs(ctx, "azure.request_duration", requestDuration, fields...)

	return res, err
}
