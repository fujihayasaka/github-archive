package identity

import (
	"testing"

	"github.com/github/authnd/client"
	"github.com/stretchr/testify/assert"
)

func TestParseInstallationTargetType(t *testing.T) {
	tests := []struct {
		input    string
		expected InstallationTargetType
		err      bool
	}{
		{"User", InstallationTargetTypeUser, false},
		{"Organization", InstallationTargetTypeOrganization, false},
		{"Business", InstallationTargetTypeBusiness, false},
		{"InvalidType", "", true}, // Should return an error
		{"", "", true},            // Should return an error for empty input
	}

	for _, test := range tests {
		result, err := ParseInstallationTargetType(test.input)
		if test.err {
			assert.NotNil(t, err)
		} else {
			assert.Nil(t, err)
		}
		assert.Equal(t, test.expected, result)
	}
}

func TestNewBotActor(t *testing.T) {
	botID := uint64(1)
	integrationID := uint64(2)
	integrationOwnerID := uint64(3)
	integrationOwnerType := ApplicationOwnerTypeUser
	integrationContext := NewApplicationContext(integrationID, ApplicationTypeIntegration, integrationOwnerID, integrationOwnerType)

	installationID := uint64(4)
	installationContext := NewIntegrationInstallation(installationID, 5, InstallationTargetTypeOrganization)
	botActor, err := NewBotActor(botID, integrationContext, installationContext, nil)
	assert.NoError(t, err)

	assert.NotNil(t, botActor)
	assert.Equal(t, botID, botActor.ID())
	assert.Equal(t, ActorTypeBot, botActor.Type())
	assert.NotNil(t, botActor.actorContext)
	assert.Equal(t, &installationID, botActor.actorContext.Installation.InstallationID)
	assert.Equal(t, InstallationTargetTypeOrganization, botActor.actorContext.Installation.InstallationTargetType)
}

func TestBotActorAuthenticationContext(t *testing.T) {
	botID := uint64(1)
	integrationID := uint64(2)
	integrationOwnerID := uint64(3)
	integrationOwnerType := ApplicationOwnerTypeUser
	integrationContext := NewApplicationContext(integrationID, ApplicationTypeIntegration, integrationOwnerID, integrationOwnerType)

	installationID := uint64(4)
	installationContext := NewIntegrationInstallation(installationID, 5, InstallationTargetTypeOrganization)
	botActor, err := NewBotActor(botID, integrationContext, installationContext, nil)
	assert.NoError(t, err)

	authContext := botActor.ActorContext()
	assert.NotNil(t, authContext)

	botAuthContext, ok := authContext.(*BotActorContext)
	assert.True(t, ok)
	assert.Equal(t, &installationID, botAuthContext.Installation.InstallationID)
	assert.Equal(t, InstallationTargetTypeOrganization, botAuthContext.Installation.InstallationTargetType)
}

func TestBotActorApplication(t *testing.T) {
	botID := uint64(1)
	integrationID := uint64(2)
	integrationOwnerID := uint64(3)
	integrationOwnerType := ApplicationOwnerTypeUser
	integrationContext := NewApplicationContext(integrationID, ApplicationTypeIntegration, integrationOwnerID, integrationOwnerType)

	installationContext := NewIntegrationInstallation(4, 5, InstallationTargetTypeOrganization)
	botActor, err := NewBotActor(botID, integrationContext, installationContext, nil)
	assert.NoError(t, err)

	appContext, err := botActor.Application()
	assert.NoError(t, err)
	assert.NotNil(t, appContext)
	assert.Equal(t, integrationID, appContext.ID)
}

func TestBotActorAuthenticatedCredentialType(t *testing.T) {
	botID := uint64(1)
	integrationID := uint64(2)
	integrationOwnerID := uint64(3)
	integrationOwnerType := ApplicationOwnerTypeUser
	integrationContext := NewApplicationContext(integrationID, ApplicationTypeIntegration, integrationOwnerID, integrationOwnerType)

	installationContext := NewIntegrationInstallation(4, 5, InstallationTargetTypeOrganization)
	botActor, err := NewBotActor(botID, integrationContext, installationContext, nil)
	assert.NoError(t, err)
	credType := botActor.AuthenticatedCredentialType()
	assert.Equal(t, client.CredentialTypeServerToServerToken, credType)
}
