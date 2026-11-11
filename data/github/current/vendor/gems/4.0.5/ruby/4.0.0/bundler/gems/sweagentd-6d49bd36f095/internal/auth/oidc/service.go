// Package oidc implements OIDC-based token exchange for 3rd party MCP servers
// in Agentic GitHub Apps.
package oidc

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/auth/oidc/varfetcher"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"golang.org/x/net/http/httpproxy"
)

// ExchangeResponse represents a successful token exchange response.
type ExchangeResponse struct {
	AccessToken     string `json:"access_token"`      //nolint:gosec // There is no hard coded secret here, this is expected to contain the access token obtained from the integrator.
	IssuedTokenType string `json:"issued_token_type"` //nolint:gosec // There is no hard coding here, this just indicates the type of the issued token.
	TokenType       string `json:"token_type"`
	ExpiresIn       int    `json:"expires_in"`
}

// IssuedToken tracks a token that was exchanged so it can later be revoked.
type IssuedToken struct {
	IDToken            string
	AccessToken        string //nolint:gosec // There is no hard coded secret here, this is expected to contain the access token obtained from the integrator.
	RevocationEndpoint string
	ConfigEntry        oidcconfig.ConfigEntry
}

// ExchangeFailure captures a per-entry token exchange failure with enough
// context for the caller to report the problem to the end user.
type ExchangeFailure struct {
	// ResponseCode is the HTTP status code that best describes this failure
	// (e.g. 500 for internal errors, 401 for authorization_required).
	ResponseCode int
	// Message is a human-readable description of what went wrong.
	Message string
	// Error is a system-readable description of what went wrong.
	Error string
	// FailureURL is the integrator-configured failure endpoint, if any.
	FailureURL string
	// SecretName is the full secret name for entries resolved via secret_names.
	SecretName string
	// ServerName is the MCP server name for entries resolved via mcp_server_names.
	ServerName string
}

// ExchangeWarning captures a per-entry token exchange warning that should be
// surfaced to callers without failing the exchange.
type ExchangeWarning struct {
	// A human-readable warning message.
	Message string
}

// ExchangeResult contains the secrets produced by processing an OIDC config and the
// associated issued tokens needed for later revocation.
type ExchangeResult struct {
	// Secrets maps each full secret name (as returned by the config entry) to the access token obtained from the exchange.
	Secrets map[string]string
	// MCPServerTokens maps MCP server names to the access token obtained from the exchange.
	MCPServerTokens map[string]string
	// IssuedTokens contains the full token details and the related request.
	IssuedTokens []IssuedToken
	// Failures contains per-entry exchange failures. Entries that fail are not
	// included in Secrets or MCPServerTokens but are captured here instead.
	Failures []ExchangeFailure

	// Warnings contains per-entry exchange warnings that are not
	// severe enough to be considered failures, but may still be useful for debugging
	// or user feedback.
	Warnings []ExchangeWarning
}

const (
	httpTimeout = 10 * time.Second
)

// ServiceConfig holds optional runtime configuration for the OIDC service.
type ServiceConfig struct {
	HTTPProxy       string
	HTTPSProxy      string
	VariableFetcher varfetcher.VariableFetcher
}

// Service orchestrates the OIDC token exchange lifecycle: generating ID tokens,
// exchanging them for 3rd party access tokens, and revoking them when work completes.
type Service struct {
	signer     TokenSigner
	httpClient *http.Client
	exchanger  *Exchanger
	revoker    *Revoker
	loader     *ConfigLoader
	obsv       observability.Exporters
}

// NewService creates a Service that uses the given TokenSigner for issuing
// OIDC ID tokens, and creates its own HTTP-based exchanger and revoker for
// communicating with integrator endpoints.
func NewService(ffClient featureflags.Client, signer TokenSigner, spokes sweagentd.Spokes, ghTwirp githubtwirp.ClientInterface, obsv observability.Exporters, cfg ServiceConfig) *Service {
	httpClient := newOIDCHTTPClient(cfg)

	fetcher := cfg.VariableFetcher
	if fetcher == nil {
		fetcher = func(_ context.Context, _ sweagentd.AgenticApp, _ int64, _ []string) (map[string]string, error) {
			return nil, nil
		}
	}

	return &Service{
		signer:     signer,
		httpClient: httpClient,
		exchanger:  NewExchanger(httpClient, obsv),
		revoker:    NewRevoker(httpClient, obsv),
		loader:     NewConfigLoader(ffClient, spokes, ghTwirp, obsv, fetcher),
		obsv:       obsv,
	}
}

// NewLocalService creates a Service that uses the given TokenSigner and does not attempt
// to load any configuration from GitHub (e.g. from settings.json or MCP config). This is
// useful for testing or local development where the full GitHub environment is not available.
func NewLocalService(ffClient featureflags.Client, signer TokenSigner, obsv observability.Exporters, cfg ServiceConfig) *Service {
	httpClient := newOIDCHTTPClient(cfg)

	fetcher := cfg.VariableFetcher
	if fetcher == nil {
		fetcher = func(_ context.Context, _ sweagentd.AgenticApp, _ int64, _ []string) (map[string]string, error) {
			return nil, nil
		}
	}

	return &Service{
		signer:     signer,
		httpClient: httpClient,
		exchanger:  NewExchanger(httpClient, obsv),
		revoker:    NewRevoker(httpClient, obsv),
		loader:     NewLocalConfigLoader(ffClient, obsv, fetcher),
		obsv:       obsv,
	}
}

func newOIDCHTTPClient(cfg ServiceConfig) *http.Client {
	baseTransport, ok := http.DefaultTransport.(*http.Transport)
	if !ok {
		baseTransport = &http.Transport{}
	}

	transport := baseTransport.Clone()
	transport.Proxy = proxyFromConfig(cfg)

	return &http.Client{
		Timeout:   httpTimeout,
		Transport: transport,
	}
}

func proxyFromConfig(cfg ServiceConfig) func(*http.Request) (*url.URL, error) {
	proxyFunc := (&httpproxy.Config{
		HTTPProxy:  strings.TrimSpace(cfg.HTTPProxy),
		HTTPSProxy: strings.TrimSpace(cfg.HTTPSProxy),
	}).ProxyFunc()

	return func(req *http.Request) (*url.URL, error) {
		if req == nil || req.URL == nil {
			return nil, nil
		}

		return proxyFunc(req.URL)
	}
}

// Signer returns the underlying TokenSigner used by the service.
func (s *Service) Signer() TokenSigner {
	return s.signer
}

// IssueIDToken delegates token signing to the underlying TokenSigner.
func (s *Service) IssueIDToken(ctx context.Context, audience, subject, actSubject string, additionalClaims map[string]string) (string, error) {
	return s.signer.IssueIDToken(ctx, audience, subject, actSubject, additionalClaims)
}

// ExchangeTokens iterates over all entries, issues an ID token for each, exchanges it
// at the integrator endpoint, and returns the resulting secrets mapped by their
// configured secret names. Entries must have endpoints already resolved (e.g. via
// DiscoverConfigForMCPServers or DiscoverConfiguration). Entries are processed in parallel.
func (s *Service) ExchangeTokens(ctx context.Context, entries []oidcconfig.ConfigEntry, params TokenParams) (result *ExchangeResult, retErr error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "oidc.Service.ExchangeTokens")
	defer func() {
		if retErr != nil && !errors.Is(retErr, ErrPartialSuccess) {
			span.RecordError(retErr)
			span.SetStatus(codes.Error, retErr.Error())
		}
		span.End()
	}()
	span.SetAttributes(attribute.Int("oidc.entry_count", len(entries)))

	if len(entries) == 0 {
		return &ExchangeResult{
			Secrets:         make(map[string]string),
			MCPServerTokens: make(map[string]string),
		}, nil
	}

	type entryResult struct {
		token   IssuedToken
		failure *ExchangeFailure
		warning *ExchangeWarning
	}

	results := make([]entryResult, len(entries))

	// Process entries in parallel since each exchange involves a network call and can be done independently
	// to reduce overall latency. We wait to return until all entries have been processed, so the worst case
	// is the latency of the slowest exchange call, but much faster than doing them serially.
	var wg sync.WaitGroup

	for i, entry := range entries {
		wg.Go(func() {
			if entry.Endpoints.Exchange == "" {
				results[i] = entryResult{
					failure: newExchangeFailure(entry, goerrors.Errorf("%w: missing token exchange endpoint for config entry", oidcconfig.ErrInvalidConfig)),
				}
				return
			}

			sub, actSub := BuildSubject(SubjectOptions{
				AgentOnlySubject:      entry.AgentOnlySubject,
				RepoOnlySubject:       entry.RepoOnlySubject,
				UseAgenticAppIdentity: entry.UseAgenticAppIdentity(),
			}, params)

			// Build standard claims from token params.
			claims := params.ToClaimsMap()

			// Include scope and resource as claims when configured.
			if entry.Scope != "" {
				claims["scope"] = entry.Scope
			}
			if entry.Resource != "" {
				claims["resource"] = entry.Resource
			}

			jwt, err := s.signer.IssueIDToken(ctx, entry.Audience, sub, actSub, claims)
			if err != nil {
				results[i] = entryResult{
					failure: newExchangeFailure(entry, goerrors.Errorf("%w: failed to issue identity token: %w", ErrTokenExchangeFailed, err))}
				return
			}

			warning := verifyDomainMatch(entry)

			var exchangeResp *ExchangeResponse
			switch {
			case entry.UseJWTBearer():
				exchangeResp, err = s.exchanger.ExchangeJWTBearer(ctx, entry.Endpoints.Exchange, entry.Audience, jwt, entry.Scope, entry.Resource)
			case entry.UseClientCredentials():
				exchangeResp, err = s.exchanger.ExchangeClientCredentials(ctx, entry.Endpoints.Exchange, jwt, entry.Scope, entry.ClientID)
			case entry.UseIDTokenExchange():
				exchangeResp, err = s.exchanger.ExchangeIDToken(ctx, entry.Endpoints.Exchange, entry.Audience, jwt, entry.Scope, entry.Resource, entry.ClientID)
			default:
				// Default to jwt-bearer for all entries, with a fallback to
				// client credentials when the server does not support it.
				exchangeResp, err = s.exchanger.ExchangeJWTBearer(ctx, entry.Endpoints.Exchange, entry.Audience, jwt, entry.Scope, entry.Resource)
				if errors.Is(err, ErrUnsupportedGrantType) && entry.ClientID != "" {
					exchangeResp, err = s.exchanger.ExchangeClientCredentials(ctx, entry.Endpoints.Exchange, jwt, entry.Scope, entry.ClientID)
				}
			}
			if err != nil {
				results[i] = entryResult{failure: newExchangeFailure(entry, err), warning: warning}
				return
			}

			results[i] = entryResult{
				token: IssuedToken{
					IDToken:            jwt,
					AccessToken:        exchangeResp.AccessToken,
					RevocationEndpoint: entry.Endpoints.Revoke,
					ConfigEntry:        entry,
				},
				warning: warning,
			}
		})
	}

	wg.Wait()

	out := &ExchangeResult{
		Secrets:         make(map[string]string, len(entries)),
		MCPServerTokens: make(map[string]string, len(entries)),
	}

	for i := range results {
		r := &results[i]
		if r.failure != nil {
			out.Failures = append(out.Failures, *r.failure)
		} else {
			if r.warning != nil {
				out.Warnings = append(out.Warnings, *r.warning)
			}
			// Technically may be applied to both a server and an env var, so handle separately
			entry := r.token.ConfigEntry
			if entry.FullSecretName() != "" {
				out.Secrets[entry.FullSecretName()] = r.token.AccessToken
			}
			if entry.ServerName() != "" {
				out.MCPServerTokens[entry.ServerName()] = r.token.AccessToken
			}
			out.IssuedTokens = append(out.IssuedTokens, r.token)
		}
	}
	if len(out.Failures) > 0 {
		return out, ErrPartialSuccess
	}
	return out, nil
}

// RevokeAccessTokens accepts a set of previously exchanged tokens and revokes them by
// calling each integrator's revocation endpoint. Entries must have endpoints already
// resolved (e.g. via DiscoverConfigForMCPServers or DiscoverConfiguration). A specific
// error is returned that can be checked for with errors.Is() if some revocations failed;
// it still attempts to revoke all tokens and collects all errors even if one fails.
func (s *Service) RevokeAccessTokens(ctx context.Context, tokens map[string]string, entries []oidcconfig.ConfigEntry, params TokenParams) (retErr error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "oidc.Service.RevokeAccessTokens")
	defer func() {
		if retErr != nil && !errors.Is(retErr, ErrPartialRevocationFailed) {
			span.RecordError(retErr)
			span.SetStatus(codes.Error, retErr.Error())
		}
		span.End()
	}()

	// Filter to entries that have a revocation endpoint and a matching token.
	var filtered []oidcconfig.ConfigEntry
	for _, entry := range entries {
		if _, ok := tokens[entry.FullSecretName()]; ok && entry.Endpoints.Revoke != "" {
			filtered = append(filtered, entry)
		}
	}

	if len(filtered) == 0 {
		return nil
	}

	var errors []error

	var wg sync.WaitGroup
	var mu sync.Mutex

	for _, entry := range filtered {
		wg.Go(func() {
			secretName := entry.FullSecretName()

			sub, actSub := BuildSubject(SubjectOptions{
				AgentOnlySubject:      entry.AgentOnlySubject,
				RepoOnlySubject:       entry.RepoOnlySubject,
				UseAgenticAppIdentity: entry.UseAgenticAppIdentity(),
			}, params)

			// Build standard claims from token params.
			claims := params.ToClaimsMap()

			idToken, err := s.signer.IssueIDToken(ctx, entry.Audience, sub, actSub, claims)
			if err != nil {
				mu.Lock()
				errors = append(errors, goerrors.Errorf("oidc: failed to issue token for %q: %w", secretName, err))
				mu.Unlock()
				return
			}

			err = s.revoker.RevokeToken(ctx, entry.Endpoints.Revoke, idToken, tokens[secretName], entry.ClientID)
			if err != nil {
				mu.Lock()
				errors = append(errors, goerrors.Errorf("oidc: failed to revoke token for secret %q: %w", secretName, err))
				mu.Unlock()
				return
			}
		})
	}
	wg.Wait()

	if len(errors) > 0 {
		resultErr := ErrPartialRevocationFailed
		for _, err := range errors {
			resultErr = goerrors.Errorf("%w: %w", resultErr, err)
		}
		return resultErr
	}
	return nil
}

// ResolveConfigurationParams contains the parameters needed to resolve OIDC configuration for a given repository and user, including any relevant agent information.
type ResolveConfigurationParams struct {
	App                  sweagentd.AgenticApp // The agentic app making the request (needed for variable fetching auth)
	RepoID               int64
	ActorID              int64
	Agent                sweagentd.CustomAgent // Optional
	AgentFromApp         bool                  // True when the agent was resolved from the agentic app's plugin (uses agentic app identity)
	SecretNames          []string
	MCPServerNames       []string
	AppMCPConfigs        []mcpconfig.JSON // MCP configs from the agentic app's own plugin (use agentic app identity)
	AdditionalMCPConfigs []mcpconfig.JSON // Extra MCP configs (e.g. from repo plugins) to merge into OIDC resolution
}

// ResolveConfiguration loads and merges OIDC configuration from settings.json, MCP config,
// and agent config (if provided) for the given repository and user, returning a DiscoveryResult
// that can be used for token exchange. Agent config takes precedence over MCP config, which
// takes precedence over settings.json. This is a potentially expensive operation since it
// may involve multiple network calls and config parsing, so the result should be cached.
func (s *Service) ResolveConfiguration(ctx context.Context, req ResolveConfigurationParams) ([]oidcconfig.ConfigEntry, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "oidc.Service.ResolveConfiguration")
	defer span.End()
	span.SetAttributes(
		attribute.Int("oidc.variable_name_count", len(req.SecretNames)),
		attribute.Int("oidc.mcp_server_name_count", len(req.MCPServerNames)),
	)

	// Build a server filter from the requested MCP server names so that Load
	// only resolves variables for servers that will actually be used.
	serverFilter := make(map[string]bool, len(req.MCPServerNames))
	for _, name := range req.MCPServerNames {
		serverFilter[name] = true
	}

	// First, load and merge the config from all relevant sources.
	loaded, err := s.loader.Load(ctx, req, serverFilter)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return nil, err
	}
	entries := make([]oidcconfig.ConfigEntry, 0, len(loaded))
	for _, entry := range loaded {
		if entry.SecretSuffix != "" && slices.Contains(req.SecretNames, entry.FullSecretName()) {
			entries = append(entries, entry)
			// Continue so we don't add it twice in the case a secret and server name is present
			continue
		}
		serverName := entry.ServerName()
		if serverName != "" && slices.Contains(req.MCPServerNames, serverName) {
			entries = append(entries, entry)
		}
	}

	return s.DiscoverConfiguration(ctx, entries)
}

func (s *Service) oidcHTTPClient() *http.Client {
	if s.httpClient != nil {
		return s.httpClient
	}
	return http.DefaultClient
}

// newExchangeFailure creates an ExchangeFailure from a config entry and the
// error that occurred during exchange. The response code is determined by the error type:
// 200 - nil
// 400 - ErrUnsupportedGrantType, ErrUnableToDetermineGrantType, ErrInvalidConfig, ErrInvalidURL
// 401 - ErrAuthorizationRequired, ErrInvalidGrant (auth failed, invalid grant)
// 404 - ErrMetadataNotFound
// 424 - ErrIDPError  (Indicates upstream failure)
// 502 - ErrNetworkError
// 500 - Anything else (probably our fault)
func newExchangeFailure(entry oidcconfig.ConfigEntry, failureErr error) *ExchangeFailure {
	failureURL := ""
	s, err := sanitizeURL(entry.Endpoints.Failure)
	if err == nil {
		failureURL = s.String()
	}
	n := entry.ServerName()
	if n == "" {
		n = entry.FullSecretName()
	}
	var message string
	var code int
	switch {
	case failureErr == nil:
		return nil
	case errors.Is(failureErr, ErrUnsupportedGrantType):
		message = fmt.Sprintf("An invalid grant type was used in the token exchange request for %s. This may indicate a misconfiguration in the integrator or that the integrator does not support the requested authentication method.", n)
		code = http.StatusBadRequest // 400
	case errors.Is(failureErr, ErrUnableToDetermineGrantType):
		message = fmt.Sprintf("The service was unable to determine the appropriate grant type for the token exchange request for %s. This may indicate a misconfiguration in the integrator or that the integrator does not support the expected authentication methods.", n)
		code = http.StatusBadRequest // 400
	case errors.Is(failureErr, oidcconfig.ErrInvalidConfig):
		message = fmt.Sprintf("The integrator configuration for %s is invalid. Please verify your configuration is correct and try again.", n)
		code = http.StatusBadRequest // 400
	case errors.Is(failureErr, ErrInvalidURL):
		message = fmt.Sprintf("The integrator configuration for %s contains an invalid URL. Please verify the URL is correct and try again.", n)
		code = http.StatusBadRequest // 400
	case errors.Is(failureErr, ErrMetadataNotFound):
		message = fmt.Sprintf("The service was unable to automatically configure the needed endpoints for token exchange for %s. Update the configuration with the correct endpoints and try again.", n)
		code = http.StatusNotFound // 404
	case errors.Is(failureErr, ErrAuthorizationRequired):
		if failureURL != "" {
			message = fmt.Sprintf("Authorization failed: GitHub was unable to get an access token for %s. Visit %s and then retry.", n, failureURL)
		} else {
			message = fmt.Sprintf("Authorization failed: GitHub was unable to get an access token for %s. This can be due to a misconfiguration or an issue with the identity provider.", n)
		}
		code = http.StatusUnauthorized // 401
	case errors.Is(failureErr, ErrInvalidGrant):
		if failureURL != "" {
			message = fmt.Sprintf("Invalid grant: GitHub was unable to get an access token for %s. This can happen due to a token expiration or misconfiguration. Visit %s and then retry.", n, failureURL)
		} else {
			message = fmt.Sprintf("Invalid grant: GitHub was unable to get an access token for %s due to an invalid grant after multiple retries. This may indicate the access token is expired, a misconfiguration in the integrator, or that the integrator does not support the requested authentication method.", n)
		}
		code = http.StatusUnauthorized // 401
	case errors.Is(failureErr, ErrIDPError):
		message = fmt.Sprintf("The integrator returned an unexpected response for %s. Please verify that the integrator is configured correctly and is available, and try again.", n)
		code = http.StatusFailedDependency // 424
	case errors.Is(failureErr, ErrNetworkError):
		message = fmt.Sprintf("A network error occurred while attempting to communicate with the identity provider for %s. Please verify that the integrator is configured correctly and is available, and try again.", n)
		code = http.StatusBadGateway // 502
	default:
		message = fmt.Sprintf("An unexpected error occurred while attempting to generate an access token for %s. Please try again, and if the problem persists, contact support.", n)
		code = http.StatusInternalServerError // 500
	}

	return &ExchangeFailure{
		ResponseCode: code,
		Message:      message,
		Error:        fmt.Sprintf("[%s] %v", n, failureErr.Error()),
		FailureURL:   failureURL,
		SecretName:   entry.FullSecretName(),
		ServerName:   entry.ServerName(),
	}
}

func sanitizeURL(rawURL string) (url.URL, error) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return url.URL{}, err
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return url.URL{}, goerrors.Errorf("invalid URL scheme: %s", u.Scheme)
	}
	hostname := u.Hostname()
	if hostname == "" {
		return url.URL{}, goerrors.New("URL must have a hostname")
	}
	if u.Scheme == "http" && (hostname != "localhost" && hostname != "127.0.0.1") {
		return url.URL{}, goerrors.Errorf("invalid hostname for http scheme: %s", hostname)
	}
	// Drop any query parameters, fragments, user, and password to
	// prevent leakage of sensitive information in logs or errors.
	sanitizedURL := url.URL{
		Scheme: u.Scheme,
		Host:   u.Host,
		Path:   u.Path,
	}
	return sanitizedURL, nil
}

// hostsMatch reports whether two URLs resolve to the same hostname.
// Path differences are expected for MCP versus token endpoints, but sending
// auth material to a different hostname should be surfaced as a warning.
func hostsMatch(rawLeft, rawRight string) bool {
	leftURL, err := url.Parse(rawLeft)
	if err != nil {
		return false
	}
	rightURL, err := url.Parse(rawRight)
	if err != nil {
		return false
	}

	leftHost := leftURL.Hostname()
	rightHost := rightURL.Hostname()
	if leftHost == "" || rightHost == "" {
		return false
	}

	return leftHost == rightHost
}

// redactURL strips userinfo, query parameters, and fragments from a URL
// to prevent leaking sensitive information in warning messages.
func redactURL(rawURL string) string {
	u, err := url.Parse(rawURL)
	if err != nil {
		return rawURL
	}
	clean := url.URL{
		Scheme: u.Scheme,
		Host:   u.Host,
		Path:   u.Path,
	}
	return clean.String()
}

func verifyDomainMatch(entry oidcconfig.ConfigEntry) *ExchangeWarning {
	serverURL := entry.ServerURL()

	targetName := entry.ServerName()
	if targetName == "" {
		targetName = entry.FullSecretName()
	}

	var mismatchedSettings []string
	exchangeURL := entry.Endpoints.Exchange
	revokeURL := entry.Endpoints.Revoke
	if serverURL != "" {
		if exchangeURL != "" && !hostsMatch(exchangeURL, serverURL) {
			mismatchedSettings = append(mismatchedSettings,
				fmt.Sprintf("token exchange endpoint (%q)", redactURL(exchangeURL)),
			)
		}
		if revokeURL != "" && !hostsMatch(revokeURL, serverURL) {
			mismatchedSettings = append(mismatchedSettings,
				fmt.Sprintf("token revoke endpoint (%q)", redactURL(revokeURL)),
			)
		}
	}
	if serverURL == "" && exchangeURL != "" && revokeURL != "" && !hostsMatch(exchangeURL, revokeURL) {
		mismatchedSettings = append(mismatchedSettings,
			fmt.Sprintf("token exchange endpoint (%q) does not match token revoke endpoint (%q)", redactURL(exchangeURL), redactURL(revokeURL)),
		)
	}
	if len(mismatchedSettings) == 0 {
		return nil
	}

	prefix := "The following MCP auth configuration settings"
	if targetName != "" {
		prefix = fmt.Sprintf("The following MCP auth configuration settings for %q", targetName)
	}

	if serverURL != "" {
		return &ExchangeWarning{Message: fmt.Sprintf("%s do not match the server's remote URL %q and may be misconfigured: %s. To ensure information is not sent to the incorrect location, please verify that these endpoints are configured correctly.", prefix, redactURL(serverURL), strings.Join(mismatchedSettings, ", "))}
	}

	return &ExchangeWarning{Message: fmt.Sprintf("%s do not match each other and may be misconfigured: %s. To ensure information is not sent to the incorrect location, please verify that these endpoints are configured correctly.", prefix, strings.Join(mismatchedSettings, ", "))}
}
