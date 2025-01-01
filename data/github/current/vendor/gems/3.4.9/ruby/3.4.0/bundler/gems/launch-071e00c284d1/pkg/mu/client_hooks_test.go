package mu_test

import (
	"context"
	"net/http"
	"testing"

	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/mu/muhttp/mw"
)

func TestGitHubRequestHeadersOnInteralRequest(t *testing.T) {
	ctx := context.WithValue(context.Background(), mw.RequestIDKey, "aaa-bbb")
	req, _ := http.NewRequest("GET", "https://api.github.com/users/mu", nil)
	req = req.WithContext(ctx)

	mu.ForwardRequestID(req)

	if req.Header.Get("X-GitHub-Request-ID") != "aaa-bbb" {
		t.Error("request id header should be set")
	}

	if len(req.Header.Get("X-GLB-Via")) == 0 {
		t.Error("glb via header should be set")
	}
}
