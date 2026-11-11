package authnd

import (
	"context"
	"os"
	"strings"

	"github.com/github/authnd/client"
)

var monalisaPAT = os.Getenv("MONALISA_PAT")

// NoopClient is a no-op implementation of the authnd Client.
type NoopClient struct {
	ActorID                uint64
	UserLogin              string
	ApplicationID          uint64
	ApplicationType        string
	CredentialType         client.CredentialType
	MockIssueIdentityToken func(ctx context.Context, req IssueIdentityTokenRequest) (string, error)
}

// NewNoopClient creates a new noop authnd client for testing and development purposes.
func NewNoopClient(githubAppID int64) *NoopClient {
	return &NoopClient{
		ActorID:       2, // monalisa
		UserLogin:     "monalisa",
		ApplicationID: uint64(githubAppID),
	}
}

// AuthenticateAPIToken is for testing and local development, and defaults to user ID 1.
func (n NoopClient) AuthenticateAPIToken(ctx context.Context, token string) (*AuthenticateTokenResponse, error) {
	actorID := n.ActorID
	if actorID == 0 {
		actorID = 1
	}

	userLogin := n.UserLogin
	if userLogin == "" {
		userLogin = "test-authnd-user"
	}

	credentialType := n.CredentialType
	if credentialType == "" {
		credentialType = client.CredentialTypeLegacyPersonalAccessToken
	}

	return &AuthenticateTokenResponse{
		ActorID:         actorID,
		UserLogin:       userLogin,
		SessionID:       123,
		ApplicationID:   n.ApplicationID,
		ApplicationType: n.ApplicationType,
		Type:            credentialType,
	}, nil
}

// IssueIdentityToken returns a mock identity token for testing and local development.
func (n NoopClient) IssueIdentityToken(ctx context.Context, req IssueIdentityTokenRequest) (string, error) {
	if n.MockIssueIdentityToken != nil {
		return n.MockIssueIdentityToken(ctx, req)
	}
	return "mock-identity-token", nil
}

// IsValidTokenFormat checks if the provided token has a valid format for testing purposes.
func (n NoopClient) IsValidTokenFormat(token string) bool {
	// We need to be able to use the monalisa PAT in development to test APIs via CURL, so treat this as a valid token
	if monalisaPAT != "" && token == monalisaPAT {
		return true
	}
	for _, prefix := range SupportedThirdPartyTokenPrefixes {
		if strings.HasPrefix(token, prefix) {
			return true
		}
	}
	return legacyTokenPattern.MatchString(token)
}
