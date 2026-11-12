package oidc

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFetchAuthorizationServerMetadata(t *testing.T) {
	t.Run("successful metadata fetch", func(t *testing.T) {
		meta := AuthorizationServerMetadata{
			Issuer:                "https://auth.example.com",
			TokenEndpoint:         "https://auth.example.com/oauth/token",
			RevocationEndpoint:    "https://auth.example.com/oauth/revoke",
			AuthorizationEndpoint: "https://auth.example.com/oauth/authorize",
			RegistrationEndpoint:  "https://auth.example.com/oauth/register",
			GrantTypesSupported:   []string{"authorization_code", "urn:ietf:params:oauth:grant-type:token-exchange"},
		}

		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			assert.Equal(t, oauthMetadataPath, r.URL.Path)
			assert.Equal(t, "application/json", r.Header.Get("Accept"))
			assert.Equal(t, "2025-03-26", r.Header.Get("MCP-Protocol-Version"))
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(meta)
		}))
		defer srv.Close()

		result, err := FetchAuthorizationServerMetadata(context.Background(), srv.Client(), srv.URL)
		require.NoError(t, err)
		assert.Equal(t, "https://auth.example.com/oauth/token", result.TokenEndpoint)
		assert.Equal(t, "https://auth.example.com/oauth/revoke", result.RevocationEndpoint)
		assert.Equal(t, "https://auth.example.com/oauth/authorize", result.AuthorizationEndpoint)
		assert.Equal(t, "https://auth.example.com/oauth/register", result.RegistrationEndpoint)
		assert.Equal(t, []string{"authorization_code", "urn:ietf:params:oauth:grant-type:token-exchange"}, result.GrantTypesSupported)
	})

	t.Run("server returns 404", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusNotFound)
		}))
		defer srv.Close()

		_, err := FetchAuthorizationServerMetadata(context.Background(), srv.Client(), srv.URL)
		require.Error(t, err)
		assert.True(t, errors.Is(err, ErrMetadataNotFound))
	})

	t.Run("server returns invalid JSON", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.Write([]byte("not json"))
		}))
		defer srv.Close()

		_, err := FetchAuthorizationServerMetadata(context.Background(), srv.Client(), srv.URL)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to parse metadata response")
	})

	t.Run("unreachable server", func(t *testing.T) {
		_, err := FetchAuthorizationServerMetadata(context.Background(), http.DefaultClient, "http://127.0.0.1:1")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "metadata request failed")
	})

	t.Run("does not double-escape encoded issuer path", func(t *testing.T) {
		meta := AuthorizationServerMetadata{
			TokenEndpoint: "https://auth.example.com/oauth/token",
		}

		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			assert.Equal(t, "/.well-known/oauth-authorization-server/tenant/nested", r.URL.Path)
			assert.NotContains(t, r.RequestURI, "%252F")
			w.Header().Set("Content-Type", "application/json")
			err := json.NewEncoder(w).Encode(meta)
			require.NoError(t, err)
		}))
		defer srv.Close()

		result, err := FetchAuthorizationServerMetadata(context.Background(), srv.Client(), srv.URL+"/tenant%2Fnested")
		require.NoError(t, err)
		assert.Equal(t, "https://auth.example.com/oauth/token", result.TokenEndpoint)
	})
}

func TestFetchOAuthProtectedResourceMetadata(t *testing.T) {
	t.Run("uses endpoint-scoped protected resource path first", func(t *testing.T) {
		meta := ProtectedResourceMetadata{
			Resource:             "https://api.example.com",
			AuthorizationServers: []string{"https://auth.example.com", "https://backup-auth.example.com"},
		}

		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			assert.Equal(t, "/.well-known/oauth-protected-resource/public/mcp", r.URL.Path)
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(meta)
		}))
		defer srv.Close()

		result, err := FetchOAuthProtectedResourceMetadata(context.Background(), srv.Client(), srv.URL+"/public/mcp")
		require.NoError(t, err)
		assert.Equal(t, "https://api.example.com", result.Resource)
		assert.Equal(t, []string{"https://auth.example.com", "https://backup-auth.example.com"}, result.AuthorizationServers)
	})

	t.Run("falls back from endpoint-scoped path to root protected resource path", func(t *testing.T) {
		meta := ProtectedResourceMetadata{
			Resource:             "https://api.example.com",
			AuthorizationServers: []string{"https://auth.example.com"},
		}

		var requestedPaths []string
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			requestedPaths = append(requestedPaths, r.URL.Path)

			switch r.URL.Path {
			case "/.well-known/oauth-protected-resource/custom/mcp":
				w.WriteHeader(http.StatusNotFound)
			case "/.well-known/oauth-protected-resource":
				w.Header().Set("Content-Type", "application/json")
				json.NewEncoder(w).Encode(meta)
			default:
				t.Fatalf("unexpected path %q", r.URL.Path)
			}
		}))
		defer srv.Close()

		result, err := FetchOAuthProtectedResourceMetadata(context.Background(), srv.Client(), srv.URL+"/custom/mcp")
		require.NoError(t, err)
		assert.Equal(t, []string{
			"/.well-known/oauth-protected-resource/custom/mcp",
			"/.well-known/oauth-protected-resource",
		}, requestedPaths)
		assert.Equal(t, "https://api.example.com", result.Resource)
		assert.Equal(t, []string{"https://auth.example.com"}, result.AuthorizationServers)
	})

	t.Run("uses only the root protected resource path when the resource URL has no path", func(t *testing.T) {
		meta := ProtectedResourceMetadata{
			Resource:             "https://api.example.com",
			AuthorizationServers: []string{"https://auth.example.com"},
		}

		var requestedPaths []string
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			requestedPaths = append(requestedPaths, r.URL.Path)
			assert.Equal(t, "/.well-known/oauth-protected-resource", r.URL.Path)
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(meta)
		}))
		defer srv.Close()

		result, err := FetchOAuthProtectedResourceMetadata(context.Background(), srv.Client(), srv.URL)
		require.NoError(t, err)
		assert.Equal(t, []string{"/.well-known/oauth-protected-resource"}, requestedPaths)
		assert.Equal(t, []string{"https://auth.example.com"}, result.AuthorizationServers)
	})
}

// metadataServer returns an httptest.Server that serves the given metadata at
// the OAuth well-known path and 404s for everything else.
func metadataServer(t *testing.T, meta AuthorizationServerMetadata) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == oauthMetadataPath {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(meta) //nolint:errchkjson,revive // best-effort write in test helper
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	t.Cleanup(srv.Close)
	return srv
}

// noMetadataServer returns an httptest.Server that always returns 404.
func noMetadataServer(t *testing.T) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestDiscoverConfiguration(t *testing.T) {
	t.Run("populates endpoints from discovered metadata", func(t *testing.T) {
		srv := metadataServer(t, AuthorizationServerMetadata{
			TokenEndpoint:      "https://auth.example.com/oauth/token",
			RevocationEndpoint: "https://auth.example.com/oauth/revoke",
		})
		svc := &Service{httpClient: srv.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{Audience: "aud", Endpoints: oidcconfig.EndpointsConfig{Base: srv.URL}},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Equal(t, "https://auth.example.com/oauth/token", resolved[0].Endpoints.Exchange)
		assert.Equal(t, "https://auth.example.com/oauth/revoke", resolved[0].Endpoints.Revoke)
	})

	t.Run("falls back to base/token when metadata unavailable", func(t *testing.T) {
		srv := noMetadataServer(t)
		svc := &Service{httpClient: srv.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{Audience: "aud", Endpoints: oidcconfig.EndpointsConfig{Base: srv.URL}},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Equal(t, srv.URL+"/token", resolved[0].Endpoints.Exchange)
		assert.Empty(t, resolved[0].Endpoints.Revoke, "no fallback path for revoke")
	})

	t.Run("falls back to normalized base token endpoint when base has trailing slash", func(t *testing.T) {
		srv := noMetadataServer(t)
		svc := &Service{httpClient: srv.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{Audience: "aud", Endpoints: oidcconfig.EndpointsConfig{Base: srv.URL + "/mcp/"}},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Equal(t, srv.URL+"/mcp/token", resolved[0].Endpoints.Exchange)
		assert.Empty(t, resolved[0].Endpoints.Revoke, "no fallback path for revoke")
	})

	t.Run("auto-discovers audience from metadata issuer", func(t *testing.T) {
		srv := metadataServer(t, AuthorizationServerMetadata{
			Issuer:        "https://accounts.example.com",
			TokenEndpoint: "https://auth.example.com/token",
		})
		svc := &Service{httpClient: srv.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{Endpoints: oidcconfig.EndpointsConfig{Base: srv.URL}},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Equal(t, "https://accounts.example.com", resolved[0].Audience)
	})

	t.Run("prefers jwt-bearer grant type over client_credentials", func(t *testing.T) {
		srv := metadataServer(t, AuthorizationServerMetadata{
			TokenEndpoint:      "https://auth.example.com/token",
			RevocationEndpoint: "https://auth.example.com/revoke",
			GrantTypesSupported: []string{
				"authorization_code",
				oidcconfig.GrantTypeTokenExchange,
				oidcconfig.GrantTypeClientCredentials,
				oidcconfig.GrantTypeJWTBearer,
			},
		})
		svc := &Service{httpClient: srv.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{Audience: "aud", Endpoints: oidcconfig.EndpointsConfig{Base: srv.URL}},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Equal(t, oidcconfig.GrantTypeJWTBearer, resolved[0].GrantType)
	})

	t.Run("prefers client_credentials when jwt-bearer not supported", func(t *testing.T) {
		srv := metadataServer(t, AuthorizationServerMetadata{
			TokenEndpoint:      "https://auth.example.com/token",
			RevocationEndpoint: "https://auth.example.com/revoke",
			GrantTypesSupported: []string{
				"authorization_code",
				oidcconfig.GrantTypeTokenExchange,
				oidcconfig.GrantTypeClientCredentials,
			},
		})
		svc := &Service{httpClient: srv.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{Audience: "aud", Endpoints: oidcconfig.EndpointsConfig{Base: srv.URL}},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Equal(t, oidcconfig.GrantTypeClientCredentials, resolved[0].GrantType)
	})

	t.Run("uses token exchange when client_credentials not supported", func(t *testing.T) {
		srv := metadataServer(t, AuthorizationServerMetadata{
			TokenEndpoint: "https://auth.example.com/token",
			GrantTypesSupported: []string{
				oidcconfig.GrantTypeTokenExchange,
			},
		})
		svc := &Service{httpClient: srv.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{Audience: "aud", Endpoints: oidcconfig.EndpointsConfig{Base: srv.URL}},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Equal(t, oidcconfig.GrantTypeTokenExchange, resolved[0].GrantType)
	})

	t.Run("leaves grant type empty when metadata has no supported types", func(t *testing.T) {
		srv := noMetadataServer(t)
		svc := &Service{httpClient: srv.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{Audience: "aud", Endpoints: oidcconfig.EndpointsConfig{Base: srv.URL}},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Empty(t, resolved[0].GrantType)
	})

	t.Run("skips fully resolved entries", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, _ *http.Request) {
			t.Fatal("unexpected request for fully resolved entry")
		}))
		t.Cleanup(srv.Close)
		svc := &Service{httpClient: srv.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{
				Audience:  "aud",
				GrantType: oidcconfig.GrantTypeTokenExchange,
				Endpoints: oidcconfig.EndpointsConfig{
					Base:     srv.URL,
					Exchange: "https://auth.example.com/token",
					Revoke:   "https://auth.example.com/revoke",
				},
			},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Equal(t, "https://auth.example.com/token", resolved[0].Endpoints.Exchange)
		assert.Equal(t, "https://auth.example.com/revoke", resolved[0].Endpoints.Revoke)
	})

	t.Run("preserves explicit exchange endpoint over discovered", func(t *testing.T) {
		srv := metadataServer(t, AuthorizationServerMetadata{
			TokenEndpoint:      "https://auth.example.com/discovered/token",
			RevocationEndpoint: "https://auth.example.com/discovered/revoke",
		})
		svc := &Service{httpClient: srv.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{
				Audience: "aud",
				Endpoints: oidcconfig.EndpointsConfig{
					Base:     srv.URL,
					Exchange: "https://explicit.example.com/token",
				},
			},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Equal(t, "https://explicit.example.com/token", resolved[0].Endpoints.Exchange)
		assert.Equal(t, "https://auth.example.com/discovered/revoke", resolved[0].Endpoints.Revoke, "revoke filled from metadata")
	})

	t.Run("preserves explicit grant type", func(t *testing.T) {
		srv := metadataServer(t, AuthorizationServerMetadata{
			TokenEndpoint:       "https://auth.example.com/token",
			GrantTypesSupported: []string{oidcconfig.GrantTypeClientCredentials},
		})
		svc := &Service{httpClient: srv.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{
				Audience:  "aud",
				GrantType: oidcconfig.GrantTypeTokenExchange,
				Endpoints: oidcconfig.EndpointsConfig{Base: srv.URL},
			},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Equal(t, oidcconfig.GrantTypeTokenExchange, resolved[0].GrantType, "explicit grant type not overridden")
	})
	t.Run("uses protected resource metadata to discover the right auth server metadata", func(t *testing.T) {
		authServer := metadataServer(t, AuthorizationServerMetadata{
			Issuer:             "https://accounts.example.com",
			TokenEndpoint:      "https://accounts.example.com/oauth/token",
			RevocationEndpoint: "https://accounts.example.com/oauth/revoke",
		})

		protectedResourceServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			switch r.URL.Path {
			case "/.well-known/oauth-protected-resource/public/mcp", "/.well-known/oauth-protected-resource":
				w.Header().Set("Content-Type", "application/json")
				err := json.NewEncoder(w).Encode(ProtectedResourceMetadata{
					Resource:             "https://resource.example.com",
					AuthorizationServers: []string{authServer.URL},
				})
				require.NoError(t, err)
			default:
				w.WriteHeader(http.StatusNotFound)
			}
		}))
		defer protectedResourceServer.Close()

		svc := &Service{httpClient: protectedResourceServer.Client(), obsv: observability.NewNoopExporters()}

		entries := []oidcconfig.ConfigEntry{
			{Endpoints: oidcconfig.EndpointsConfig{Base: protectedResourceServer.URL}},
		}
		resolved, err := svc.DiscoverConfiguration(context.Background(), entries)
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Equal(t, "https://accounts.example.com/oauth/token", resolved[0].Endpoints.Exchange)
		assert.Equal(t, "https://accounts.example.com/oauth/revoke", resolved[0].Endpoints.Revoke)
		assert.Equal(t, "https://accounts.example.com", resolved[0].Audience)
	})
}

func TestProtectedResourceMetadataURLsDoesNotDoubleEscapeEncodedPath(t *testing.T) {
	urls, err := protectedResourceMetadataURLs("https://resource.example.com/custom%2Fmcp")
	require.NoError(t, err)
	require.Len(t, urls, 2)
	assert.Equal(t, "https://resource.example.com/.well-known/oauth-protected-resource/custom/mcp", urls[0])
	assert.NotContains(t, urls[0], "%252F")
}
