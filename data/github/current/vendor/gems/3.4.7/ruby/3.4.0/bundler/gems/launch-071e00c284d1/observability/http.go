package observability

import (
	"context"
	"fmt"
	"net/url"
	"strconv"
	"sync"

	"github.com/github/go-log"
	"github.com/github/go-reqmeta"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/observability/metrickeys"
)

type contextKey string

const retryKey contextKey = "retrycounter"

type retryCounter struct {
	mutex   sync.Mutex
	retries int
}

// HTTPStatusToCategoryName buckets status codes into their category, and returns "invalid_status" for
// codes not in the specification.
func HTTPStatusToCategoryName(status int) string {
	// https://tools.ietf.org/html/rfc2616#section-6.1.1
	switch {
	case status >= 600:
		return metrickeys.InvalidHTTPStatus
	case status >= 500:
		return "5xx"
	case status >= 400:
		return "4xx"
	case status >= 300:
		return "3xx"
	case status >= 200:
		return "2xx"
	case status >= 100:
		return "1xx"
	default:
		return metrickeys.InvalidHTTPStatus
	}
}

func statusForHTTPResult(httpCode int, err error) string {
	if err == nil {
		return HTTPStatusToCategoryName(httpCode)
	}
	// we suffered an error at below the application layer
	return metrickeys.NonHTTPError
}

// RecordHTTPResult records the outcome of a HTTP request to an external API
func (o *Observability) RecordHTTPResult(ctx context.Context, serviceName, operationName string, httpCode int, err error) {
	CountHTTPResult(ctx, o, serviceName, operationName, httpCode, err)
}

// WithRetryCounter creates a new context with a retry counter
func WithRetryCounter(ctx context.Context) context.Context {
	return context.WithValue(ctx, retryKey, &retryCounter{})
}

// GetRetryCount returns the current retry count in the context. Returns -1 if there is no retry counter in context.
func GetRetryCount(ctx context.Context) int {
	if v, ok := ctx.Value(retryKey).(*retryCounter); ok {
		return v.retries
	}
	return -1
}

// IncrementRetryCounter increase the retry count by one. Noop if there is no retry counter in context.
func IncrementRetryCounter(ctx context.Context) {
	if v, ok := ctx.Value(retryKey).(*retryCounter); ok {
		// mutex here might be overkill, since retries should be serial
		v.mutex.Lock()
		defer v.mutex.Unlock()
		v.retries++
	} else {
		// No key found, log something although it's expected to not be there for all consumers of the function
		log.Debug("no retrycounter to increment")
	}
}

// CountHTTPResult records the outcome of a HTTP request to an external API
func CountHTTPResult(ctx context.Context, obs *Observability, serviceName string, operationName string, httpCode int, err error) {
	tags := map[string]string{
		metrickeys.ServiceName:        serviceName,
		metrickeys.OperationName:      operationName,
		metrickeys.HTTPResultCategory: statusForHTTPResult(httpCode, err),
	}

	retry := GetRetryCount(ctx)
	if retry > 0 {
		tags["retry_number"] = strconv.Itoa(retry)
	}

	if httpCode != 0 {
		tags[metrickeys.HTTPStatusCode] = strconv.Itoa(httpCode)
	}
	obs.Counter(ctx, fmt.Sprintf("%s.%s", metrickeys.ExternalAPI, metrickeys.HTTPResult), tags, 1)
}

// SetRetryInQueryString adds a retry counter to query string based on a value in context. Relies on a context that's been initialized with `WithRetryCounter`
func SetRetryInQueryString(ctx context.Context, u *url.URL) {
	r := GetRetryCount(ctx)
	if r > 0 {
		q := u.Query()
		q.Set("retry_number", fmt.Sprint(r))
		u.RawQuery = q.Encode()
	}
}

func EnableTwirpRequestMetadata() *twirp.ServerHooks {
	return &twirp.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			return reqmeta.WithRequestMetadata(ctx, reqmeta.NewRequestMetadata()), nil
		},
	}
}
