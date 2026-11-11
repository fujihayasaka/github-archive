package authnd

import (
	"testing"

	"github.com/github/authnd/client"
	"github.com/stretchr/testify/require"
)

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
