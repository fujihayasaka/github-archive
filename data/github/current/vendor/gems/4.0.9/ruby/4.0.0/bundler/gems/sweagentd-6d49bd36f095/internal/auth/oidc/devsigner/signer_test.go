package devsigner

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v4"
)

func mustGenerateRSAKey(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("failed to generate RSA key: %v", err)
	}
	return key
}

func TestTokenIssuer_IssueIDToken(t *testing.T) {
	key := mustGenerateRSAKey(t)
	issuer := NewSigner(key, jwt.SigningMethodRS256, "test-key-1", "https://github.com/login/oauth")

	subject := "agent:copilot:actor_id:42"

	actSubject := "user_id:42"
	tokenStr, err := issuer.IssueIDToken(context.Background(), "client-123", subject, actSubject, map[string]string{"repository": "github/example", "session_id": "123-123"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Parse and verify the token using MapClaims to check top-level additional claims
	parsed, err := jwt.Parse(tokenStr, func(token *jwt.Token) (any, error) {
		return &key.PublicKey, nil
	})
	if err != nil {
		t.Fatalf("failed to parse token: %v", err)
	}

	claims, ok := parsed.Claims.(jwt.MapClaims)
	if !ok {
		t.Fatal("failed to cast claims")
	}

	if claims["iss"] != "https://github.com/login/oauth" {
		t.Errorf("expected issuer %q, got %q", "https://github.com/login/oauth", claims["iss"])
	}
	if claims["aud"] != "client-123" {
		t.Errorf("expected audience %q, got %q", "client-123", claims["aud"])
	}
	if claims["jti"] == nil || claims["jti"] == "" {
		t.Error("expected non-empty JTI")
	}
	if claims["repository"] != "github/example" {
		t.Errorf("expected repository claim %q, got %q", "github/example", claims["repository"])
	}
	if claims["session_id"] != "123-123" {
		t.Errorf("expected session_id claim %q, got %q", "123-123", claims["session_id"])
	}

	// Verify subject
	if claims["sub"] != "agent:copilot:actor_id:42" {
		t.Errorf("expected subject %q, got %q", "agent:copilot:actor_id:42", claims["sub"])
	}

	// Verify act.sub claim
	actClaim, ok := claims["act"].(map[string]any)
	if !ok {
		t.Fatal("expected act claim to be a map")
	}
	if actClaim["sub"] != actSubject {
		t.Errorf("expected act.sub %q, got %q", actSubject, actClaim["sub"])
	}

	// Verify kid header
	if parsed.Header["kid"] != "test-key-1" {
		t.Errorf("expected kid %q, got %q", "test-key-1", parsed.Header["kid"])
	}
}

func TestTokenIssuer_IssueIDToken_ScopeAndResource(t *testing.T) {
	key := mustGenerateRSAKey(t)
	issuer := NewSigner(key, jwt.SigningMethodRS256, "test-key-1", "https://github.com/login/oauth")

	tokenStr, err := issuer.IssueIDToken(context.Background(), "client-123", "sub", "sub", map[string]string{
		"scope":    "read:org",
		"resource": "https://api.example.com",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	parsed, err := jwt.Parse(tokenStr, func(token *jwt.Token) (any, error) {
		return &key.PublicKey, nil
	})
	if err != nil {
		t.Fatalf("failed to parse token: %v", err)
	}

	claims := parsed.Claims.(jwt.MapClaims)
	if claims["scope"] != "read:org" {
		t.Errorf("expected scope %q, got %q", "read:org", claims["scope"])
	}
	if claims["resource"] != "https://api.example.com" {
		t.Errorf("expected resource %q, got %q", "https://api.example.com", claims["resource"])
	}
}

func TestTokenIssuer_IssueIDToken_RejectsUnknownClaims(t *testing.T) {
	key := mustGenerateRSAKey(t)
	issuer := NewSigner(key, jwt.SigningMethodRS256, "test-key-1", "https://github.com/login/oauth")

	_, err := issuer.IssueIDToken(context.Background(), "client-123", "sub", "sub", map[string]string{"forbidden_claim": "value"})
	if err == nil {
		t.Fatal("expected error for unknown claim, got nil")
	}
}

func TestTokenIssuer_IssueIDToken_CustomSubject(t *testing.T) {
	key := mustGenerateRSAKey(t)
	issuer := NewSigner(key, jwt.SigningMethodRS256, "test-key-1", "https://github.com/login/oauth")

	tokenStr, err := issuer.IssueIDToken(context.Background(), "client-123", "my-custom-engine:actor:octocat", "user_id:7", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	parsed, err := jwt.Parse(tokenStr, func(token *jwt.Token) (any, error) {
		return &key.PublicKey, nil
	})
	if err != nil {
		t.Fatalf("failed to parse token: %v", err)
	}

	claims := parsed.Claims.(jwt.MapClaims)
	if claims["sub"] != "my-custom-engine:actor:octocat" {
		t.Errorf("expected sub %q, got %q", "my-custom-engine:actor:octocat", claims["sub"])
	}
}

func TestTokenIssuer_WithTokenExpiry(t *testing.T) {
	key := mustGenerateRSAKey(t)
	expiry := 10 * time.Minute
	issuer := NewSigner(key, jwt.SigningMethodRS256, "k1", "https://issuer", WithTokenExpiry(expiry))

	tokenStr, err := issuer.IssueIDToken(context.Background(), "C", "copilot-swe-agent:actor:user", "copilot-swe-agent:actor:user", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	parsed, err := jwt.Parse(tokenStr, func(token *jwt.Token) (any, error) {
		return &key.PublicKey, nil
	})
	if err != nil {
		t.Fatalf("failed to parse token: %v", err)
	}

	claims := parsed.Claims.(jwt.MapClaims)
	exp := claims["exp"].(float64)
	iat := claims["iat"].(float64)
	diff := time.Duration(exp-iat) * time.Second
	if diff != expiry {
		t.Errorf("expected expiry duration %v, got %v", expiry, diff)
	}
}
