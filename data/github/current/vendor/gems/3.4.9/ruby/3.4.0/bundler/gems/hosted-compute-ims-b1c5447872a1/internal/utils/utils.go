package utils

import (
	"context"
	"database/sql/driver"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-core/telemetry"
)

func ToPtr[T any](v T) *T {
	return &v
}

func FromPtr[T any](p *T) T {
	var v T
	if p != nil {
		v = *p
	}
	return v
}

func NewLoggerWithFields(logger *telemetry.ReportingLogger, fields ...kvp.Field) *telemetry.ReportingLogger {
	return telemetry.NewReportingLogger(
		logger.WithFields(fields...),
		logger.Reporter,
		logger.Statter,
	)
}

func CheckUrlReachability(ctx context.Context, logger *telemetry.ReportingLogger, url string) bool {
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, url, nil)
	if err != nil {
		return false
	}

	client := NewRetryableHttpClientWithLogging("sas_url_validation", logger).
		WithInternalHttpClient(&http.Client{Timeout: 5 * time.Second}).
		WithTelemetrySettings(false)

	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	return resp.StatusCode == http.StatusOK
}

func GetMapKeys[K comparable, V any](m map[K]V) []K {
	keys := make([]K, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}

	return keys
}

type AnyTime struct{}

// Match satisfies sqlmock.Argument interface
func (a AnyTime) Match(v driver.Value) bool {
	_, ok := v.(time.Time)
	return ok
}
