package signerhttp

import (
	"crypto/rand"
	"crypto/rsa"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"

	"github.com/golang-jwt/jwt/v4"

	"github.com/github/sweagentd/internal/auth/oidc/devsigner"
)

type recordingMux struct {
	routes map[string]http.HandlerFunc
}

func (m *recordingMux) Get(pattern string, handler http.HandlerFunc) {
	if m.routes == nil {
		m.routes = make(map[string]http.HandlerFunc)
	}
	m.routes[pattern] = handler
}

func mustGenerateRSAKey(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("failed to generate RSA key: %v", err)
	}
	return key
}

func TestComputeKeyID(t *testing.T) {
	key := mustGenerateRSAKey(t)
	kid := devsigner.ComputeKeyID(&key.PublicKey)

	if kid == "" {
		t.Fatal("expected non-empty key ID")
	}

	// Same key should produce the same ID.
	kid2 := devsigner.ComputeKeyID(&key.PublicKey)
	if kid != kid2 {
		t.Errorf("expected deterministic key ID, got %q then %q", kid, kid2)
	}

	// Different key should produce a different ID.
	key2, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("failed to generate second key: %v", err)
	}
	kid3 := devsigner.ComputeKeyID(&key2.PublicKey)
	if kid == kid3 {
		t.Error("expected different key IDs for different keys")
	}
}

func TestRSAPublicKeyToJWK(t *testing.T) {
	key := mustGenerateRSAKey(t)
	jwk := rsaPublicKeyToJWK(&key.PublicKey, "test-kid")

	if jwk.Kty != "RSA" {
		t.Errorf("expected kty RSA, got %q", jwk.Kty)
	}
	if jwk.Use != "sig" {
		t.Errorf("expected use sig, got %q", jwk.Use)
	}
	if jwk.Alg != "RS256" {
		t.Errorf("expected alg RS256, got %q", jwk.Alg)
	}
	if jwk.Kid != "test-kid" {
		t.Errorf("expected kid test-kid, got %q", jwk.Kid)
	}
	if jwk.N == "" {
		t.Error("expected non-empty modulus")
	}
	if jwk.E == "" {
		t.Error("expected non-empty exponent")
	}
}

func TestHandler_JWKS(t *testing.T) {
	key := mustGenerateRSAKey(t)
	kid := devsigner.ComputeKeyID(&key.PublicKey)
	signer := devsigner.NewSigner(key, jwt.SigningMethodRS256, kid, "https://issuer.example.com")
	handler := NewHandler(signer)

	req := httptest.NewRequest(http.MethodGet, "/.well-known/jwks.json", http.NoBody)
	rec := httptest.NewRecorder()
	handler.handleJWKS(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("expected application/json, got %q", ct)
	}

	var ks jwkSet
	err := json.Unmarshal(rec.Body.Bytes(), &ks)
	if err != nil {
		t.Fatalf("failed to decode JWKS: %v", err)
	}
	if len(ks.Keys) != 1 {
		t.Fatalf("expected 1 key, got %d", len(ks.Keys))
	}
	if ks.Keys[0].Kid != kid {
		t.Errorf("expected kid %q, got %q", kid, ks.Keys[0].Kid)
	}
}

func TestHandler_OpenIDConfiguration(t *testing.T) {
	key := mustGenerateRSAKey(t)
	signer := devsigner.NewSigner(key, jwt.SigningMethodRS256, "kid-1", "https://issuer.example.com")
	handler := NewHandler(signer)

	req := httptest.NewRequest(http.MethodGet, "/.well-known/openid-configuration", http.NoBody)
	rec := httptest.NewRecorder()
	handler.handleOpenIDConfiguration(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var cfg openIDConfiguration
	err := json.Unmarshal(rec.Body.Bytes(), &cfg)
	if err != nil {
		t.Fatalf("failed to decode config: %v", err)
	}
	if cfg.Issuer != "https://issuer.example.com" {
		t.Errorf("expected issuer %q, got %q", "https://issuer.example.com", cfg.Issuer)
	}
	if cfg.JWKSURI != "https://issuer.example.com/.well-known/jwks.json" {
		t.Errorf("expected JWKS URI %q, got %q", "https://issuer.example.com/.well-known/jwks.json", cfg.JWKSURI)
	}
}

func TestHandler_RegisterRoutes(t *testing.T) {
	key := mustGenerateRSAKey(t)
	signer := devsigner.NewSigner(key, jwt.SigningMethodRS256, "kid-1", "https://issuer.example.com")
	handler := NewHandler(signer)
	mux := &recordingMux{}

	handler.RegisterRoutes(mux)

	got := make([]string, 0, len(mux.routes))
	for route := range mux.routes {
		got = append(got, route)
	}
	slices.Sort(got)

	want := []string{
		"/.well-known/jwks.json",
		"/.well-known/oauth-protected-resource",
		"/.well-known/oauth-protected-resource/public/mcp",
		"/.well-known/openid-configuration",
	}

	if len(got) != len(want) {
		t.Fatalf("expected %d routes, got %d: %v", len(want), len(got), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("expected routes %v, got %v", want, got)
		}
	}
}

func TestHandler_ProtectedResourceMetadata(t *testing.T) {
	key := mustGenerateRSAKey(t)
	signer := devsigner.NewSigner(key, jwt.SigningMethodRS256, "kid-1", "https://issuer.example.com")
	handler := NewHandler(signer)

	req := httptest.NewRequest(http.MethodGet, "/.well-known/oauth-protected-resource", http.NoBody)
	rec := httptest.NewRecorder()
	handler.handleProtectedResourceMeta(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var metadata protectedResourceMetadata
	err := json.Unmarshal(rec.Body.Bytes(), &metadata)
	if err != nil {
		t.Fatalf("failed to decode protected resource metadata: %v", err)
	}
	if metadata.Resource != "https://issuer.example.com" {
		t.Fatalf("expected resource %q, got %q", "https://issuer.example.com", metadata.Resource)
	}
	if len(metadata.AuthorizationServers) != 1 || metadata.AuthorizationServers[0] != "https://issuer.example.com" {
		t.Fatalf("expected authorization server %q, got %v", "https://issuer.example.com", metadata.AuthorizationServers)
	}
}
