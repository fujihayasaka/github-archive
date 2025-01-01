package fault

import (
	"bytes"
	"io"
	"net/http"
)

const errorFaultRoundTripperName = "errorFaultRoundTripper"

type errorFaultRoundTripper struct {
	reporter Reporter

	statusCode int
	statusText string
}

func NewErrorFault(reporter Reporter, statusCode int, statusText string) Injector {
	return &errorFaultRoundTripper{
		reporter:   reporter,
		statusCode: statusCode,
		statusText: statusText,
	}
}

func (s *errorFaultRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	s.reporter.Report(req.Context(), errorFaultRoundTripperName, StateStarted)
	resp := http.Response{
		Body:       io.NopCloser(bytes.NewBufferString(s.statusText)),
		StatusCode: s.statusCode,
	}
	return &resp, nil
}

func (s *errorFaultRoundTripper) chain(_ http.RoundTripper) Injector {
	return &errorFaultRoundTripper{
		reporter:   s.reporter,
		statusCode: s.statusCode,
		statusText: s.statusText,
	}
}
