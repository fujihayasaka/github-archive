package identity

import (
	"testing"

	"github.com/github/authnd/client"
	"github.com/stretchr/testify/assert"
)

func TestActorMethods(t *testing.T) {
	actorID := uint64(123)
	attributes := map[string]interface{}{
		"key": "value",
	}

	tests := []struct {
		name           string
		actorType      ActorType
		credentialType client.CredentialType
		expectedID     uint64
		expectedType   ActorType
		expectedAttrs  map[string]interface{}
	}{
		{
			name:           "Test User Actor",
			actorType:      ActorTypeUser,
			credentialType: client.CredentialTypeOauthApplicationAccessToken,
			expectedID:     actorID,
			expectedType:   ActorTypeUser,
			expectedAttrs:  attributes,
		},
		{
			name:           "Test Bot Actor",
			actorType:      ActorTypeBot,
			credentialType: client.CredentialTypeServerToServerToken,
			expectedID:     actorID,
			expectedType:   ActorTypeBot,
			expectedAttrs:  attributes,
		},
		{
			name:           "Test Repository Actor",
			actorType:      ActorTypeRepository,
			credentialType: client.CredentialTypeSSHPublicKey,
			expectedID:     actorID,
			expectedType:   ActorTypeRepository,
			expectedAttrs:  attributes,
		},
		{
			name:           "Test Integration Actor",
			actorType:      ActorTypeIntegration,
			credentialType: client.CredentialTypeIntegrationToken,
			expectedID:     actorID,
			expectedType:   ActorTypeIntegration,
			expectedAttrs:  attributes,
		},
		{
			name:           "Test OAuth Application Actor",
			actorType:      ActorTypeOauthApplication,
			credentialType: client.CredentialTypeOauthAppClientSecret,
			expectedID:     actorID,
			expectedType:   ActorTypeOauthApplication,
			expectedAttrs:  attributes,
		},
	}

	// Iterate over test cases
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create the actor instance
			a := newBaseActor(tt.expectedID, tt.expectedType, tt.credentialType, tt.expectedAttrs)

			// Test ID
			assert.Equal(t, tt.expectedID, a.ID())

			// Test Type
			assert.Equal(t, tt.expectedType, a.Type())

			// Test AuthenticatedCredentialType
			assert.Equal(t, tt.credentialType, a.AuthenticatedCredentialType())

			// Test Attributes
			assert.Equal(t, tt.expectedAttrs, a.Attributes())
		})
	}

	// Additional tests for actor-specific methods

	t.Run("Test IsUser", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeUser, client.CredentialTypeOauthApplicationAccessToken, attributes)
		assert.True(t, a.IsUser())
	})

	t.Run("Test IsBot", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeBot, client.CredentialTypeServerToServerToken, attributes)
		assert.True(t, a.IsBot())
	})

	t.Run("Test IsRepository", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeRepository, client.CredentialTypeSSHPublicKey, attributes)
		assert.True(t, a.IsRepository())
	})

	t.Run("Test IsIntegration", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeIntegration, client.CredentialTypeIntegrationToken, attributes)
		assert.True(t, a.IsIntegration())
	})

	t.Run("Test IsOauthApplication", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeOauthApplication, client.CredentialTypeOauthAppClientSecret, attributes)
		assert.True(t, a.IsOauthApplication())
	})

	// Test authentication checks
	t.Run("Test IsAuthenticatedViaUserToServerToken", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeUser, client.CredentialTypeUserToServerToken, attributes)
		assert.True(t, a.IsAuthenticatedViaUserToServerToken())
	})

	t.Run("Test IsAuthenticatedViaOauthApplicationAccessToken", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeUser, client.CredentialTypeOauthApplicationAccessToken, attributes)
		assert.True(t, a.IsAuthenticatedViaOauthApplicationAccessToken())
	})

	t.Run("Test IsAuthenticatedViaFineGrainedPersonalAccessToken", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeUser, client.CredentialTypeFineGrainedPersonalAccessToken, attributes)
		assert.True(t, a.IsAuthenticatedViaFineGrainedPersonalAccessToken())
	})

	t.Run("Test IsAuthenticatedViaLegacyPersonalAccessToken", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeUser, client.CredentialTypeLegacyPersonalAccessToken, attributes)
		assert.True(t, a.IsAuthenticatedViaLegacyPersonalAccessToken())
	})

	t.Run("Test IsAuthenticatedViaSSHPublicKey for user", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeUser, client.CredentialTypeSSHPublicKey, attributes)
		assert.True(t, a.IsAuthenticatedViaSSHPublicKey())
	})

	t.Run("Test IsAuthenticatedViaSSHPublicKey for repo", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeRepository, client.CredentialTypeSSHPublicKey, attributes)
		assert.True(t, a.IsAuthenticatedViaSSHPublicKey())
	})

	t.Run("Test IsAuthenticatedViaServerToServerToken", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeBot, client.CredentialTypeServerToServerToken, attributes)
		assert.True(t, a.IsAuthenticatedViaServerToServerToken())
	})

	t.Run("Test IsAuthenticatedViaIntegrationToken", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeIntegration, client.CredentialTypeIntegrationToken, attributes)
		assert.True(t, a.IsAuthenticatedViaIntegrationToken())
	})

	t.Run("Test IsAuthenticatedViaOauthAppClientSecret", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeOauthApplication, client.CredentialTypeOauthAppClientSecret, attributes)
		assert.True(t, a.IsAuthenticatedViaOauthAppClientSecret())
	})

	t.Run("Test IsAuthenticatedViaSignedAuthToken", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeBot, client.CredentialTypeSignedAuthToken, attributes)
		assert.True(t, a.IsAuthenticatedViaSignedAuthToken())
	})

	// Test context methods (they should return nil)
	t.Run("Test OauthAccess", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeUser, client.CredentialTypeOauthApplicationAccessToken, attributes)
		oauthAccess, err := a.OauthAccess()
		assert.NoError(t, err)
		assert.Nil(t, oauthAccess)
	})

	t.Run("Test Application", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeUser, client.CredentialTypeOauthApplicationAccessToken, attributes)
		application, err := a.Application()
		assert.NoError(t, err)
		assert.Nil(t, application)
	})

	t.Run("Test SSHPublicKey", func(t *testing.T) {
		a := newBaseActor(actorID, ActorTypeRepository, client.CredentialTypeSSHPublicKey, attributes)
		sshKey, err := a.SSHPublicKey()
		assert.NoError(t, err)
		assert.Nil(t, sshKey)
	})
}
