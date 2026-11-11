package oidc

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/golang-jwt/jwt/v4"

	"github.com/github/sweagentd/internal/auth/oidc/devsigner"
	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/observability"
)

func newTestExchangeServer(t *testing.T, handler http.HandlerFunc) (*httptest.Server, *Exchanger) {
	t.Helper()
	svr := httptest.NewServer(handler)
	t.Cleanup(svr.Close)
	return svr, NewExchanger(svr.Client(), observability.NewNoopExporters())
}

func newTestRevocationServer(t *testing.T, handler http.HandlerFunc) (*httptest.Server, *Revoker) {
	t.Helper()
	svr := httptest.NewServer(handler)
	t.Cleanup(svr.Close)
	return svr, NewRevoker(svr.Client(), observability.NewNoopExporters())
}

func newTestService(t *testing.T, exchanger *Exchanger, revoker *Revoker) *Service {
	t.Helper()

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("failed to generate RSA key: %v", err)
	}

	obsv := observability.NewNoopExporters()
	issuer := devsigner.NewSigner(key, jwt.SigningMethodRS256, "test-key", "https://issuer")

	return &Service{
		signer:     issuer,
		httpClient: &http.Client{Timeout: httpTimeout},
		exchanger:  exchanger,
		revoker:    revoker,
		obsv:       obsv,
	}
}

func TestProxyFromConfig_UsesConfiguredProxy(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "https://api.example.com/token", http.NoBody)
	proxyURL, err := proxyFromConfig(ServiceConfig{HTTPSProxy: "proxy.example.com:3128"})(req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if proxyURL == nil {
		t.Fatal("expected proxy URL, got nil")
	}
	if got := proxyURL.String(); got != "http://proxy.example.com:3128" {
		t.Fatalf("expected proxy URL %q, got %q", "http://proxy.example.com:3128", got)
	}
}

func TestProxyFromConfig_AlwaysUsesProxy(t *testing.T) {
	// Even requests to .github.net should go through the proxy since NoProxy is no longer supported
	req := httptest.NewRequest(http.MethodGet, "https://api.github.net/token", http.NoBody)
	proxyURL, err := proxyFromConfig(ServiceConfig{HTTPSProxy: "proxy.example.com:3128"})(req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if proxyURL == nil {
		t.Fatal("expected proxy URL, got nil")
	}
	if got := proxyURL.String(); got != "http://proxy.example.com:3128" {
		t.Fatalf("expected proxy URL %q, got %q", "http://proxy.example.com:3128", got)
	}
}

func TestService_ExchangeTokens_Success(t *testing.T) {
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "exchanged-token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	revokeSvr, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "MY_SECRET",
			Audience:     "aud-1",
			Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL, Revoke: revokeSvr.URL},
		},
	}

	params := TokenParams{
		Actor: "octocat",
		Owner: "github",
		Repo:  "example",
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, params)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(result.Secrets) != 1 {
		t.Fatalf("expected 1 secret, got %d", len(result.Secrets))
	}
	if result.Secrets["GITHUB_COPILOT_OIDC_"+"MY_SECRET"] != "exchanged-token" {
		t.Errorf("expected secret value %q, got %q", "exchanged-token", result.Secrets["GITHUB_COPILOT_OIDC_"+"MY_SECRET"])
	}
	if len(result.IssuedTokens) != 1 {
		t.Fatalf("expected 1 issued token, got %d", len(result.IssuedTokens))
	}
	if result.IssuedTokens[0].AccessToken != "exchanged-token" {
		t.Errorf("unexpected access token: %q", result.IssuedTokens[0].AccessToken)
	}
	if result.IssuedTokens[0].RevocationEndpoint != revokeSvr.URL {
		t.Errorf("unexpected revocation endpoint: %q", result.IssuedTokens[0].RevocationEndpoint)
	}
}

func TestService_ExchangeTokens_ExchangeFailure(t *testing.T) {
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
			Error:            "invalid_grant",
			ErrorDescription: "bad token",
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "S",
			Audience:     "C",
			Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL, Failure: "https://example.com/failure"},
		},
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "user"})
	if err == nil {
		t.Fatal("expected ErrPartialSuccess, got nil")
	}
	if !errors.Is(err, ErrPartialSuccess) {
		t.Fatalf("expected ErrPartialSuccess, got: %v", err)
	}
	if len(result.Failures) != 1 {
		t.Fatalf("expected 1 failure, got %d", len(result.Failures))
	}
	f := result.Failures[0]
	if f.ResponseCode != http.StatusUnauthorized {
		t.Errorf("expected response code %d, got %d", http.StatusUnauthorized, f.ResponseCode)
	}
	if f.FailureURL != "https://example.com/failure" {
		t.Errorf("expected failure URL %q, got %q", "https://example.com/failure", f.FailureURL)
	}
	if f.SecretName != "GITHUB_COPILOT_OIDC_S" {
		t.Errorf("expected secret name %q, got %q", "GITHUB_COPILOT_OIDC_S", f.SecretName)
	}
	if f.Message == "" {
		t.Error("expected non-empty failure message")
	}
	// Message should reference the secret name and failure URL
	if !strings.Contains(f.Message, "GITHUB_COPILOT_OIDC_S") {
		t.Errorf("expected message to contain secret reference, got %q", f.Message)
	}
	if !strings.Contains(f.Message, "https://example.com/failure") {
		t.Errorf("expected message to contain failure URL, got %q", f.Message)
	}
}

func TestService_ExchangeTokens_AuthorizationRequired(t *testing.T) {
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusForbidden)
		_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
			Error:            "authorization_required",
			ErrorDescription: "user must authorize",
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "AUTH_S",
			Audience:     "aud",
			Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL, Failure: "https://example.com/auth"},
		},
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "user"})
	if err == nil {
		t.Fatal("expected ErrPartialSuccess, got nil")
	}
	if !errors.Is(err, ErrPartialSuccess) {
		t.Fatalf("expected ErrPartialSuccess, got: %v", err)
	}
	if len(result.Failures) != 1 {
		t.Fatalf("expected 1 failure, got %d", len(result.Failures))
	}
	f := result.Failures[0]
	if f.ResponseCode != http.StatusUnauthorized {
		t.Errorf("expected response code %d, got %d", http.StatusUnauthorized, f.ResponseCode)
	}
	if f.FailureURL != "https://example.com/auth" {
		t.Errorf("expected failure URL %q, got %q", "https://example.com/auth", f.FailureURL)
	}
	// Message should reference the secret name and failure URL
	if !strings.Contains(f.Message, "GITHUB_COPILOT_OIDC_AUTH_S") {
		t.Errorf("expected message to contain secret reference, got %q", f.Message)
	}
	if !strings.Contains(f.Message, "https://example.com/auth") {
		t.Errorf("expected message to contain failure URL, got %q", f.Message)
	}
}

func TestService_ExchangeTokens_PartialFailure(t *testing.T) {
	var callCount atomic.Int32
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		n := callCount.Add(1)
		if n == 1 {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(ExchangeResponse{
				AccessToken: "good-token",
				TokenType:   "Bearer",
			})
		} else {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
				Error:            "invalid_grant",
				ErrorDescription: "bad token",
			})
		}
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{SecretSuffix: "GOOD", Audience: "a", Endpoints: oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL}},
		{SecretSuffix: "BAD", Audience: "b", Endpoints: oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL, Failure: "https://fail.example.com"}},
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "user"})
	if err == nil {
		t.Fatal("expected ErrPartialSuccess, got nil")
	}
	if !errors.Is(err, ErrPartialSuccess) {
		t.Fatalf("expected ErrPartialSuccess, got: %v", err)
	}

	// One entry should succeed and one should fail
	totalSecrets := len(result.Secrets)
	totalFailures := len(result.Failures)
	if totalSecrets+totalFailures != 2 {
		t.Fatalf("expected 2 total results (secrets + failures), got %d + %d", totalSecrets, totalFailures)
	}
	if totalFailures != 1 {
		t.Fatalf("expected 1 failure, got %d", totalFailures)
	}
	if totalSecrets != 1 {
		t.Fatalf("expected 1 secret, got %d", totalSecrets)
	}
}

func TestService_ExchangeTokens_MCPServerFailure(t *testing.T) {
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
			Error:            "server_error",
			ErrorDescription: "internal failure",
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		oidcconfig.NewConfigEntryForMCP("my-mcp-server", "https://example.com/mcp", oidcconfig.ConfigEntry{
			Audience:  "aud",
			Endpoints: oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL, Failure: "https://example.com/fail"},
		}),
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "user"})
	if err == nil {
		t.Fatal("expected ErrPartialSuccess, got nil")
	}
	if !errors.Is(err, ErrPartialSuccess) {
		t.Fatalf("expected ErrPartialSuccess, got: %v", err)
	}
	if len(result.Failures) != 1 {
		t.Fatalf("expected 1 failure, got %d", len(result.Failures))
	}
	f := result.Failures[0]
	if f.ServerName != "my-mcp-server" {
		t.Errorf("expected server name %q, got %q", "my-mcp-server", f.ServerName)
	}
	if f.FailureURL != "https://example.com/fail" {
		t.Errorf("expected failure URL %q, got %q", "https://example.com/fail", f.FailureURL)
	}
	if f.ResponseCode != http.StatusFailedDependency {
		t.Errorf("expected response code %d, got %d", http.StatusFailedDependency, f.ResponseCode)
	}
	// Message should reference the MCP server name
	if !strings.Contains(f.Message, "my-mcp-server") {
		t.Errorf("expected message to contain server name, got %q", f.Message)
	}
}

func TestService_ExchangeTokens_NoWarningWhenHostsMatch(t *testing.T) {
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	exchangeURL, err := url.Parse(exchangeSvr.URL)
	if err != nil {
		t.Fatalf("failed to parse exchange server URL: %v", err)
	}

	entries := []oidcconfig.ConfigEntry{
		oidcconfig.NewConfigEntryForMCP("my-mcp-server", "https://"+exchangeURL.Hostname()+"/mcp", oidcconfig.ConfigEntry{
			Audience:  "aud",
			Endpoints: oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
		}),
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "user"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Warnings) != 0 {
		t.Fatalf("expected 0 warnings, got %d", len(result.Warnings))
	}
}

func TestService_ExchangeTokens_NoWarningForNonMCPEntry(t *testing.T) {
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{{
		SecretSuffix: "SECRET",
		Audience:     "aud",
		Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
	}}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "user"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Warnings) != 0 {
		t.Fatalf("expected 0 warnings, got %d", len(result.Warnings))
	}
}

func TestService_ExchangeTokens_HostMismatchWarning(t *testing.T) {
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		oidcconfig.NewConfigEntryForMCP("my-mcp-server", "https://example.com/mcp", oidcconfig.ConfigEntry{
			Audience:  "aud",
			Endpoints: oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
		}),
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "user"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Warnings) != 1 {
		t.Fatalf("expected 1 warning, got %d", len(result.Warnings))
	}
	warning := result.Warnings[0]
	if !strings.Contains(warning.Message, exchangeSvr.URL) {
		t.Errorf("expected warning to contain exchange endpoint %q, got %q", exchangeSvr.URL, warning.Message)
	}
	if !strings.Contains(warning.Message, "my-mcp-server") {
		t.Errorf("expected warning to contain MCP server name %q, got %q", "my-mcp-server", warning.Message)
	}
	if !strings.Contains(warning.Message, "https://example.com/mcp") {
		t.Errorf("expected warning to contain MCP server URL %q, got %q", "https://example.com/mcp", warning.Message)
	}
	if strings.Contains(warning.Message, "security risk") {
		t.Errorf("expected warning to avoid security risk phrasing, got %q", warning.Message)
	}
	if !strings.Contains(warning.Message, "please verify") {
		t.Errorf("expected warning to include verify guidance, got %q", warning.Message)
	}
}

func TestService_ExchangeTokens_HostMismatchWarningIncludesExchangeAndRevoke(t *testing.T) {
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	revokeSvr, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		oidcconfig.NewConfigEntryForMCP("my-mcp-server", "https://example.com/mcp", oidcconfig.ConfigEntry{
			Audience:  "aud",
			Endpoints: oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL, Revoke: revokeSvr.URL},
		}),
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "user"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Warnings) != 1 {
		t.Fatalf("expected 1 warning, got %d", len(result.Warnings))
	}
	warning := result.Warnings[0]
	if !strings.Contains(warning.Message, exchangeSvr.URL) {
		t.Errorf("expected warning to contain exchange endpoint %q, got %q", exchangeSvr.URL, warning.Message)
	}
	if !strings.Contains(warning.Message, revokeSvr.URL) {
		t.Errorf("expected warning to contain revoke endpoint %q, got %q", revokeSvr.URL, warning.Message)
	}
	if !strings.Contains(warning.Message, "my-mcp-server") {
		t.Errorf("expected warning to contain MCP server name %q, got %q", "my-mcp-server", warning.Message)
	}
	if !strings.Contains(warning.Message, "https://example.com/mcp") {
		t.Errorf("expected warning to contain MCP server URL %q, got %q", "https://example.com/mcp", warning.Message)
	}
	if !strings.Contains(warning.Message, "token exchange endpoint") || !strings.Contains(warning.Message, "token revoke endpoint") {
		t.Errorf("expected warning to list both mismatched endpoint fields, got %q", warning.Message)
	}
	if !strings.Contains(warning.Message, "please verify") {
		t.Errorf("expected warning to include verify guidance, got %q", warning.Message)
	}
}

func TestService_ExchangeTokens_HostMismatchWarningIncludesExchangeRevokeRelationship(t *testing.T) {
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	exchangeURL, err := url.Parse(exchangeSvr.URL)
	if err != nil {
		t.Fatalf("failed to parse exchange server URL: %v", err)
	}

	revokeURL := "https://revoke.example.com/revoke"
	entries := []oidcconfig.ConfigEntry{
		oidcconfig.NewConfigEntryForMCP("my-mcp-server", "https://"+exchangeURL.Hostname()+"/mcp", oidcconfig.ConfigEntry{
			Audience:  "aud",
			Endpoints: oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL, Revoke: revokeURL},
		}),
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "user"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Warnings) != 1 {
		t.Fatalf("expected 1 warning, got %d", len(result.Warnings))
	}
	warning := result.Warnings[0]
	if !strings.Contains(warning.Message, revokeURL) {
		t.Errorf("expected warning to contain revoke endpoint %q, got %q", revokeURL, warning.Message)
	}
	if !strings.Contains(warning.Message, "my-mcp-server") {
		t.Errorf("expected warning to contain MCP server name %q, got %q", "my-mcp-server", warning.Message)
	}
	if strings.Contains(warning.Message, exchangeSvr.URL) {
		t.Errorf("expected warning not to contain matching exchange endpoint %q, got %q", exchangeSvr.URL, warning.Message)
	}
	if !strings.Contains(warning.Message, "token revoke endpoint") {
		t.Errorf("expected warning to mention the mismatched revoke endpoint field, got %q", warning.Message)
	}
	if !strings.Contains(warning.Message, "please verify") {
		t.Errorf("expected warning to include verify guidance, got %q", warning.Message)
	}
	if strings.Contains(warning.Message, "token exchange endpoint") && strings.Contains(warning.Message, "token exchange endpoint (") && strings.Contains(warning.Message, "token revoke endpoint (") {
		// both URLs may appear, but only the mismatched field should be listed in the synthesized field list for this case.
		if strings.Contains(warning.Message, fmt.Sprintf("token exchange endpoint (%q), token revoke endpoint (%q)", exchangeSvr.URL, revokeURL)) {
			t.Errorf("expected warning to only list the mismatched field against the server URL, got %q", warning.Message)
		}
	}
}

func TestVerifyDomainMatch_WarnsForDifferentSubdomainsOnSameRegistrableDomain(t *testing.T) {
	warning := verifyDomainMatch(oidcconfig.NewConfigEntryForMCP(
		"my-mcp-server",
		"https://symmetrical-cod-46pgj7x94pcj9pw-3125.app.github.dev/mcp",
		oidcconfig.ConfigEntry{
			Endpoints: oidcconfig.EndpointsConfig{
				Exchange: "https://symmetrical-cod-46pgj7x94pcj9pw-3124.app.github.dev/token",
			},
		},
	))

	if warning == nil {
		t.Fatal("expected warning for different subdomains on the same registrable domain")
	}
	if !strings.Contains(warning.Message, "3124.app.github.dev/token") {
		t.Fatalf("expected warning to mention mismatched exchange endpoint, got %q", warning.Message)
	}
}

func TestService_ExchangeTokens_MultipleEntries(t *testing.T) {
	var callCount atomic.Int32
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, _ *http.Request) {
		n := callCount.Add(1)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token-" + fmt.Sprint(n),
			TokenType:   "Bearer",
		})
	})
	revokeSvr, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{SecretSuffix: "SECRET_A", Audience: "a", Endpoints: oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL, Revoke: revokeSvr.URL}},
		{SecretSuffix: "SECRET_B", Audience: "b", Endpoints: oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL, Revoke: revokeSvr.URL}},
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "user"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.Secrets) != 2 {
		t.Fatalf("expected 2 secrets, got %d", len(result.Secrets))
	}
	if len(result.IssuedTokens) != 2 {
		t.Fatalf("expected 2 issued tokens, got %d", len(result.IssuedTokens))
	}
}

func TestService_ExchangeTokens_ScopeAndResourceInClaimsAndFormParams(t *testing.T) {
	var receivedScope, receivedResource string
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		receivedScope = r.FormValue("scope")
		receivedResource = r.FormValue("resource")

		// Verify the ID token contains scope and resource claims.
		assertion := r.FormValue("assertion")
		parser := jwt.NewParser(jwt.WithoutClaimsValidation())
		token, _, err := parser.ParseUnverified(assertion, jwt.MapClaims{})
		if err != nil {
			t.Fatalf("failed to parse subject_token JWT: %v", err)
		}
		claims := token.Claims.(jwt.MapClaims)
		if claims["scope"] != "read:data write:data" {
			t.Errorf("expected scope claim %q, got %v", "read:data write:data", claims["scope"])
		}
		if claims["resource"] != "https://api.example.com" {
			t.Errorf("expected resource claim %q, got %v", "https://api.example.com", claims["resource"])
		}
		if claims["session_id"] != "123-123" {
			t.Errorf("expected session_id claim %q, got %v", "123-123", claims["session_id"])
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "scoped-token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "SCOPED",
			Audience:     "aud-1",
			Scope:        "read:data write:data",
			Resource:     "https://api.example.com",
			Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
		},
	}

	params := TokenParams{
		ActorID:   42,
		Actor:     "octocat",
		Owner:     "github",
		Repo:      "example",
		SessionID: "123-123",
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, params)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(result.Secrets) != 1 {
		t.Fatalf("expected 1 secret, got %d", len(result.Secrets))
	}
	if result.Secrets["GITHUB_COPILOT_OIDC_"+"SCOPED"] != "scoped-token" {
		t.Errorf("unexpected secret value: %q", result.Secrets["GITHUB_COPILOT_OIDC_"+"SCOPED"])
	}
	if receivedScope != "read:data write:data" {
		t.Errorf("expected form scope %q, got %q", "read:data write:data", receivedScope)
	}
	if receivedResource != "https://api.example.com" {
		t.Errorf("expected form resource %q, got %q", "https://api.example.com", receivedResource)
	}
}

func TestService_ExchangeTokens_JWTBearerGrant(t *testing.T) {
	var receivedGrantType, receivedAssertion, receivedScope, receivedResource string
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		receivedGrantType = r.FormValue("grant_type")
		receivedAssertion = r.FormValue("assertion")
		receivedScope = r.FormValue("scope")
		receivedResource = r.FormValue("resource")

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "wif-access-token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "WIF_SECRET",
			Audience:     "aud-wif",
			Scope:        "mcp:read",
			Resource:     "https://mcp.example.com",
			GrantType:    oidcconfig.GrantTypeJWTBearer,
			Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
		},
	}

	params := TokenParams{
		Actor: "octocat",
		Owner: "github",
		Repo:  "example",
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, params)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if receivedGrantType != oidcconfig.GrantTypeJWTBearer {
		t.Errorf("expected grant_type %q, got %q", oidcconfig.GrantTypeJWTBearer, receivedGrantType)
	}
	if receivedAssertion == "" {
		t.Error("expected non-empty assertion")
	}
	if receivedScope != "mcp:read" {
		t.Errorf("expected scope %q, got %q", "mcp:read", receivedScope)
	}
	if receivedResource != "https://mcp.example.com" {
		t.Errorf("expected resource %q, got %q", "https://mcp.example.com", receivedResource)
	}

	if len(result.Secrets) != 1 {
		t.Fatalf("expected 1 secret, got %d", len(result.Secrets))
	}
	if result.Secrets["GITHUB_COPILOT_OIDC_WIF_SECRET"] != "wif-access-token" {
		t.Errorf("unexpected secret value: %q", result.Secrets["GITHUB_COPILOT_OIDC_WIF_SECRET"])
	}
}

func TestService_ExchangeTokens_JWTBearerFallsBackToClientCredentials(t *testing.T) {
	var callCount atomic.Int32
	var receivedGrantTypes []string
	var mu sync.Mutex

	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		gt := r.FormValue("grant_type")
		mu.Lock()
		receivedGrantTypes = append(receivedGrantTypes, gt)
		mu.Unlock()

		n := callCount.Add(1)
		if n == 1 {
			// First call (jwt-bearer) → reject with unsupported_grant_type
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
				Error:            "unsupported_grant_type",
				ErrorDescription: "jwt-bearer not supported",
			})
			return
		}
		// Second call (client_credentials) → succeed
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "fallback-token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "S",
			Audience:     "aud",
			ClientID:     "test-client",
			Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
		},
	}

	params := TokenParams{Actor: "octocat"}
	result, err := svc.ExchangeTokens(context.Background(), entries, params)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Secrets["GITHUB_COPILOT_OIDC_S"] != "fallback-token" {
		t.Errorf("expected fallback token, got %q", result.Secrets["GITHUB_COPILOT_OIDC_S"])
	}
	if len(receivedGrantTypes) != 2 {
		t.Fatalf("expected 2 exchange calls, got %d", len(receivedGrantTypes))
	}
	if receivedGrantTypes[0] != oidcconfig.GrantTypeJWTBearer {
		t.Errorf("first call should be jwt-bearer, got %q", receivedGrantTypes[0])
	}
	if receivedGrantTypes[1] != oidcconfig.GrantTypeClientCredentials {
		t.Errorf("second call should be client_credentials, got %q", receivedGrantTypes[1])
	}
}

func TestService_ExchangeTokens_DefaultsToJWTBearer(t *testing.T) {
	var receivedGrantType string
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		receivedGrantType = r.FormValue("grant_type")

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "default-wif-token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	t.Run("no grant type and agent-only subject defaults to jwt-bearer", func(t *testing.T) {
		receivedGrantType = ""
		entries := []oidcconfig.ConfigEntry{
			{
				SecretSuffix:     "S",
				Audience:         "aud",
				Endpoints:        oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
				AgentOnlySubject: true,
			},
		}
		params := TokenParams{ActorID: 42, Actor: "octocat", Owner: "github", OwnerID: 100}
		_, err := svc.ExchangeTokens(context.Background(), entries, params)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if receivedGrantType != oidcconfig.GrantTypeJWTBearer {
			t.Errorf("expected grant_type %q, got %q", oidcconfig.GrantTypeJWTBearer, receivedGrantType)
		}
	})

	t.Run("no grant type and bot actor defaults to jwt-bearer", func(t *testing.T) {
		receivedGrantType = ""
		entries := []oidcconfig.ConfigEntry{
			{
				SecretSuffix: "S",
				Audience:     "aud",
				Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
			},
		}
		params := TokenParams{ActorID: 99, Actor: "dependabot[bot]", Owner: "github", OwnerID: 100}
		_, err := svc.ExchangeTokens(context.Background(), entries, params)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if receivedGrantType != oidcconfig.GrantTypeJWTBearer {
			t.Errorf("expected grant_type %q, got %q", oidcconfig.GrantTypeJWTBearer, receivedGrantType)
		}
	})

	t.Run("no grant type and human actor defaults to jwt-bearer", func(t *testing.T) {
		receivedGrantType = ""
		entries := []oidcconfig.ConfigEntry{
			{
				SecretSuffix: "S",
				Audience:     "aud",
				Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
			},
		}
		params := TokenParams{ActorID: 42, Actor: "octocat", Owner: "github", OwnerID: 100}
		_, err := svc.ExchangeTokens(context.Background(), entries, params)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if receivedGrantType != oidcconfig.GrantTypeJWTBearer {
			t.Errorf("expected grant_type %q, got %q", oidcconfig.GrantTypeJWTBearer, receivedGrantType)
		}
	})

	t.Run("explicit token exchange grant type uses token exchange", func(t *testing.T) {
		receivedGrantType = ""
		entries := []oidcconfig.ConfigEntry{
			{
				SecretSuffix: "S",
				Audience:     "aud",
				GrantType:    oidcconfig.GrantTypeTokenExchange,
				Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
			},
		}
		params := TokenParams{ActorID: 42, Actor: "octocat", Owner: "github", OwnerID: 100}
		_, err := svc.ExchangeTokens(context.Background(), entries, params)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if receivedGrantType != oidcconfig.GrantTypeTokenExchange {
			t.Errorf("expected grant_type %q, got %q", oidcconfig.GrantTypeTokenExchange, receivedGrantType)
		}
	})
}

func TestService_GenerateAccessTokens_SendsClientID(t *testing.T) {
	var receivedClientID string
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		receivedClientID = r.FormValue("client_id")

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "S",
			Audience:     "aud",
			GrantType:    oidcconfig.GrantTypeTokenExchange,
			Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
		},
	}

	t.Run("no entry client ID omits client_id from form", func(t *testing.T) {
		receivedClientID = ""
		params := TokenParams{ActorID: 42, Actor: "octocat"}
		_, err := svc.ExchangeTokens(context.Background(), entries, params)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if receivedClientID != "" {
			t.Errorf("expected empty client_id, got %q", receivedClientID)
		}
	})

	t.Run("params AppClientID does not affect form client_id", func(t *testing.T) {
		receivedClientID = ""
		params := TokenParams{ActorID: 42, Actor: "octocat", AppClientID: "Iv1.custom123"}
		_, err := svc.ExchangeTokens(context.Background(), entries, params)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		// AppClientID on params is used in JWT claims, not in the form client_id field
		if receivedClientID != "" {
			t.Errorf("expected empty client_id, got %q", receivedClientID)
		}
	})
}

func TestService_ExchangeTokens_UsesEntryClientID(t *testing.T) {
	var receivedClientID string
	exchangeSvr, exchanger := newTestExchangeServer(t, func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		receivedClientID = r.FormValue("client_id")

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	})
	_, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "S",
			Audience:     "aud",
			ClientID:     "my-custom-client",
			GrantType:    oidcconfig.GrantTypeTokenExchange,
			Endpoints:    oidcconfig.EndpointsConfig{Exchange: exchangeSvr.URL},
		},
	}

	params := TokenParams{ActorID: 42, Actor: "octocat"}
	_, err := svc.ExchangeTokens(context.Background(), entries, params)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if receivedClientID != "my-custom-client" {
		t.Errorf("expected client_id %q, got %q", "my-custom-client", receivedClientID)
	}
}

func TestService_ExchangeTokens_ResolvesDiscoveryEndpoints(t *testing.T) {
	var receivedExchange bool
	exchangeSvr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		receivedExchange = true
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "discovered-token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	}))
	t.Cleanup(exchangeSvr.Close)

	// Discovery server returns metadata pointing to the exchange server.
	discoverySvr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(AuthorizationServerMetadata{
			TokenEndpoint:      exchangeSvr.URL + "/token",
			RevocationEndpoint: exchangeSvr.URL + "/revoke",
		})
	}))
	t.Cleanup(discoverySvr.Close)

	exchanger := NewExchanger(exchangeSvr.Client(), observability.NewNoopExporters())
	revoker := NewRevoker(&http.Client{}, observability.NewNoopExporters())
	svc := newTestService(t, exchanger, revoker)
	svc.httpClient = discoverySvr.Client()

	entries, err := svc.DiscoverConfiguration(context.Background(), []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "DISC",
			Audience:     "aud",
			Endpoints:    oidcconfig.EndpointsConfig{Base: discoverySvr.URL},
		},
	})
	if err != nil {
		t.Fatalf("unexpected resolution error: %v", err)
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "octocat"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !receivedExchange {
		t.Fatal("expected exchange endpoint to be called")
	}
	if result.Secrets["GITHUB_COPILOT_OIDC_"+"DISC"] != "discovered-token" {
		t.Errorf("expected access token %q, got %q", "discovered-token", result.Secrets["GITHUB_COPILOT_OIDC_"+"DISC"])
	}
}

func TestService_ExchangeTokens_DiscoveryDoesNotOverrideExplicitEndpoints(t *testing.T) {
	var receivedURL string
	exchangeSvr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedURL = r.URL.Path
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	}))
	t.Cleanup(exchangeSvr.Close)

	// Discovery server would point elsewhere, but should not be consulted
	// since both endpoints are explicit.
	discoverySvr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(AuthorizationServerMetadata{
			TokenEndpoint:      "https://should-not-be-used.example.com/token",
			RevocationEndpoint: "https://should-not-be-used.example.com/revoke",
		})
	}))
	t.Cleanup(discoverySvr.Close)

	exchanger := NewExchanger(exchangeSvr.Client(), observability.NewNoopExporters())
	revoker := NewRevoker(&http.Client{}, observability.NewNoopExporters())
	svc := newTestService(t, exchanger, revoker)
	svc.httpClient = discoverySvr.Client()

	entries, err := svc.DiscoverConfiguration(context.Background(), []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "EXPL",
			Audience:     "aud",
			Endpoints:    oidcconfig.EndpointsConfig{Base: discoverySvr.URL, Exchange: exchangeSvr.URL + "/explicit", Revoke: exchangeSvr.URL + "/revoke-explicit"},
		},
	})
	if err != nil {
		t.Fatalf("unexpected resolution error: %v", err)
	}

	_, err = svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "octocat"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if receivedURL != "/explicit" {
		t.Errorf("expected exchange at /explicit, got %q", receivedURL)
	}
}

func TestService_ExchangeTokens_UsesClientCredentialsWhenDiscovered(t *testing.T) {
	var receivedGrantType string
	var receivedClientAssertion string
	exchangeSvr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		receivedGrantType = r.FormValue("grant_type")
		receivedClientAssertion = r.FormValue("client_assertion")

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "azure-token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	}))
	t.Cleanup(exchangeSvr.Close)

	// Discovery server advertises only client_credentials (like Azure AD).
	discoverySvr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(AuthorizationServerMetadata{
			TokenEndpoint:       exchangeSvr.URL + "/token",
			GrantTypesSupported: []string{"client_credentials"},
		})
	}))
	t.Cleanup(discoverySvr.Close)

	exchanger := NewExchanger(exchangeSvr.Client(), observability.NewNoopExporters())
	revoker := NewRevoker(&http.Client{}, observability.NewNoopExporters())
	svc := newTestService(t, exchanger, revoker)
	svc.httpClient = discoverySvr.Client()

	entries, err := svc.DiscoverConfiguration(context.Background(), []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "AZURE",
			Audience:     "api://AzureADTokenExchange",
			Scope:        "api/.default",
			ClientID:     "my-azure-client",
			Endpoints:    oidcconfig.EndpointsConfig{Base: discoverySvr.URL},
		},
	})
	if err != nil {
		t.Fatalf("unexpected resolution error: %v", err)
	}

	result, err := svc.ExchangeTokens(context.Background(), entries, TokenParams{Actor: "octocat"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if receivedGrantType != "client_credentials" {
		t.Errorf("expected grant_type %q, got %q", "client_credentials", receivedGrantType)
	}
	if receivedClientAssertion == "" {
		t.Error("expected client_assertion to be set")
	}
	if result.Secrets["GITHUB_COPILOT_OIDC_"+"AZURE"] != "azure-token" {
		t.Errorf("expected access token %q, got %q", "azure-token", result.Secrets["GITHUB_COPILOT_OIDC_"+"AZURE"])
	}
}

func TestService_RevokeAccessTokens_Success(t *testing.T) {
	var revoked atomic.Int32
	revokeSvr, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		revoked.Add(1)
		w.WriteHeader(http.StatusOK)
	})
	exchanger := NewExchanger(&http.Client{}, observability.NewNoopExporters())
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{SecretSuffix: "A", Audience: "c-a", Endpoints: oidcconfig.EndpointsConfig{Exchange: "https://example.com/exchange", Revoke: revokeSvr.URL}},
		{SecretSuffix: "B", Audience: "c-b", Endpoints: oidcconfig.EndpointsConfig{Exchange: "https://example.com/exchange", Revoke: revokeSvr.URL}},
	}

	tokens := map[string]string{
		"GITHUB_COPILOT_OIDC_" + "A": "at-a",
		"GITHUB_COPILOT_OIDC_" + "B": "at-b",
	}

	err := svc.RevokeAccessTokens(context.Background(), tokens, entries, TokenParams{Actor: "octocat"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if revoked.Load() != 2 {
		t.Errorf("expected 2 revocation calls, got %d", revoked.Load())
	}
}

func TestService_RevokeAccessTokens_SkipsEmptyEndpoint(t *testing.T) {
	_, revoker := newTestRevocationServer(t, func(_ http.ResponseWriter, _ *http.Request) {
		t.Error("revocation should not be called for empty endpoint")
	})
	exchanger := NewExchanger(&http.Client{}, observability.NewNoopExporters())
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{SecretSuffix: "A", Audience: "c-a", Endpoints: oidcconfig.EndpointsConfig{Exchange: "https://example.com/exchange"}},
	}

	tokens := map[string]string{
		"GITHUB_COPILOT_OIDC_" + "A": "at-a",
	}

	err := svc.RevokeAccessTokens(context.Background(), tokens, entries, TokenParams{Actor: "user"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestService_RevokeAccessTokens_ContinuesOnError(t *testing.T) {
	var callCount atomic.Int32
	revokeSvr, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, _ *http.Request) {
		n := callCount.Add(1)
		if n == 1 {
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write([]byte("server error"))
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	exchanger := NewExchanger(&http.Client{}, observability.NewNoopExporters())
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{SecretSuffix: "FAIL", Audience: "c-fail", Endpoints: oidcconfig.EndpointsConfig{Exchange: "https://example.com/exchange", Revoke: revokeSvr.URL}},
		{SecretSuffix: "OK", Audience: "c-ok", Endpoints: oidcconfig.EndpointsConfig{Exchange: "https://example.com/exchange", Revoke: revokeSvr.URL}},
	}

	tokens := map[string]string{
		"GITHUB_COPILOT_OIDC_" + "FAIL": "at-fail",
		"GITHUB_COPILOT_OIDC_" + "OK":   "at-ok",
	}

	err := svc.RevokeAccessTokens(context.Background(), tokens, entries, TokenParams{Actor: "user"})
	// Should return an error but still process all tokens
	if err == nil {
		t.Fatal("expected error from revocation failure")
	}
	if callCount.Load() != 2 {
		t.Errorf("expected 2 revocation calls (best-effort), got %d", callCount.Load())
	}
}

func TestService_RevokeAccessTokens_SkipsUnmatchedTokens(t *testing.T) {
	_, revoker := newTestRevocationServer(t, func(_ http.ResponseWriter, _ *http.Request) {
		t.Error("revocation should not be called for unmatched tokens")
	})
	exchanger := NewExchanger(&http.Client{}, observability.NewNoopExporters())
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{SecretSuffix: "A", Audience: "c-a", Endpoints: oidcconfig.EndpointsConfig{Exchange: "https://example.com/exchange", Revoke: "https://example.com/revoke"}},
	}

	// Token key doesn't match any config entry
	tokens := map[string]string{
		"GITHUB_COPILOT_OIDC_" + "UNKNOWN": "at-unknown",
	}

	err := svc.RevokeAccessTokens(context.Background(), tokens, entries, TokenParams{Actor: "user"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestService_RevokeAccessTokens_ResolvesDiscoveryEndpoints(t *testing.T) {
	var receivedRevoke bool
	revokeSvr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		receivedRevoke = true
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(revokeSvr.Close)

	discoverySvr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(AuthorizationServerMetadata{
			TokenEndpoint:      revokeSvr.URL + "/token",
			RevocationEndpoint: revokeSvr.URL + "/revoke",
		})
	}))
	t.Cleanup(discoverySvr.Close)

	exchanger := NewExchanger(&http.Client{}, observability.NewNoopExporters())
	revoker := NewRevoker(revokeSvr.Client(), observability.NewNoopExporters())
	svc := newTestService(t, exchanger, revoker)
	svc.httpClient = discoverySvr.Client()

	entries, err := svc.DiscoverConfiguration(context.Background(), []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "DISC",
			Audience:     "aud",
			Endpoints:    oidcconfig.EndpointsConfig{Base: discoverySvr.URL},
		},
	})
	if err != nil {
		t.Fatalf("unexpected resolution error: %v", err)
	}

	tokens := map[string]string{
		"GITHUB_COPILOT_OIDC_" + "DISC": "at-disc",
	}

	err = svc.RevokeAccessTokens(context.Background(), tokens, entries, TokenParams{Actor: "octocat"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !receivedRevoke {
		t.Fatal("expected revocation endpoint to be called")
	}
}

func TestService_RevokeAccessTokens_UsesEntryClientID(t *testing.T) {
	var receivedClientID string
	revokeSvr, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		receivedClientID = r.FormValue("client_id")
		w.WriteHeader(http.StatusOK)
	})
	exchanger := NewExchanger(&http.Client{}, observability.NewNoopExporters())
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{
			SecretSuffix: "A",
			Audience:     "c-a",
			ClientID:     "entry-level-client",
			Endpoints:    oidcconfig.EndpointsConfig{Exchange: "https://example.com/exchange", Revoke: revokeSvr.URL},
		},
	}

	tokens := map[string]string{
		"GITHUB_COPILOT_OIDC_" + "A": "at-a",
	}

	err := svc.RevokeAccessTokens(context.Background(), tokens, entries, TokenParams{Actor: "octocat"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if receivedClientID != "entry-level-client" {
		t.Errorf("expected client_id %q, got %q", "entry-level-client", receivedClientID)
	}
}

func TestService_RevokeAccessTokens_SendsClientID(t *testing.T) {
	var receivedClientID string
	revokeSvr, revoker := newTestRevocationServer(t, func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		receivedClientID = r.FormValue("client_id")
		w.WriteHeader(http.StatusOK)
	})
	exchanger := NewExchanger(&http.Client{}, observability.NewNoopExporters())
	svc := newTestService(t, exchanger, revoker)

	entries := []oidcconfig.ConfigEntry{
		{SecretSuffix: "A", Audience: "c-a", Endpoints: oidcconfig.EndpointsConfig{Exchange: "https://example.com/exchange", Revoke: revokeSvr.URL}},
	}

	tokens := map[string]string{
		"GITHUB_COPILOT_OIDC_" + "A": "at-a",
	}

	err := svc.RevokeAccessTokens(context.Background(), tokens, entries, TokenParams{Actor: "octocat"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if receivedClientID != "" {
		t.Errorf("expected empty client_id when entry has no ClientID, got %q", receivedClientID)
	}
}

func Test_newExchangeFailure(t *testing.T) {
	secretEntry := oidcconfig.ConfigEntry{
		SecretSuffix: "MY_SECRET",
		Audience:     "aud",
		Endpoints:    oidcconfig.EndpointsConfig{Failure: "https://example.com/fail"},
	}
	mcpEntry := oidcconfig.NewConfigEntryForMCP("my-mcp-server", "https://mcp.example.com",
		oidcconfig.ConfigEntry{
			Audience:  "aud",
			Endpoints: oidcconfig.EndpointsConfig{Failure: "https://example.com/mcp-fail"},
		})
	secretEntryNoFailure := oidcconfig.ConfigEntry{
		SecretSuffix: "NO_FAIL",
		Audience:     "aud",
	}

	tests := []struct {
		name            string
		entry           oidcconfig.ConfigEntry
		err             error
		wantNil         bool
		wantCode        int
		wantMsgContains []string
		wantSecretName  string
		wantServerName  string
		wantFailureURL  string
		wantErrContains string
	}{
		{
			name:    "nil error returns nil",
			entry:   secretEntry,
			err:     nil,
			wantNil: true,
		},
		{
			name:            "ErrUnsupportedGrantType returns 400",
			entry:           secretEntry,
			err:             fmt.Errorf("%w: bad grant", ErrUnsupportedGrantType),
			wantCode:        http.StatusBadRequest,
			wantMsgContains: []string{"invalid grant type", "GITHUB_COPILOT_OIDC_MY_SECRET"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_MY_SECRET",
			wantFailureURL:  "https://example.com/fail",
			wantErrContains: "GITHUB_COPILOT_OIDC_MY_SECRET",
		},
		{
			name:            "ErrUnableToDetermineGrantType returns 400",
			entry:           secretEntry,
			err:             fmt.Errorf("%w: dunno", ErrUnableToDetermineGrantType),
			wantCode:        http.StatusBadRequest,
			wantMsgContains: []string{"unable to determine", "GITHUB_COPILOT_OIDC_MY_SECRET"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_MY_SECRET",
			wantFailureURL:  "https://example.com/fail",
		},
		{
			name:            "ErrInvalidConfig returns 400",
			entry:           secretEntry,
			err:             fmt.Errorf("%w: bad config", oidcconfig.ErrInvalidConfig),
			wantCode:        http.StatusBadRequest,
			wantMsgContains: []string{"configuration", "invalid", "GITHUB_COPILOT_OIDC_MY_SECRET"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_MY_SECRET",
			wantFailureURL:  "https://example.com/fail",
		},
		{
			name:            "ErrInvalidURL returns 400",
			entry:           secretEntry,
			err:             fmt.Errorf("%w: bad url", ErrInvalidURL),
			wantCode:        http.StatusBadRequest,
			wantMsgContains: []string{"invalid URL", "GITHUB_COPILOT_OIDC_MY_SECRET"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_MY_SECRET",
			wantFailureURL:  "https://example.com/fail",
		},
		{
			name:            "ErrMetadataNotFound returns 404",
			entry:           secretEntry,
			err:             fmt.Errorf("%w: not found", ErrMetadataNotFound),
			wantCode:        http.StatusNotFound,
			wantMsgContains: []string{"endpoints", "GITHUB_COPILOT_OIDC_MY_SECRET"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_MY_SECRET",
			wantFailureURL:  "https://example.com/fail",
		},
		{
			name:            "ErrAuthorizationRequired with failure URL returns 401 with URL in message",
			entry:           secretEntry,
			err:             fmt.Errorf("%w: need auth", ErrAuthorizationRequired),
			wantCode:        http.StatusUnauthorized,
			wantMsgContains: []string{"GITHUB_COPILOT_OIDC_MY_SECRET", "https://example.com/fail"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_MY_SECRET",
			wantFailureURL:  "https://example.com/fail",
		},
		{
			name:            "ErrAuthorizationRequired without failure URL returns 401 without URL",
			entry:           secretEntryNoFailure,
			err:             fmt.Errorf("%w: need auth", ErrAuthorizationRequired),
			wantCode:        http.StatusUnauthorized,
			wantMsgContains: []string{"GITHUB_COPILOT_OIDC_NO_FAIL"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_NO_FAIL",
		},
		{
			name:            "ErrInvalidGrant with failure URL returns 401 with URL in message",
			entry:           secretEntry,
			err:             fmt.Errorf("%w: expired", ErrInvalidGrant),
			wantCode:        http.StatusUnauthorized,
			wantMsgContains: []string{"Invalid grant", "GITHUB_COPILOT_OIDC_MY_SECRET", "https://example.com/fail"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_MY_SECRET",
			wantFailureURL:  "https://example.com/fail",
		},
		{
			name:            "ErrInvalidGrant without failure URL returns 401 without URL",
			entry:           secretEntryNoFailure,
			err:             fmt.Errorf("%w: expired", ErrInvalidGrant),
			wantCode:        http.StatusUnauthorized,
			wantMsgContains: []string{"Invalid grant", "GITHUB_COPILOT_OIDC_NO_FAIL"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_NO_FAIL",
		},
		{
			name:            "ErrIDPError returns 424",
			entry:           secretEntry,
			err:             fmt.Errorf("%w: bad response", ErrIDPError),
			wantCode:        http.StatusFailedDependency,
			wantMsgContains: []string{"unexpected response", "GITHUB_COPILOT_OIDC_MY_SECRET"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_MY_SECRET",
			wantFailureURL:  "https://example.com/fail",
		},
		{
			name:            "ErrNetworkError returns 502",
			entry:           secretEntry,
			err:             fmt.Errorf("%w: timeout", ErrNetworkError),
			wantCode:        http.StatusBadGateway,
			wantMsgContains: []string{"network error", "GITHUB_COPILOT_OIDC_MY_SECRET"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_MY_SECRET",
			wantFailureURL:  "https://example.com/fail",
		},
		{
			name:            "unknown error returns 500",
			entry:           secretEntry,
			err:             errors.New("something weird"),
			wantCode:        http.StatusInternalServerError,
			wantMsgContains: []string{"unexpected error", "GITHUB_COPILOT_OIDC_MY_SECRET"},
			wantSecretName:  "GITHUB_COPILOT_OIDC_MY_SECRET",
			wantFailureURL:  "https://example.com/fail",
		},
		{
			name:            "MCP entry uses server name as reference",
			entry:           mcpEntry,
			err:             fmt.Errorf("%w: bad response", ErrIDPError),
			wantCode:        http.StatusFailedDependency,
			wantMsgContains: []string{"my-mcp-server"},
			wantServerName:  "my-mcp-server",
			wantFailureURL:  "https://example.com/mcp-fail",
			wantErrContains: "my-mcp-server",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := newExchangeFailure(tt.entry, tt.err)
			if tt.wantNil {
				if got != nil {
					t.Fatalf("expected nil, got %+v", got)
				}
				return
			}
			if got == nil {
				t.Fatal("expected non-nil ExchangeFailure")
			}
			if got.ResponseCode != tt.wantCode {
				t.Errorf("ResponseCode: got %d, want %d", got.ResponseCode, tt.wantCode)
			}
			for _, substr := range tt.wantMsgContains {
				if !strings.Contains(got.Message, substr) {
					t.Errorf("Message %q missing expected substring %q", got.Message, substr)
				}
			}
			if tt.wantSecretName != "" && got.SecretName != tt.wantSecretName {
				t.Errorf("SecretName: got %q, want %q", got.SecretName, tt.wantSecretName)
			}
			if tt.wantServerName != "" && got.ServerName != tt.wantServerName {
				t.Errorf("ServerName: got %q, want %q", got.ServerName, tt.wantServerName)
			}
			if got.FailureURL != tt.wantFailureURL {
				t.Errorf("FailureURL: got %q, want %q", got.FailureURL, tt.wantFailureURL)
			}
			if tt.wantErrContains != "" && !strings.Contains(got.Error, tt.wantErrContains) {
				t.Errorf("Error %q missing expected substring %q", got.Error, tt.wantErrContains)
			}
			// Error field should always contain the reference in brackets
			if got.Error == "" {
				t.Error("expected non-empty Error field")
			}
		})
	}
}
