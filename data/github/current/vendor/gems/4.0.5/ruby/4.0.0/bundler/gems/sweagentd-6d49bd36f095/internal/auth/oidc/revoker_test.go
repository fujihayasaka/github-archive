package oidc

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/sweagentd/internal/observability"
)

func TestRevoker_RevokeToken_Success(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("expected POST, got %s", r.Method)
		}
		if ct := r.Header.Get("Content-Type"); ct != "application/x-www-form-urlencoded" {
			t.Errorf("expected form content type, got %q", ct)
		}

		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		if r.FormValue("token") != "access-token-123" {
			t.Errorf("unexpected token: %q", r.FormValue("token"))
		}
		if r.FormValue("token_type_hint") != "access_token" {
			t.Errorf("unexpected token_type_hint: %q", r.FormValue("token_type_hint"))
		}
		if r.FormValue("subject_token") != "id-token-456" {
			t.Errorf("unexpected subject_token: %q", r.FormValue("subject_token"))
		}
		if r.FormValue("subject_token_type") != tokenTypeIDToken {
			t.Errorf("unexpected subject_token_type: %q", r.FormValue("subject_token_type"))
		}

		w.WriteHeader(http.StatusOK)
	}))
	defer svr.Close()

	revoker := NewRevoker(svr.Client(), observability.NewNoopExporters())
	err := revoker.RevokeToken(context.Background(), svr.URL, "id-token-456", "access-token-123", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestRevoker_RevokeToken_ServerError(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte("server error"))
	}))
	defer svr.Close()

	revoker := NewRevoker(svr.Client(), observability.NewNoopExporters())
	err := revoker.RevokeToken(context.Background(), svr.URL, "id", "access", "")

	if !errors.Is(err, ErrTokenRevocationFailed) {
		t.Fatalf("expected ErrTokenRevocationFailed, got: %v", err)
	}
}

func TestRevoker_RevokeToken_ConnectionError(t *testing.T) {
	revoker := NewRevoker(&http.Client{}, observability.NewNoopExporters())
	err := revoker.RevokeToken(context.Background(), "http://127.0.0.1:0/bad", "id", "access", "")

	if !errors.Is(err, ErrNetworkError) {
		t.Fatalf("expected ErrNetworkError, got: %v", err)
	}
}

func TestRevoker_RevokeToken_WithClientID(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		if r.FormValue("client_id") != "github-agent:my-app" {
			t.Errorf("unexpected client_id: %q", r.FormValue("client_id"))
		}
		if r.FormValue("token") != "access-token" {
			t.Errorf("unexpected token: %q", r.FormValue("token"))
		}

		w.WriteHeader(http.StatusOK)
	}))
	defer svr.Close()

	revoker := NewRevoker(svr.Client(), observability.NewNoopExporters())
	err := revoker.RevokeToken(context.Background(), svr.URL, "id-token", "access-token", "github-agent:my-app")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestRevoker_RevokeToken_OmitsEmptyClientID(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		if r.Form.Has("client_id") {
			t.Error("client_id should not be present when empty")
		}

		w.WriteHeader(http.StatusOK)
	}))
	defer svr.Close()

	revoker := NewRevoker(svr.Client(), observability.NewNoopExporters())
	err := revoker.RevokeToken(context.Background(), svr.URL, "id-token", "access-token", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}
