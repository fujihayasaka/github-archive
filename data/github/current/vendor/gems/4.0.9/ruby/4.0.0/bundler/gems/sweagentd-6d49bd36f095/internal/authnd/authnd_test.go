package authnd

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/authnd/client"
	"github.com/github/sweagentd/internal/observability"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type mockIdentityManager struct {
	issueIdentityTokenFn func(context.Context, *client.IssueIdentityTokenRequest) (*client.IssueIdentityTokenResponse, error)
}

func (m *mockIdentityManager) IssueIdentityToken(ctx context.Context, req *client.IssueIdentityTokenRequest) (*client.IssueIdentityTokenResponse, error) {
	if m.issueIdentityTokenFn != nil {
		return m.issueIdentityTokenFn(ctx, req)
	}
	return &client.IssueIdentityTokenResponse{Token: "default-mock-token"}, nil
}

func TestIsValidTokenFormat(t *testing.T) {
	c := &Client{}

	// Modern prefixed tokens should be valid
	require.True(t, c.IsValidTokenFormat("ghp_abc123"))
	require.True(t, c.IsValidTokenFormat("gho_abc123"))
	require.True(t, c.IsValidTokenFormat("ghu_abc123"))
	require.True(t, c.IsValidTokenFormat("github_pat_abc123"))
	require.True(t, c.IsValidTokenFormat("ghs_abc123"))

	// Legacy tokens should be valid
	require.True(t, c.IsValidTokenFormat("1234567890abcdef1234567890abcdef12345678"))

	// Invalid tokens should be rejected
	require.False(t, c.IsValidTokenFormat(""))
	require.False(t, c.IsValidTokenFormat("invalid_prefix"))
	require.False(t, c.IsValidTokenFormat("1234567890abcdef1234567890abcdef1234567"))
}

func TestAuthnd_SupportedTokenTypes(t *testing.T) {
	testCases := []struct {
		credType client.CredentialType
		allowed  bool
	}{
		{credType: client.CredentialTypeUnknown, allowed: false},

		// User actor, allowed:
		{credType: client.CredentialTypeUserToServerToken, allowed: true},
		{credType: client.CredentialTypeLegacyPersonalAccessToken, allowed: true},
		{credType: client.CredentialTypeOauthApplicationAccessToken, allowed: true},

		// User actor, which may be attempting to access organization resources,
		// depending on its grant
		{credType: client.CredentialTypeFineGrainedPersonalAccessToken, allowed: true},

		// "Bot" actor, allowed:
		{credType: client.CredentialTypeServerToServerToken, allowed: true},

		// Intentionally disallowed tokens:
		{credType: client.CredentialTypeOauthAppClientSecret, allowed: false},
		{credType: client.CredentialTypeSSHPublicKey, allowed: false},
		{credType: client.CredentialTypeIntegrationToken, allowed: false},
	}
	for _, tC := range testCases {
		t.Run("validates credential type", func(t *testing.T) {
			require.Equal(t, tC.allowed, isSupportedCredentialType(tC.credType), "Credential type: %v", tC.credType)
		})
	}
}

func TestIssueIdentityToken(t *testing.T) {
	t.Run("returns token on success", func(t *testing.T) {
		mock := &mockIdentityManager{
			issueIdentityTokenFn: func(_ context.Context, req *client.IssueIdentityTokenRequest) (*client.IssueIdentityTokenResponse, error) {
				return &client.IssueIdentityTokenResponse{Token: "signed-id-token"}, nil
			},
		}
		c := &Client{identityManager: mock, obsv: observability.NewNoopExporters()}

		token, err := c.IssueIdentityToken(context.Background(), IssueIdentityTokenRequest{
			Aud: "https://example.com",
			Sub: "user:123",
			Act: ActorClaims{Sub: "actor:456"},
		})
		require.NoError(t, err)
		require.Equal(t, "signed-id-token", token)
	})

	t.Run("passes claims correctly to identity manager", func(t *testing.T) {
		var capturedReq *client.IssueIdentityTokenRequest
		mock := &mockIdentityManager{
			issueIdentityTokenFn: func(_ context.Context, req *client.IssueIdentityTokenRequest) (*client.IssueIdentityTokenResponse, error) {
				capturedReq = req
				return &client.IssueIdentityTokenResponse{Token: "test-token"}, nil
			},
		}
		c := &Client{identityManager: mock, obsv: observability.NewNoopExporters()}

		_, err := c.IssueIdentityToken(context.Background(), IssueIdentityTokenRequest{
			Aud:              "https://api.example.com",
			Sub:              "user:789",
			Act:              ActorClaims{Sub: "agent:101"},
			AdditionalClaims: map[string]string{"repo": "owner/repo", "workflow": "ci"},
		})
		require.NoError(t, err)
		require.NotNil(t, capturedReq)
		require.Equal(t, "https://api.example.com", capturedReq.Claims.Aud)
		require.Equal(t, "user:789", capturedReq.Claims.Sub)
		require.Equal(t, "agent:101", capturedReq.Claims.Act.Sub)

		// Verify jti is set and is a valid UUID
		jti, ok := capturedReq.Claims.AdditionalClaims["jti"]
		require.True(t, ok, "jti must be present in AdditionalClaims")
		_, err = uuid.Parse(jti)
		require.NoError(t, err, "jti must be a valid UUID")

		// Verify original claims are preserved alongside jti
		require.Equal(t, "owner/repo", capturedReq.Claims.AdditionalClaims["repo"])
		require.Equal(t, "ci", capturedReq.Claims.AdditionalClaims["workflow"])
	})

	t.Run("returns error when identity manager fails", func(t *testing.T) {
		mock := &mockIdentityManager{
			issueIdentityTokenFn: func(_ context.Context, _ *client.IssueIdentityTokenRequest) (*client.IssueIdentityTokenResponse, error) {
				return nil, errors.New("authnd unavailable")
			},
		}
		c := &Client{identityManager: mock, obsv: observability.NewNoopExporters()}

		token, err := c.IssueIdentityToken(context.Background(), IssueIdentityTokenRequest{
			Aud: "https://example.com",
			Sub: "user:123",
		})
		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to issue identity token")
		require.Contains(t, err.Error(), "authnd unavailable")
		require.Empty(t, token)
	})

	t.Run("handles additional claims as nil", func(t *testing.T) {
		var capturedReq *client.IssueIdentityTokenRequest
		mock := &mockIdentityManager{
			issueIdentityTokenFn: func(_ context.Context, req *client.IssueIdentityTokenRequest) (*client.IssueIdentityTokenResponse, error) {
				capturedReq = req
				return &client.IssueIdentityTokenResponse{Token: "token-no-extra-claims"}, nil
			},
		}
		c := &Client{identityManager: mock, obsv: observability.NewNoopExporters()}

		token, err := c.IssueIdentityToken(context.Background(), IssueIdentityTokenRequest{
			Aud: "https://example.com",
			Sub: "user:123",
			Act: ActorClaims{Sub: "actor:456"},
		})
		require.NoError(t, err)
		require.Equal(t, "token-no-extra-claims", token)

		// Even with nil AdditionalClaims, jti should be set
		require.NotNil(t, capturedReq.Claims.AdditionalClaims)
		jti, ok := capturedReq.Claims.AdditionalClaims["jti"]
		require.True(t, ok, "jti must be present in AdditionalClaims")
		_, err = uuid.Parse(jti)
		require.NoError(t, err, "jti must be a valid UUID")
		require.Len(t, capturedReq.Claims.AdditionalClaims, 1, "only jti should be present")
	})

	t.Run("sets oidcJWTLifetime on the request", func(t *testing.T) {
		var capturedReq *client.IssueIdentityTokenRequest
		mock := &mockIdentityManager{
			issueIdentityTokenFn: func(_ context.Context, req *client.IssueIdentityTokenRequest) (*client.IssueIdentityTokenResponse, error) {
				capturedReq = req
				return &client.IssueIdentityTokenResponse{Token: "token-with-lifetime"}, nil
			},
		}
		c := &Client{identityManager: mock, obsv: observability.NewNoopExporters()}

		_, err := c.IssueIdentityToken(context.Background(), IssueIdentityTokenRequest{
			Aud: "https://example.com",
			Sub: "user:123",
		})
		require.NoError(t, err)
		require.NotNil(t, capturedReq)
		require.Equal(t, 5*time.Minute, capturedReq.Lifetime, "lifetime must be set to oidcJWTLifetime (5 minutes)")
	})

	t.Run("generates unique jti for each call", func(t *testing.T) {
		var jtis []string
		mock := &mockIdentityManager{
			issueIdentityTokenFn: func(_ context.Context, req *client.IssueIdentityTokenRequest) (*client.IssueIdentityTokenResponse, error) {
				jtis = append(jtis, req.Claims.AdditionalClaims["jti"])
				return &client.IssueIdentityTokenResponse{Token: "token"}, nil
			},
		}
		c := &Client{identityManager: mock, obsv: observability.NewNoopExporters()}

		for range 3 {
			_, err := c.IssueIdentityToken(context.Background(), IssueIdentityTokenRequest{
				Aud:              "https://example.com",
				Sub:              "user:123",
				AdditionalClaims: map[string]string{},
			})
			require.NoError(t, err)
		}
		require.Len(t, jtis, 3)
		require.NotEqual(t, jtis[0], jtis[1])
		require.NotEqual(t, jtis[1], jtis[2])
		require.NotEqual(t, jtis[0], jtis[2])
	})
}
