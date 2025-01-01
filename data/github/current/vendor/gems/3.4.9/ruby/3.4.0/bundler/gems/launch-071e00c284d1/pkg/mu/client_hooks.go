package mu

import (
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/github/launch/pkg/mu/muhttp/mw"
)

// ForwardRequestID is a request hook that looks for X-GitHub-Request-Id and
// X-GLB-Via headers in the incoming contextand adds them to r's headers.
func ForwardRequestID(r *http.Request) {
	ctx := r.Context()

	// If this request is going to a github domain, forward the
	// X-GitHub-Request-Id and X-GLB-Via headers
	if reqID := mw.GetGitHubRequestID(ctx); reqID != "" {
		r.Header.Set(xGitHubRequestID, reqID)
	}

	if host, err := os.Hostname(); err == nil {
		t := float64(time.Now().UnixNano()) / 1000000000.0
		r.Header.Set(xGLBVia, fmt.Sprintf("hostname=%s t=%f", host, t))
	}
}

const (
	xGitHubRequestID = "X-GitHub-Request-ID"
	xGLBVia          = "X-GLB-Via"
)
