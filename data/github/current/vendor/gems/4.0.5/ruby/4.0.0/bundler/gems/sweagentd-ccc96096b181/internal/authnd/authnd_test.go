package authnd

import (
	"testing"

	"github.com/github/authnd/client"
	"github.com/stretchr/testify/require"
)

func TestIsValidTokenFormat(t *testing.T) {
	c := &Client{}

	// Modern prefixed tokens should be valid
	require.True(t, c.IsValidTokenFormat("ghp_abc123"))
	require.True(t, c.IsValidTokenFormat("gho_abc123"))
	require.True(t, c.IsValidTokenFormat("ghu_abc123"))
	require.True(t, c.IsValidTokenFormat("github_pat_abc123"))

	// Legacy tokens should be valid
	require.True(t, c.IsValidTokenFormat("1234567890abcdef1234567890abcdef12345678"))

	// Invalid tokens should be rejected
	require.False(t, c.IsValidTokenFormat(""))
	require.False(t, c.IsValidTokenFormat("invalid_prefix"))
	require.False(t, c.IsValidTokenFormat("1234567890abcdef1234567890abcdef1234567"))
}

func TestAuthnd_SupportedTokenTypes(t *testing.T) {
	t.Skip("Not all these token types are supported yet, so this test is disabled")

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
