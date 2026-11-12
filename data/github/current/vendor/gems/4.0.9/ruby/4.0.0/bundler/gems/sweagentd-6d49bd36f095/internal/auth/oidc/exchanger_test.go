package oidc

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/observability"
)

func TestExchanger_ExchangeIDToken_Success(t *testing.T) {
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
		if r.FormValue("grant_type") != oidcconfig.GrantTypeTokenExchange {
			t.Errorf("unexpected grant_type: %q", r.FormValue("grant_type"))
		}
		if r.FormValue("subject_token") != "my-id-token" {
			t.Errorf("unexpected subject_token: %q", r.FormValue("subject_token"))
		}
		if r.FormValue("subject_token_type") != tokenTypeIDToken {
			t.Errorf("unexpected subject_token_type: %q", r.FormValue("subject_token_type"))
		}
		if r.FormValue("audience") != "test-audience" {
			t.Errorf("unexpected audience: %q", r.FormValue("audience"))
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken:     "3p-access-token",
			IssuedTokenType: tokenTypeAccessToken,
			TokenType:       "Bearer",
			ExpiresIn:       3600,
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	resp, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "test-audience", "my-id-token", "", "", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if resp.AccessToken != "3p-access-token" {
		t.Errorf("expected access token %q, got %q", "3p-access-token", resp.AccessToken)
	}
	if resp.TokenType != "Bearer" {
		t.Errorf("expected token type %q, got %q", "Bearer", resp.TokenType)
	}
	if resp.ExpiresIn != 3600 {
		t.Errorf("expected expires_in 3600, got %d", resp.ExpiresIn)
	}
}

func TestExchanger_ExchangeIDToken_AuthorizationRequired(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
			Error:            "authorization_required",
			ErrorDescription: "User must authorize via OAuth",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "c", "t", "", "", "")

	if !errors.Is(err, ErrAuthorizationRequired) {
		t.Fatalf("expected ErrAuthorizationRequired, got: %v", err)
	}
}

func TestExchanger_ExchangeIDToken_UnsupportedGrantType(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
			Error:            "unsupported_grant_type",
			ErrorDescription: "Token exchange not supported",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "c", "t", "", "", "")

	if !errors.Is(err, ErrUnsupportedGrantType) {
		t.Fatalf("expected ErrUnsupportedGrantType, got: %v", err)
	}
	if errors.Is(err, ErrAuthorizationRequired) {
		t.Fatal("should NOT be ErrAuthorizationRequired")
	}
	if errors.Is(err, ErrIDPError) {
		t.Fatal("should NOT be ErrTokenExchangeIDPError")
	}
}

func TestExchanger_ExchangeIDToken_ServerError(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte("internal error"))
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "c", "t", "", "", "")

	if !errors.Is(err, ErrIDPError) {
		t.Fatalf("expected ErrTokenExchangeIDPError, got: %v", err)
	}
}

func TestExchanger_ExchangeIDToken_InvalidGrant(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
			Error:            "invalid_grant",
			ErrorDescription: "token expired",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "c", "t", "", "", "")

	if !errors.Is(err, ErrInvalidGrant) {
		t.Fatalf("expected ErrInvalidGrant, got: %v", err)
	}
}

func TestExchanger_ExchangeIDToken_EmptyAccessToken(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "",
			TokenType:   "Bearer",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "c", "t", "", "", "")

	if !errors.Is(err, ErrIDPError) {
		t.Fatalf("expected ErrTokenExchangeIDPError, got: %v", err)
	}
}

func TestExchanger_ExchangeIDToken_ConnectionError(t *testing.T) {
	exchanger := NewExchanger(&http.Client{}, observability.NewNoopExporters())
	_, err := exchanger.ExchangeIDToken(context.Background(), "http://127.0.0.1:0/bad", "c", "t", "", "", "")

	if !errors.Is(err, ErrNetworkError) {
		t.Fatalf("expected ErrNetworkError, got: %v", err)
	}
}

func TestExchanger_ExchangeIDToken_InvalidURL(t *testing.T) {
	exchanger := NewExchanger(&http.Client{}, observability.NewNoopExporters())

	tests := []struct {
		name     string
		endpoint string
	}{
		{name: "invalid scheme", endpoint: "ftp://example.com/token"},
		{name: "no hostname", endpoint: "https:///token"},
		{name: "http with non-localhost host", endpoint: "http://remote-host.example.com/token"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := exchanger.ExchangeIDToken(context.Background(), tt.endpoint, "aud", "tok", "", "", "")
			if !errors.Is(err, ErrInvalidURL) {
				t.Fatalf("expected ErrInvalidURL, got: %v", err)
			}
		})
	}
}

func TestExchanger_ExchangeIDToken_WithScopeAndResource(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		if r.FormValue("scope") != "read:data write:data" {
			t.Errorf("unexpected scope: %q", r.FormValue("scope"))
		}
		if r.FormValue("resource") != "https://api.example.com" {
			t.Errorf("unexpected resource: %q", r.FormValue("resource"))
		}
		if r.FormValue("grant_type") != oidcconfig.GrantTypeTokenExchange {
			t.Errorf("unexpected grant_type: %q", r.FormValue("grant_type"))
		}
		if r.FormValue("audience") != "test-audience" {
			t.Errorf("unexpected audience: %q", r.FormValue("audience"))
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken:     "scoped-token",
			IssuedTokenType: tokenTypeAccessToken,
			TokenType:       "Bearer",
			ExpiresIn:       3600,
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	resp, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "test-audience", "my-id-token", "read:data write:data", "https://api.example.com", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if resp.AccessToken != "scoped-token" {
		t.Errorf("expected access token %q, got %q", "scoped-token", resp.AccessToken)
	}
}

func TestExchanger_ExchangeIDToken_OmitsEmptyScopeAndResource(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		if r.Form.Has("scope") {
			t.Error("scope should not be present when empty")
		}
		if r.Form.Has("resource") {
			t.Error("resource should not be present when empty")
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "aud", "id-token", "", "", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestExchanger_ExchangeIDToken_WithClientID(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		if r.FormValue("client_id") != "github-agent:copilot-swe-agent" {
			t.Errorf("unexpected client_id: %q", r.FormValue("client_id"))
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token-with-client-id",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	resp, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "aud", "id-token", "", "", "github-agent:copilot-swe-agent")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.AccessToken != "token-with-client-id" {
		t.Errorf("expected access token %q, got %q", "token-with-client-id", resp.AccessToken)
	}
}

func TestExchanger_ExchangeIDToken_OmitsEmptyClientID(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		if r.Form.Has("client_id") {
			t.Error("client_id should not be present when empty")
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "aud", "id-token", "", "", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestExchanger_ExchangeClientCredentials_Success(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		if r.FormValue("grant_type") != oidcconfig.GrantTypeClientCredentials {
			t.Errorf("unexpected grant_type: %q", r.FormValue("grant_type"))
		}
		if r.FormValue("client_assertion_type") != clientAssertionTypeJWTBearer {
			t.Errorf("unexpected client_assertion_type: %q", r.FormValue("client_assertion_type"))
		}
		if r.FormValue("client_assertion") != "my-id-token" {
			t.Errorf("unexpected client_assertion: %q", r.FormValue("client_assertion"))
		}
		if r.FormValue("client_id") != "my-client" {
			t.Errorf("unexpected client_id: %q", r.FormValue("client_id"))
		}
		if r.FormValue("scope") != "api/.default" {
			t.Errorf("unexpected scope: %q", r.FormValue("scope"))
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "azure-access-token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	resp, err := exchanger.ExchangeClientCredentials(context.Background(), svr.URL, "my-id-token", "api/.default", "my-client")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.AccessToken != "azure-access-token" {
		t.Errorf("expected access token %q, got %q", "azure-access-token", resp.AccessToken)
	}
}

func TestExchanger_ExchangeClientCredentials_Error(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
			Error:            "invalid_client",
			ErrorDescription: "bad assertion",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeClientCredentials(context.Background(), svr.URL, "bad-token", "", "client")
	if !errors.Is(err, ErrIDPError) {
		t.Fatalf("expected ErrTokenExchangeIDPError, got: %v", err)
	}
}

func TestExchanger_ExchangeClientCredentials_OmitsEmptyScope(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		if r.Form.Has("scope") {
			t.Error("scope should not be present when empty")
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeClientCredentials(context.Background(), svr.URL, "id-token", "", "client-id")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestExchanger_ExchangeClientCredentials_EmptyAccessToken(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "",
			TokenType:   "Bearer",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeClientCredentials(context.Background(), svr.URL, "tok", "scope", "client")
	if !errors.Is(err, ErrIDPError) {
		t.Fatalf("expected ErrTokenExchangeIDPError, got: %v", err)
	}
}

func TestExchanger_ExchangeClientCredentials_ConnectionError(t *testing.T) {
	exchanger := NewExchanger(&http.Client{}, observability.NewNoopExporters())
	_, err := exchanger.ExchangeClientCredentials(context.Background(), "http://127.0.0.1:0/bad", "tok", "", "client")
	if !errors.Is(err, ErrNetworkError) {
		t.Fatalf("expected ErrNetworkError, got: %v", err)
	}
}

func TestExchanger_ExchangeClientCredentials_InvalidURL(t *testing.T) {
	exchanger := NewExchanger(&http.Client{}, observability.NewNoopExporters())

	tests := []struct {
		name     string
		endpoint string
	}{
		{name: "invalid scheme", endpoint: "ftp://example.com/token"},
		{name: "no hostname", endpoint: "https:///token"},
		{name: "http with non-localhost host", endpoint: "http://remote-host.example.com/token"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := exchanger.ExchangeClientCredentials(context.Background(), tt.endpoint, "tok", "", "client")
			if !errors.Is(err, ErrInvalidURL) {
				t.Fatalf("expected ErrInvalidURL, got: %v", err)
			}
		})
	}
}

func TestExchanger_ExchangeClientCredentials_UnsupportedGrantType(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
			Error:            "unsupported_grant_type",
			ErrorDescription: "Client credentials not supported",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeClientCredentials(context.Background(), svr.URL, "tok", "", "client")

	if !errors.Is(err, ErrUnsupportedGrantType) {
		t.Fatalf("expected ErrUnsupportedGrantType, got: %v", err)
	}
	if errors.Is(err, ErrIDPError) {
		t.Fatal("should NOT be ErrTokenExchangeIDPError")
	}
}

func TestExchanger_ExchangeJWTBearer_Success(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		if r.FormValue("grant_type") != oidcconfig.GrantTypeJWTBearer {
			t.Errorf("unexpected grant_type: %q", r.FormValue("grant_type"))
		}
		if r.FormValue("assertion") != "my-workload-jwt" {
			t.Errorf("unexpected assertion: %q", r.FormValue("assertion"))
		}
		if r.FormValue("scope") != "mcp:read" {
			t.Errorf("unexpected scope: %q", r.FormValue("scope"))
		}
		if r.FormValue("resource") != "https://mcp.example.com" {
			t.Errorf("unexpected resource: %q", r.FormValue("resource"))
		}
		if r.FormValue("audience") != "test-audience" {
			t.Errorf("unexpected audience: %q", r.FormValue("audience"))
		}
		// JWT bearer should NOT include client_id or subject_token fields.
		if r.Form.Has("client_id") {
			t.Error("client_id should not be present in jwt-bearer grant")
		}
		if r.Form.Has("subject_token") {
			t.Error("subject_token should not be present in jwt-bearer grant")
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "wif-access-token",
			TokenType:   "Bearer",
			ExpiresIn:   3600,
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	resp, err := exchanger.ExchangeJWTBearer(context.Background(), svr.URL, "test-audience", "my-workload-jwt", "mcp:read", "https://mcp.example.com")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.AccessToken != "wif-access-token" {
		t.Errorf("expected access token %q, got %q", "wif-access-token", resp.AccessToken)
	}
	if resp.TokenType != "Bearer" {
		t.Errorf("expected token type %q, got %q", "Bearer", resp.TokenType)
	}
}

func TestExchanger_ExchangeJWTBearer_OmitsEmptyScopeAndResource(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		err := r.ParseForm()
		if err != nil {
			t.Fatalf("failed to parse form: %v", err)
		}
		if r.Form.Has("scope") {
			t.Error("scope should not be present when empty")
		}
		if r.Form.Has("resource") {
			t.Error("resource should not be present when empty")
		}
		if r.FormValue("grant_type") != oidcconfig.GrantTypeJWTBearer {
			t.Errorf("unexpected grant_type: %q", r.FormValue("grant_type"))
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ExchangeResponse{
			AccessToken: "token",
			TokenType:   "Bearer",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeJWTBearer(context.Background(), svr.URL, "aud", "jwt", "", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestExchanger_ExchangeJWTBearer_Error(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
			Error:            "invalid_grant",
			ErrorDescription: "JWT expired",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeJWTBearer(context.Background(), svr.URL, "aud", "expired-jwt", "", "")
	if !errors.Is(err, ErrInvalidGrant) {
		t.Fatalf("expected ErrInvalidGrant, got: %v", err)
	}
}

func TestExchanger_HandleExchangeError_ErrorWithDescription(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(exchangeErrorResponse{
			Error:            "invalid_request",
			ErrorDescription: "missing required parameter",
		})
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "aud", "tok", "", "", "")

	if !errors.Is(err, ErrIDPError) {
		t.Fatalf("expected ErrTokenExchangeIDPError, got: %v", err)
	}
	if errMsg := err.Error(); !strings.Contains(errMsg, "invalid_request") || !strings.Contains(errMsg, "missing required parameter") {
		t.Errorf("error message should contain error code and description, got: %s", errMsg)
	}
}

func TestExchanger_HandleExchangeError_ErrorWithoutDescription(t *testing.T) {
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte("access denied"))
	}))
	defer svr.Close()

	exchanger := NewExchanger(svr.Client(), observability.NewNoopExporters())
	_, err := exchanger.ExchangeIDToken(context.Background(), svr.URL, "aud", "tok", "", "", "")

	if !errors.Is(err, ErrIDPError) {
		t.Fatalf("expected ErrTokenExchangeIDPError, got: %v", err)
	}
	if errMsg := err.Error(); !strings.Contains(errMsg, "HTTP 403") {
		t.Errorf("error message should contain HTTP status code, got: %s", errMsg)
	}
}
