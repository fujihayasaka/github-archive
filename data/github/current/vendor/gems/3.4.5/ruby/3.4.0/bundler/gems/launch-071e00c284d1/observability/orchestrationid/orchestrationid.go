package orchestrationid

import (
	"net/http"

	"github.com/github/launch/observability/ctxstash"
)

type orchestrationIdRequestHeadersTransport struct {
	Transport http.RoundTripper
}

// NewOrchestrationIdRequestHeadersTransport returns a new http.RoundTripper that sets the X-GitHub-Actions-Orchestration-Id header on the request if the context contains an orchestration ID.
func NewOrchestrationIdRequestHeadersTransport(rt http.RoundTripper) http.RoundTripper {
	return &orchestrationIdRequestHeadersTransport{Transport: rt}
}

func (orht *orchestrationIdRequestHeadersTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	ctx := req.Context()
	orchID := ctxstash.From(ctx).Correlations().VSS.OrchestrationID
	if orchID != "" {
		req.Header.Set("X-GitHub-Actions-Orchestration-Id", orchID)
	}

	return orht.Transport.RoundTrip(req)
}
