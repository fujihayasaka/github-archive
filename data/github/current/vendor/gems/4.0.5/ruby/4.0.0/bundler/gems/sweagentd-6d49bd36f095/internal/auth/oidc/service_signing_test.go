package oidc_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/golang-jwt/jwt/v4"

	"github.com/github/sweagentd/internal/auth/oidc"
	"github.com/github/sweagentd/internal/auth/oidc/devsigner"
	"github.com/github/sweagentd/internal/auth/oidc/devsigner/signerhttp"
	"github.com/github/sweagentd/internal/observability"
)

// Test OIDC service's token signing using the built-in signer as a  placeholder for the prod one.
func TestIDTokenSigning(t *testing.T) {
	obsv := observability.NewNoopExporters()
	signer, err := devsigner.NewSignerFromKey("https://issuer.example.com", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	svc := oidc.NewService(nil, signer, nil, nil, obsv, oidc.ServiceConfig{})
	if svc == nil {
		t.Fatal("expected non-nil service")
	}
	if signer.PublicKey() == nil {
		t.Fatal("expected non-nil public key")
	}
	if signer.KeyID() == "" {
		t.Fatal("expected non-empty key ID")
	}

	// Verify that the service can issue a token.
	token, err := svc.IssueIDToken(context.Background(), "test-aud", "test-sub", "test-act-sub", nil)
	if err != nil {
		t.Fatalf("failed to issue token: %v", err)
	}
	if token == "" {
		t.Error("expected non-empty token")
	}

	// Verify that the JWKS endpoint exposes the signing key via registered routes.
	handler := signerhttp.NewHandler(signer)
	mux := http.NewServeMux()
	handler.RegisterRoutes(routeAdapter{mux})

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/.well-known/jwks.json", http.NoBody)
	mux.ServeHTTP(rec, req)

	type jwkKeyResp struct {
		Kid string `json:"kid"`
	}
	type jwkSetResp struct {
		Keys []jwkKeyResp `json:"keys"`
	}

	var ks jwkSetResp
	err = json.Unmarshal(rec.Body.Bytes(), &ks)
	if err != nil {
		t.Fatalf("failed to decode JWKS: %v", err)
	}
	if len(ks.Keys) != 1 {
		t.Fatalf("expected 1 key in JWKS, got %d", len(ks.Keys))
	}

	// Parse the issued token and verify the kid matches the JWKS key.
	parsed, err := jwt.Parse(token, func(_ *jwt.Token) (any, error) {
		return nil, errors.New("skipping verification")
	})
	// jwt.Parse returns an error because we didn't verify — we only care about headers.
	if parsed == nil {
		t.Fatalf("failed to parse token header: %v", err)
	}
	kid, ok := parsed.Header["kid"].(string)
	if !ok || kid == "" {
		t.Fatal("expected kid in token header")
	}
	if kid != ks.Keys[0].Kid {
		t.Errorf("token kid %q does not match JWKS kid %q", kid, ks.Keys[0].Kid)
	}
}

// routeAdapter adapts http.ServeMux to the interface expected by signerhttp.Handler.RegisterRoutes.
type routeAdapter struct {
	mux *http.ServeMux
}

func (r routeAdapter) Get(pattern string, handler http.HandlerFunc) {
	r.mux.HandleFunc("GET "+pattern, handler)
}
