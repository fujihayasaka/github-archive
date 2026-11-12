// Package authnd provides an interface Authenticator for the authnd service.
package authnd

import (
	"context"
	"regexp"
	"slices"
	"strings"

	"github.com/github/authnd/client"
	authproto "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-mark"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

// ClientOpts are options for creating a new authnd client.
type ClientOpts struct {
	AuthndURL   string
	ServiceName string
	HMACKey     string
}

// Client implements the Authenticator interface.
type Client struct {
	authenticator     client.Authenticator
	credentialManager client.CredentialManager
	obsv              observability.Exporters
}

// NewClient creates a new authnd client instance.
func NewClient(obsv observability.Exporters, opts ClientOpts) (*Client, error) {
	c, err := client.NewAuthenticator(
		opts.AuthndURL,
		opts.ServiceName,
		client.WithHMACKey(opts.HMACKey),
		client.WithStatter(obsv.Statter),
	)
	if err != nil {
		return nil, err
	}
	credman, err := client.NewCredentialManager(
		opts.AuthndURL,
		opts.ServiceName,
		client.WithHMACKey(opts.HMACKey),
		client.WithStatter(obsv.Statter),
	)
	if err != nil {
		return nil, err
	}

	return &Client{authenticator: c, credentialManager: credman, obsv: obsv}, nil
}

// Authenticator is the interface for the authnd client.
type Authenticator interface {
	AuthenticateAPIToken(ctx context.Context, token string) (*AuthenticateTokenResponse, error)
	IsValidTokenFormat(token string) bool
}

var _ Authenticator = (*Client)(nil)

// AuthenticateTokenResponse is the response from AuthenticateToken.
type AuthenticateTokenResponse struct {
	ActorID                      uint64
	UserLogin                    string
	SessionID                    int64
	ApplicationID                uint64
	ApplicationType              string
	Type                         client.CredentialType
	OrganizationSSOAuthorizedIDs []int64
}

// SupportedThirdPartyTokenPrefixes are the prefixes for third-party tokens.
// Per https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github#githubs-token-formats
var SupportedThirdPartyTokenPrefixes = []string{
	"ghp_",        // Personal access token (classic)
	"github_pat_", // Fine-grained personal access token
	"gho_",        // OAuth access token - e.g. one from VS Code
	"ghu_",        // User access token for a GitHub App
}

// legacyTokenPattern is the regular expression for the old pattern of the token.
// Until 2021, GitHub API tokens did not have an identifiable prefix. They
// were 40 characters long and only contained the characters a-f and 0-9.
var legacyTokenPattern = regexp.MustCompile(`^[a-f0-9]{40}$`)

// SupportedAuthndCredentialTypes defines the credential types supported by the authnd service.
var SupportedAuthndCredentialTypes = []client.CredentialType{
	client.CredentialTypeUserToServerToken,
	client.CredentialTypeLegacyPersonalAccessToken,
	client.CredentialTypeFineGrainedPersonalAccessToken,
	client.CredentialTypeOauthApplicationAccessToken,
}

// AuthenticateAPIToken authenticates a PAT or a user-to-server token.
func (c *Client) AuthenticateAPIToken(ctx context.Context, token string) (*AuthenticateTokenResponse, error) {
	creds := client.NewAccessTokenCredentials(token)
	req := client.NewAuthenticateRequest(creds)

	// tenant will be empty on non-Proxima requests, which is ok by authnd
	resp, err := c.authenticator.Authenticate(ctx, req, client.WithTenantSlug(tenant.GetTenant(ctx)))
	if err != nil {
		return nil, goerrors.Errorf("%w: failed to authenticate: %w", mark.ErrUnauthorized, err)
	}
	if resp == nil {
		return nil, goerrors.Errorf("%w: AuthenticateToken response is nil", mark.ErrUnauthorized)
	}

	if !resp.Succeeded() {
		c.logAuthndFailure(ctx, resp)
		return nil, goerrors.Errorf("%w: AuthenticateToken authentication failed", mark.ErrUnauthorized)
	}

	// These are defined here: https://github.com/github/authnd/blob/e940c8c70eb104d0df78c0bae92e972e29210742/internal/api/models/attributes.go#L39
	actorID, err := resp.GetIntAttribute("actor.id")
	if err != nil {
		return nil, goerrors.Errorf("%w: no actor ID on token: %w", mark.ErrBadRequest, err)
	}

	// If there's no integration ID/type, this is a PAT. Checking that the user is enabled is enough.
	applicationID, _ := resp.GetIntAttribute("application.id")
	applicationType, _ := resp.GetStringAttribute("application.type")

	credentialType, err := resp.GetStringAttribute("credential.type")
	if err != nil {
		return nil, goerrors.Errorf("%w: no credential type on token: %w", mark.ErrBadRequest, err)
	}
	parsedType, err := client.ParseCredentialType(credentialType)
	if err != nil {
		return nil, goerrors.Errorf("%w: invalid token type: %w", mark.ErrBadRequest, err)
	}

	userLogin, err := resp.GetStringAttribute("user.login")
	if err != nil {
		return nil, goerrors.Errorf("%w: no user login on token: %w", mark.ErrBadRequest, err)
	}

	if !isSupportedCredentialType(parsedType) {
		return nil, goerrors.Errorf("%w: invalid token type: %w", mark.ErrForbidden, err)
	}

	// if there's no sessionID in the response, this will return 0, which is
	// a fine default, since we don't even reference this ourselves right now.
	sessionID, _ := resp.GetIntAttribute("session.id")

	// This is returned for oauth tokens only.
	orgSSOAuthorizedIDs, _ := resp.GetIntegerListAttribute("organization.sso_authorized_ids")

	return &AuthenticateTokenResponse{
		ActorID:                      uint64(actorID),
		UserLogin:                    userLogin,
		SessionID:                    sessionID,
		ApplicationID:                uint64(applicationID),
		ApplicationType:              applicationType,
		Type:                         parsedType,
		OrganizationSSOAuthorizedIDs: orgSSOAuthorizedIDs,
	}, nil
}

// IsValidTokenFormat checks if the provided token has a valid format based on supported prefixes.
func (c *Client) IsValidTokenFormat(token string) bool {
	for _, prefix := range SupportedThirdPartyTokenPrefixes {
		if strings.HasPrefix(token, prefix) {
			return true
		}
	}
	return legacyTokenPattern.MatchString(token)
}

func (c *Client) logAuthndFailure(ctx context.Context, resp *client.AuthenticateResponse) {
	reqID := requestid.GetGitHubRequestID(ctx)
	result, ok := authproto.AuthenticateResponse_Result_name[int32(resp.Result)]
	if !ok {
		c.obsv.Logger.WithContext(ctx).Info(
			"authnd: authentication failed with unexpected result",
			kvp.Int32("gh.sweagentd.authnd_result.unexpected", int32(resp.Result)),
			kvp.String("gh.request_id", reqID),
		)
		return
	}

	c.obsv.Logger.WithContext(ctx).Info(
		"authnd: authentication failed",
		kvp.String("gh.sweagentd.authnd_result", result),
		kvp.String("gh.request_id", reqID),
	)
}

func isSupportedCredentialType(credType client.CredentialType) bool {
	return slices.Contains(SupportedAuthndCredentialTypes, credType)
}
