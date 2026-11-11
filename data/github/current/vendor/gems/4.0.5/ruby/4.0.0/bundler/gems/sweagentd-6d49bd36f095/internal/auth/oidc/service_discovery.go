package oidc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/github/go-stats"

	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/goerrors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"golang.org/x/sync/errgroup"
)

const (
	// oauthMetadataPath is the well-known path for OAuth 2.0 Authorization Server
	// Metadata as defined by RFC 8414 and the MCP protocol specification.
	oauthMetadataPath = "/.well-known/oauth-authorization-server"

	// openIDConfigPath is the well-known path for OpenID Connect Discovery 1.0
	// configuration metadata.
	openIDConfigPath = "/.well-known/openid-configuration"

	// oauthProtectedResourceRootPath is the RFC 9728 well-known path for OAuth 2.0
	// protected resource metadata.
	oauthProtectedResourceRootPath = "/.well-known/oauth-protected-resource"

	// discoveryTimeout limits how long a single discovery flow may take unless the
	// caller has already provided a sooner deadline.
	discoveryTimeout = 10 * time.Second

	// discoveryConcurrencyLimit limits the number of concurrent discovery flows.
	discoveryConcurrencyLimit = 8
)

func withDiscoveryDeadline(ctx context.Context) (context.Context, context.CancelFunc) {
	deadline := time.Now().Add(discoveryTimeout)
	if existingDeadline, ok := ctx.Deadline(); ok && !deadline.Before(existingDeadline) {
		return ctx, func() {}
	}
	return context.WithDeadline(ctx, deadline)
}

// AuthorizationServerMetadata represents the subset of RFC 8414 fields that
// are relevant for OIDC token exchange endpoint discovery.
type AuthorizationServerMetadata struct {
	Issuer                string   `json:"issuer"`
	TokenEndpoint         string   `json:"token_endpoint"`
	RevocationEndpoint    string   `json:"revocation_endpoint"`
	AuthorizationEndpoint string   `json:"authorization_endpoint"`
	RegistrationEndpoint  string   `json:"registration_endpoint"`
	GrantTypesSupported   []string `json:"grant_types_supported"`
}

// ProtectedResourceMetadata represents the subset of RFC 9728 protected
// resource metadata relevant for OIDC token exchange endpoint discovery.
type ProtectedResourceMetadata struct {
	Resource               string   `json:"resource"`
	AuthorizationServers   []string `json:"authorization_servers"`
	BearerMethodsSupported []string `json:"bearer_methods_supported"`
	ScopesSupported        []string `json:"scopes_supported"`
	ResourceDocumentation  string   `json:"resource_documentation"`
}

// SupportsTokenExchange reports whether the authorization server advertises
// support for RFC 8693 token exchange. Returns false if grant_types_supported is
// absent or empty, which generally means the default autodetection logic will be used.
func (m *AuthorizationServerMetadata) SupportsTokenExchange() bool {
	return slices.Contains(m.GrantTypesSupported, oidcconfig.GrantTypeTokenExchange)
}

// SupportsClientCredentials reports whether the authorization server advertises
// support for the client_credentials grant type (used by Azure AD workload
// identity federation). Returns false if grant_types_supported is
// absent or empty, which generally means the default autodetection logic will be used.
func (m *AuthorizationServerMetadata) SupportsClientCredentials() bool {
	return slices.Contains(m.GrantTypesSupported, oidcconfig.GrantTypeClientCredentials)
}

// SupportsJWTBearer reports whether the authorization server advertises
// support for the RFC 7523 JWT Bearer grant type (used for workload identity
// federation). Returns false if grant_types_supported is absent or empty.
func (m *AuthorizationServerMetadata) SupportsJWTBearer() bool {
	return slices.Contains(m.GrantTypesSupported, oidcconfig.GrantTypeJWTBearer)
}

// FetchAuthorizationServerMetadata fetches OAuth/OIDC metadata from the given
// base URL. This follows the rules detailed in the MCP spec on RFC8414 Section 3.1 “Authorization Server Metadata Request” for OAuth 2.0 Authorization Server Metadata discovery
// and RFC8414 Section 5 “Compatibility Notes” for OpenID Connect Discovery 1.0 interoperability.
// Rules in order are inlined in the code for clarity.
func FetchAuthorizationServerMetadata(ctx context.Context, client *http.Client, baseURL string) (*AuthorizationServerMetadata, error) {
	ctx, cancel := withDiscoveryDeadline(ctx)
	defer cancel()

	sanitizedURL, err := sanitizeURL(baseURL)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse base URL: %w", err)
	}

	base := &url.URL{Scheme: sanitizedURL.Scheme, Host: sanitizedURL.Host}
	path := strings.TrimPrefix(sanitizedURL.Path, "/")

	candidates := []string{
		// 1. OAuth 2.0 Authorization Server Metadata with path insertion: https://auth.example.com/.well-known/oauth-authorization-server/tenant1
		base.JoinPath(oauthMetadataPath, path).String(),
		// 2. OpenID Connect Discovery 1.0 with path insertion: https://auth.example.com/.well-known/openid-configuration/tenant1
		base.JoinPath(openIDConfigPath, path).String(),
		// 3. OpenID Connect Discovery 1.0 path appending: https://auth.example.com/tenant1/.well-known/openid-configuration
		base.JoinPath(path, openIDConfigPath).String(),

		// For issuer URLs without path components (e.g., https://auth.example.com)
		// 4. OAuth 2.0 Authorization Server Metadata: https://auth.example.com/.well-known/oauth-authorization-server
		base.JoinPath(oauthMetadataPath).String(),
		// 5. OpenID Connect Discovery 1.0: https://auth.example.com/.well-known/openid-configuration
		base.JoinPath(openIDConfigPath).String(),
	}

	for _, u := range candidates {
		meta, err := fetchMetadataFromURL(ctx, client, u)
		if err == nil {
			return meta, nil
		}
		if !errors.Is(err, ErrMetadataNotFound) {
			return nil, err
		}
	}
	return nil, ErrMetadataNotFound
}

// fetchMetadataFromURL performs an HTTP GET against the given metadata URL and
// decodes the response into AuthorizationServerMetadata.
func fetchMetadataFromURL(ctx context.Context, client *http.Client, metadataURL string) (*AuthorizationServerMetadata, error) {
	ctx, cancel := withDiscoveryDeadline(ctx)
	defer cancel()

	url, err := sanitizeURL(metadataURL)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse metadata URL: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url.String(), http.NoBody)
	if err != nil {
		return nil, goerrors.Errorf("failed to create metadata request: %w", err)
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("MCP-Protocol-Version", "2025-03-26")

	resp, err := client.Do(req) //nolint:gosec // URL is sanitized before use.
	if err != nil {
		return nil, goerrors.Errorf("metadata request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, ErrMetadataNotFound
	} else if resp.StatusCode != http.StatusOK {
		return nil, goerrors.Errorf("metadata endpoint returned HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, goerrors.Errorf("failed to read metadata response: %w", err)
	}

	var meta AuthorizationServerMetadata
	err = json.Unmarshal(body, &meta)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse metadata response: %w", err)
	}

	return &meta, nil
}

func discoverAuthorizationServerMetadata(ctx context.Context, client *http.Client, baseURL string) (*AuthorizationServerMetadata, error) {
	ctx, cancel := withDiscoveryDeadline(ctx)
	defer cancel()

	meta, err := FetchAuthorizationServerMetadata(ctx, client, baseURL)
	if err == nil {
		return meta, nil
	}
	if !errors.Is(err, ErrMetadataNotFound) {
		return nil, err
	}

	protectedResourceMeta, err := FetchOAuthProtectedResourceMetadata(ctx, client, baseURL)
	if err != nil {
		if errors.Is(err, ErrMetadataNotFound) {
			return nil, ErrMetadataNotFound
		}
		return nil, err
	}
	if len(protectedResourceMeta.AuthorizationServers) == 0 {
		return nil, ErrMetadataNotFound
	}

	return FetchAuthorizationServerMetadata(ctx, client, protectedResourceMeta.AuthorizationServers[0])
}

// DiscoverConfiguration returns a copy of entries with endpoints populated
// from the base URL via metadata discovery when explicit endpoints are missing.
// Entries without a base URL or that already have both endpoints are returned
// unchanged. The resolved grant type is also set based on discovered metadata:
// JWT Bearer is preferred if supported, then client_credentials, then RFC 8693
// ID token exchange.
func (s *Service) DiscoverConfiguration(ctx context.Context, entries []oidcconfig.ConfigEntry) ([]oidcconfig.ConfigEntry, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "oidc.Service.DiscoverConfiguration")
	defer span.End()
	span.SetAttributes(attribute.Int("oidc.entry_count", len(entries)))

	resolved := make([]oidcconfig.ConfigEntry, len(entries))
	copy(resolved, entries)

	eg, gctx := errgroup.WithContext(ctx)
	eg.SetLimit(discoveryConcurrencyLimit)

	for i, entry := range resolved {
		eg.Go(func() error {
			if entry.Endpoints.Exchange != "" && entry.Endpoints.Revoke != "" && entry.GrantType != "" && entry.Audience != "" {
				s.recordDiscoveryMetrics(gctx, "skipped", 0)
				return nil
			}

			meta := &AuthorizationServerMetadata{}
			var err error

			if entry.Endpoints.Base != "" {
				start := time.Now()
				discoverCtx, discoverSpan := s.obsv.Tracer.Start(gctx, "oidc.Service.DiscoverConfiguration.discoverAuthorizationServerMetadata")
				meta, err = discoverAuthorizationServerMetadata(discoverCtx, s.oidcHTTPClient(), entry.Endpoints.Base)
				if err != nil {
					if errors.Is(err, ErrMetadataNotFound) {
						s.recordDiscoveryMetrics(gctx, "not_found", time.Since(start))
					} else {
						s.recordDiscoveryMetrics(gctx, "error", time.Since(start))
						s.obsv.Logger.WithContext(gctx).Info(fmt.Sprintf("endpoint discovery failed for %q: %v", entry.SecretSuffix, err))
						discoverSpan.RecordError(err)
						discoverSpan.SetStatus(codes.Error, err.Error())
					}

					meta = &AuthorizationServerMetadata{}
				} else {
					s.recordDiscoveryMetrics(gctx, "success", time.Since(start))
				}
				discoverSpan.End()
			}

			if entry.Endpoints.Exchange == "" {
				if meta.TokenEndpoint != "" {
					resolved[i].Endpoints.Exchange = meta.TokenEndpoint
				} else if resolved[i].Endpoints.Base != "" {
					resolved[i].Endpoints.Exchange, err = url.JoinPath(resolved[i].Endpoints.Base, "token")
					if err != nil {
						s.obsv.Logger.WithContext(gctx).Info(fmt.Sprintf("failed to construct token endpoint URL for %q: %v", entry.SecretSuffix, err))
						return goerrors.Errorf("failed to construct token endpoint URL: %w", err)
					}
				}
			}
			// Revocation is optional
			if entry.Endpoints.Revoke == "" {
				if meta.RevocationEndpoint != "" {
					resolved[i].Endpoints.Revoke = meta.RevocationEndpoint
				}
			}
			if entry.Audience == "" && meta.Issuer != "" {
				resolved[i].Audience = meta.Issuer
			}

			// Determine the grant type from discovered metadata when not
			// explicitly configured.
			if resolved[i].GrantType == "" {
				switch {
				case meta.SupportsJWTBearer():
					resolved[i].GrantType = oidcconfig.GrantTypeJWTBearer
				case meta.SupportsClientCredentials():
					resolved[i].GrantType = oidcconfig.GrantTypeClientCredentials
				case meta.SupportsTokenExchange():
					resolved[i].GrantType = oidcconfig.GrantTypeTokenExchange
				default:
					// Do nothing which will try one way and then do another
				}
			}

			return nil
		})
	}

	err := eg.Wait()
	if err != nil {
		return nil, err
	}

	return resolved, nil
}

func (s *Service) recordDiscoveryMetrics(ctx context.Context, status string, duration time.Duration) {
	tags := stats.Tags{"status": status}
	s.obsv.Increment(ctx, "oidc.discovery.count", tags)
	if duration > 0 {
		s.obsv.DistributionMs(ctx, "oidc.discovery.latency_ms", tags, duration)
	}
}

func protectedResourceMetadataURLs(resourceURL string) ([]string, error) {
	u, err := sanitizeURL(resourceURL)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse protected resource URL: %w", err)
	}

	origin := url.URL{Scheme: u.Scheme, Host: u.Host}
	metadataURLs := make([]string, 0, 2)
	resourcePath := strings.TrimPrefix(u.Path, "/")
	if resourcePath != "" && resourcePath != "/" {
		metadataURLs = append(metadataURLs, origin.JoinPath(oauthProtectedResourceRootPath, resourcePath).String())
	}
	metadataURLs = append(metadataURLs, origin.JoinPath(oauthProtectedResourceRootPath).String())

	return metadataURLs, nil
}

// FetchOAuthProtectedResourceMetadata fetches RFC 9728 protected resource
// metadata from the resource URL's well-known paths.
func FetchOAuthProtectedResourceMetadata(ctx context.Context, client *http.Client, resourceURL string) (*ProtectedResourceMetadata, error) {
	ctx, cancel := withDiscoveryDeadline(ctx)
	defer cancel()

	metadataURLs, err := protectedResourceMetadataURLs(resourceURL)
	if err != nil {
		return nil, goerrors.Errorf("%w: %w", ErrUnableToDetermineAuthConfig, err)
	}

	for _, metadataURL := range metadataURLs {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, metadataURL, http.NoBody)
		if err != nil {
			return nil, goerrors.Errorf("%w: %w", ErrUnableToDetermineAuthConfig, err)
		}
		req.Header.Set("Accept", "application/json")

		//nolint:gosec // metadataURL is constructed by protectedResourceMetadataURLs from the sanitized resource URL.
		resp, err := client.Do(req)
		if err != nil {
			return nil, goerrors.Errorf("%w: %w", ErrUnableToDetermineAuthConfig, err)
		}

		if resp.StatusCode == http.StatusNotFound {
			closeErr := resp.Body.Close()
			if closeErr != nil {
				return nil, goerrors.Errorf("%w: %w", ErrUnableToDetermineAuthConfig, closeErr)
			}
			continue
		}
		if resp.StatusCode != http.StatusOK {
			closeErr := resp.Body.Close()
			if closeErr != nil {
				return nil, goerrors.Errorf("%w: %w", ErrUnableToDetermineAuthConfig, closeErr)
			}
			return nil, goerrors.Errorf("%w: unexpected status code %d", ErrUnableToDetermineAuthConfig, resp.StatusCode)
		}

		body, err := io.ReadAll(resp.Body)
		closeErr := resp.Body.Close()
		if err != nil {
			return nil, goerrors.Errorf("%w: %w", ErrUnableToDetermineAuthConfig, err)
		}
		if closeErr != nil {
			return nil, goerrors.Errorf("%w: %w", ErrUnableToDetermineAuthConfig, closeErr)
		}

		var metadata ProtectedResourceMetadata
		err = json.Unmarshal(body, &metadata)
		if err != nil {
			return nil, goerrors.Errorf("%w: %w", ErrUnableToDetermineAuthConfig, err)
		}

		return &metadata, nil
	}

	return nil, ErrMetadataNotFound
}
