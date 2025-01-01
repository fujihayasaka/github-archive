package mw_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/launch/pkg/mu/muhttp/mw"
)

type testHandler struct {
	Request *http.Request
}

func (h *testHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.Request = r
}

func TestRequestIdWithExistingHeader(t *testing.T) {
	h := &testHandler{}

	fn := mw.GitHubRequestID(h)

	w := httptest.NewRecorder()

	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Add("X-GitHub-Request-Id", "12345")

	fn.ServeHTTP(w, req)

	id := mw.GetGitHubRequestID(h.Request.Context())
	if id != "12345" {
		t.Fatalf("expected 12345, got %s", id)
	}
}

func TestRequestIdWithoutExistingHeader(t *testing.T) {
	h := &testHandler{}

	fn := mw.GitHubRequestID(h)

	w := httptest.NewRecorder()

	req := httptest.NewRequest("GET", "/", nil)

	fn.ServeHTTP(w, req)

	id := mw.GetGitHubRequestID(h.Request.Context())
	if len(id) == 0 {
		t.Error("expected an id, got empty string")
	}
}

func TestRequestIdWithNilContext(t *testing.T) {
	id := mw.GetGitHubRequestID(nil) // nolint: staticcheck, megacheck
	if id != "" {
		t.Error("expected empty request id")
	}
}

func TestRequestIdNotInContext(t *testing.T) {
	id := mw.GetGitHubRequestID(context.Background())
	if id != "" {
		t.Error("expected empty request id")
	}
}
