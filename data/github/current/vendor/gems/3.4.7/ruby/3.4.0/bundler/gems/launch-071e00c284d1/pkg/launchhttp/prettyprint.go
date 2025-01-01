package launchhttp

import (
	"net/http"
	"strings"
)

// GetMetricTagForStatusCode takes a status code and prints a string representation suitable
// for usage as a metric tag.
func GetMetricTagForStatusCode(code int) string {
	s := http.StatusText(code)
	return strings.ReplaceAll(strings.ToLower(s), " ", "_")
}
