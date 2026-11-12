package httputil

import (
	"net/http"
	"strconv"
	"time"

	"github.com/github/token-scanning-service/ts/utils"
)

// StatRoundTripper wraps a base roundtripper and reports metrics based on http timings
// The metric reporter/statter should already be set in the context for this to work otherwise we simply continue the request like normal
type StatRoundTripper struct {
	baseRoundTripper http.RoundTripper
}

// NewStatRoundTripper creates a new StatRoundTripper
func NewStatRoundTripper(baseRoundTripper http.RoundTripper) *StatRoundTripper {
	return &StatRoundTripper{baseRoundTripper: baseRoundTripper}
}

// RoundTrip implements the http.RoundTripper interface and emits timing stats via the statter
func (s *StatRoundTripper) RoundTrip(r *http.Request) (*http.Response, error) {
	statter := utils.StatterFromContext(r.Context())
	if statter == nil {
		return s.baseRoundTripper.RoundTrip(r)
	}

	start := time.Now()
	resp, err := s.baseRoundTripper.RoundTrip(r)

	tags := map[string]string{
		"http.request.host":   r.URL.Hostname(),
		"http.request.url":    r.URL.String(),
		"http.request.method": r.Method,
	}
	if resp != nil {
		tags["http.response.status_code"] = strconv.Itoa(resp.StatusCode)
		tags["http.response.errored"] = strconv.FormatBool(resp.StatusCode >= http.StatusBadRequest)
	}
	if err != nil {
		tags["http.response.errored"] = "true"
	}
	statter.DistributionMs("http.client.request.duration", tags, time.Since(start))
	return resp, err
}
