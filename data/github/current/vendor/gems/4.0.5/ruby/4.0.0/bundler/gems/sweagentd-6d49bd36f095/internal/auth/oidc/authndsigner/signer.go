// Package authndsigner implements a TokenSigner that delegates ID token
// signing to the authnd IdentityManager service instead of signing locally.
package authndsigner

import (
	"context"
	"slices"

	"github.com/github/sweagentd/internal/authnd"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

// additionalJWTClaims lists the additional claims included in OIDC tokens. No others should be allowed.
var additionalJWTClaims = []string{"repository", "repository_id", "repository_owner", "repository_owner_id", "client_id", "agent_client_id", "agent_id", "installation_id", "preferred_username", "user_id", "scope", "resource", "session_id"}

// Signer implements oidc.TokenSigner by delegating token signing to the
// authnd IdentityManager service via IssueIdentityToken.
type Signer struct {
	client authnd.Authenticator
}

// NewSignerWithClient creates a Signer that issues identity tokens via authnd's
// IssueIdentityToken RPC.
func NewSignerWithClient(client authnd.Authenticator) *Signer {
	return &Signer{
		client: client,
	}
}

// NewSigner creates a Signer along with the required authnd identity client.
func NewSigner(cfg *config.Config, obsv observability.Exporters) (*Signer, error) {
	if cfg.AuthndURL == "" {
		return nil, goerrors.New("AUTHND_URL is required when OIDC_AUTHND_ENABLED is true")
	}
	// Note: Authnd HMAC key is "" in Proxima, so we cannot check for that here.
	obsv.Logger.Info("Using authnd service for OIDC token issuance at " + cfg.AuthndURL)
	client, err := authnd.NewClient(obsv, authnd.ClientOpts{
		AuthndURL:   cfg.AuthndURL,
		HMACKey:     cfg.AuthndHMACKey,
		ServiceName: cfg.ServiceName,
	})
	if err != nil {
		return nil, goerrors.Errorf("failed to create authnd client: %w", err)
	}
	return NewSignerWithClient(client), nil
}

// IssueIDToken mints an ID token by calling authnd's IssueIdentityToken.
func (s *Signer) IssueIDToken(ctx context.Context, audience, subject, actSubject string, additionalClaims map[string]string) (string, error) {
	// Validate that all keys in additionalClaims are allowed
	for key := range additionalClaims {
		if !slices.Contains(additionalJWTClaims, key) {
			return "", goerrors.Errorf("oidc: claim %q is not in AdditionalJWTClaims", key)
		}
	}

	req := authnd.IssueIdentityTokenRequest{
		Sub:              subject,
		Aud:              audience,
		Act:              authnd.ActorClaims{Sub: actSubject},
		AdditionalClaims: additionalClaims,
	}
	token, err := s.client.IssueIdentityToken(ctx, req)
	if err != nil {
		return "", goerrors.Errorf("oidc: authnd IssueIdentityToken failed: %w", err)
	}

	if token == "" {
		return "", goerrors.New("oidc: authnd returned empty token")
	}

	return token, nil
}
