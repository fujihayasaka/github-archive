package utils

import (
	"context"
	"database/sql/driver"
	"net/http"
	"os"
	"time"
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

func CheckUrlReachability(ctx context.Context, url string) bool {
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, url, nil)
	if err != nil {
		return false
	}

	client := NewRetryableHttpClientWithLogging("sas_url_validation").
		WithInternalHttpClient(&http.Client{Timeout: 5 * time.Second}).
		WithTelemetrySettings(false)

	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	return resp.StatusCode == http.StatusOK
}

func FilterFunc[T any](collection []T, match func(T) bool) (filtered []T) {
	for _, elem := range collection {
		if match(elem) {
			filtered = append(filtered, elem)
		}
	}

	return filtered
}

func MapFunc[T any, P any](collection []*T, mapper func(*T) (*P, error)) ([]*P, error) {
	result := make([]*P, 0, len(collection))

	for _, elem := range collection {
		mappedElement, err := mapper(elem)
		if err != nil {
			return nil, err
		}

		result = append(result, mappedElement)
	}

	return result, nil
}

func GetMapKeys[K comparable, V any](m map[K]V) []K {
	keys := make([]K, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}

	return keys
}

func WriteStartupCompletionFlag() error {
	return os.WriteFile("/tmp/ims_completed_startup", []byte(time.Now().Format(time.RFC850)), 0o600) // nolint:gosec // write timestamp and keep it in /tmp
}

type AnyTime struct{}

// Match satisfies sqlmock.Argument interface
func (a AnyTime) Match(v driver.Value) bool {
	_, ok := v.(time.Time)
	return ok
}
