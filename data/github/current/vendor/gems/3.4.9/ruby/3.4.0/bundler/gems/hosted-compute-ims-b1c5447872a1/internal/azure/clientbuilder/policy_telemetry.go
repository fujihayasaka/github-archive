package clientbuilder

import (
	"fmt"
	"net/http"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
)

type telemetryPolicy struct {
	logger *telemetry.ReportingLogger
}

func newTelemetryPolicy(logger *telemetry.ReportingLogger) telemetryPolicy {
	return telemetryPolicy{
		logger: logger,
	}
}

func (p telemetryPolicy) Do(req *policy.Request) (*http.Response, error) {
	requestStartTime := time.Now()

	res, err := req.Next()

	requestDuration := time.Since(requestStartTime)
	statusCode := -1
	if res != nil {
		statusCode = res.StatusCode
	}

	tags := stats.Tags{
		"method":      req.Raw().Method,
		"url":         req.Raw().URL.String(),
		"status_code": fmt.Sprint(statusCode),
	}
	p.logger.Statter.Counter("azure.request", tags, 1)
	p.logger.Statter.DistributionMs("azure.request_duration", tags, requestDuration)

	return res, err
}
