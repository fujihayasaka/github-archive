// Package auth contains middleware and helpers for authentication
package auth

import (
	"crypto/sha256"
	"encoding/base64"
	"net/http"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/authnd"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

const (
	// AuthorizationHeader is the HTTP header used for authentication.
	AuthorizationHeader = "Authorization"

	// EncryptedTokenPrefix is the prefix for encrypted tokens.
	EncryptedTokenPrefix = "GitHub-Bearer " //nolint:gosec // This is not a secret token, but rather a prefix used to identify the token type.
)

// Authenticator contains a middleware and helpers for authenticating requests.
type Authenticator struct {
	obsv         observability.Exporters
	authndClient authnd.Authenticator
	ffClient     featureflags.Client
	ghTwirp      githubtwirp.ClientInterface
	appProvider  *agenticapp.Provider
}

// NewAuthenticator returns an Authenticator.
func NewAuthenticator(obsv observability.Exporters, authndClient authnd.Authenticator, ghTwirp githubtwirp.ClientInterface, ffClient featureflags.Client) *Authenticator {
	return &Authenticator{
		obsv:         obsv,
		authndClient: authndClient,
		ghTwirp:      ghTwirp,
		ffClient:     ffClient,
	}
}

// SetAppProvider configures the agenticapp.Provider used to resolve the
// authenticated token's GitHub App into an agent_slug telemetry tag. When
// unset the middleware behaves as before; when set it populates
// requestctx.CtxAgent so downstream metrics can include agent_slug even on
// non-job request paths. Gated on sweagent_emit_agent_slug_telemetry.
func (a *Authenticator) SetAppProvider(p *agenticapp.Provider) {
	a.appProvider = p
}

// Middleware authenticates requests and adds the user info to the request context.
func (a *Authenticator) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, span := a.obsv.Tracer.Start(r.Context(), "auth.Authenticator.Middleware")
		defer span.End()

		tags, _, kvps := requestctx.ToTelemetry(ctx, r)
		logger := a.obsv.Logger.WithContext(ctx).WithFields(kvps...)

		token := a.parseAuthorizationHeader(r)
		if token == "" {
			logger.Error("no token in request")
			http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
			return
		}

		if !a.authndClient.IsValidTokenFormat(token) {
			prefix := token
			if len(prefix) > 10 {
				prefix = prefix[:10]
			}
			logger.Error("unsupported token format",
				kvp.String("gh.sweagentd.token_prefix", prefix),
				kvp.Int("gh.sweagentd.token_length", len(token)),
			)
			http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
			return
		}

		tokenInfo, err := a.authndClient.AuthenticateAPIToken(ctx, token)
		if err != nil {
			logger.WithError(err).Error("failed to authenticate token")
			a.obsv.Statter.Counter("authnd.attempt", tags.Merge(stats.Tags{"success": "false"}), 1)
			http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
			return
		}

		// This should be the actual request IP rather than just the IP used to connect to the service.
		ipAddress := r.Header.Get("X-Real-IP")

		a.obsv.Statter.Counter("authnd.attempt", tags.Merge(stats.Tags{"success": "true", "credential_type": string(tokenInfo.Type)}), 1)

		// Add data to the context first, so we can use it for caching
		data := &requestctx.CtxData{}
		ctx = requestctx.AddData(ctx, data)

		// Store the integration client (derived from User-Agent) in the context
		// so it is available to TelemetryTags even without the *http.Request.
		_ = requestctx.AddIntegrationClient(ctx, r.UserAgent())

		// let's see if we can get the tracking ID from dotcom
		var trackingID string

		// use the GitHub Twirp client to get the tracking ID
		userDetails, err := a.ghTwirp.GetCopilotUserDetails(ctx, int64(tokenInfo.ActorID))
		if err != nil {
			logger.WithError(err).Error("failed to get copilot user details")
			a.obsv.Statter.Counter("authnd.copilot_user_lookup", tags.Merge(stats.Tags{"success": "false"}), 1)
		} else {
			a.obsv.Statter.Counter("authnd.copilot_user_lookup", tags.Merge(stats.Tags{"success": "true"}), 1)
			trackingID = userDetails.AnalyticsTrackingId
		}

		data.UserInfo = &requestctx.UserInfo{
			ID:         tokenInfo.ActorID,
			Login:      tokenInfo.UserLogin,
			RequestIP:  ipAddress,
			TrackingID: trackingID,
			TokenInfo: &requestctx.TokenInfo{
				SessionID:                    tokenInfo.SessionID,
				ApplicationID:                tokenInfo.ApplicationID,
				Type:                         string(tokenInfo.Type),
				ApplicationType:              tokenInfo.ApplicationType,
				Token:                        token,
				OrganizationSSOAuthorizedIDs: tokenInfo.OrganizationSSOAuthorizedIDs,
			},
		}

		// Populate the agent_slug telemetry tag from the authenticated token's
		// GitHub App when an appProvider is configured. Best-effort: a missing
		// app (e.g. PAT, unknown app id) just leaves the tag unset.
		if a.appProvider != nil && tokenInfo.ApplicationID != 0 {
			appID := int64(tokenInfo.ApplicationID)
			app, err := a.appProvider.FindByID(ctx, appID)
			if err == nil {
				jobservice.SetCtxAgent(ctx, a.obsv, a.ffClient, app, appID)
			}
		}

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// parseAuthorizationHeader parses the `Authorization` header and returns the token.
func (a *Authenticator) parseAuthorizationHeader(r *http.Request) string {
	authHeader := r.Header.Get(AuthorizationHeader)
	if authHeader == "" {
		return ""
	}

	// support "Bearer", "bearer" and "token" to conform to api.github.com
	token := authHeader
	token = strings.TrimPrefix(token, "Bearer ")
	token = strings.TrimPrefix(token, "bearer ")
	token = strings.TrimPrefix(token, "token ")
	return token
}

// HashToken computes SHA256 base64 digest of a token, matching the server-side Ruby implementation:
// Digest::SHA256.base64digest(token)
func HashToken(token string) string {
	hash := sha256.Sum256([]byte(token))
	return base64.StdEncoding.EncodeToString(hash[:])
}
