package identity

import (
	"testing"
	"time"

	"github.com/github/authnd/client"
	"github.com/stretchr/testify/assert"
)

func TestNewUserActorNoContext(t *testing.T) {
	userID := uint64(12345)
	userActor := NewUserActorNoContext(userID)

	assert.NotNil(t, userActor)
	assert.Equal(t, userActor.ID(), userID)
	assert.Equal(t, userActor.Type(), ActorTypeUser)
	assert.Equal(t, userActor.AuthenticatedCredentialType(), client.CredentialTypeUnknown)
	assert.Nil(t, userActor.ActorContext())
}

func TestNewUserActorViaUserToServerToken(t *testing.T) {
	userID := uint64(12345)
	applicationID := uint64(1)
	applicationOwnerID := uint64(67890)
	applicationOwnerType := ApplicationOwnerTypeUser
	oauthAccessID := uint64(222)

	userActor := NewUserActorViaUserToServerToken(userID, applicationID, applicationOwnerID, applicationOwnerType, oauthAccessID, nil)

	assert.NotNil(t, userActor)
	assert.Equal(t, userActor.ID(), userID)
	assert.Equal(t, userActor.Type(), ActorTypeUser)
	assert.Equal(t, userActor.AuthenticatedCredentialType(), client.CredentialTypeUserToServerToken)

	ctx, ok := userActor.ActorContext().(*UserToServerActorContext)
	assert.True(t, ok)
	assert.NotNil(t, ctx.OauthAccess)
	assert.Equal(t, ctx.OauthAccess.OauthAccessID, oauthAccessID)
	assert.Equal(t, ctx.OauthAccess.Application.ID, applicationID)
	assert.Equal(t, ctx.OauthAccess.Application.OwnerID, applicationOwnerID)
	assert.Equal(t, ctx.OauthAccess.Application.OwnerType, applicationOwnerType)
	assert.Equal(t, ctx.OauthAccess.Application.Type, ApplicationTypeIntegration)
}

func TestNewUserActorViaOauthApplicationAccessToken(t *testing.T) {
	userID := uint64(12345)
	applicationID := uint64(1)
	applicationOwnerID := uint64(67890)
	applicationOwnerType := ApplicationOwnerTypeOrganization
	oauthAccessID := uint64(333)
	scopes := []string{"repo", "read:org"}

	userActor := NewUserActorViaOauthApplicationAccessToken(userID, applicationID, applicationOwnerID, applicationOwnerType, oauthAccessID, scopes, nil)

	assert.NotNil(t, userActor)
	assert.Equal(t, userActor.ID(), userID)
	assert.Equal(t, userActor.Type(), ActorTypeUser)
	assert.Equal(t, userActor.AuthenticatedCredentialType(), client.CredentialTypeOauthApplicationAccessToken)

	ctx, ok := userActor.ActorContext().(*OauthAccessContext)
	assert.True(t, ok)
	assert.Equal(t, ctx.OauthAccessID, oauthAccessID)
	assert.ElementsMatch(t, ctx.Scopes, scopes)
	assert.Equal(t, ctx.Application.ID, applicationID)
	assert.Equal(t, ctx.Application.OwnerID, applicationOwnerID)
	assert.Equal(t, ctx.Application.OwnerType, applicationOwnerType)
	assert.Equal(t, ctx.Application.Type, ApplicationTypeOauthApplication)
}

func TestNewUserActorViaFineGrainedPersonalAccessToken(t *testing.T) {
	userID := uint64(12345)
	programmaticAccessID := uint64(444)
	issuedAt := time.Now()
	expiresAt := time.Now().Add(24 * time.Hour)

	userActor := NewUserActorViaFineGrainedPersonalAccessToken(userID, programmaticAccessID, issuedAt, &expiresAt, nil)

	assert.NotNil(t, userActor)
	assert.Equal(t, userActor.ID(), userID)
	assert.Equal(t, userActor.Type(), ActorTypeUser)
	assert.Equal(t, userActor.AuthenticatedCredentialType(), client.CredentialTypeFineGrainedPersonalAccessToken)

	ctx, ok := userActor.ActorContext().(*FineGrainedPersonalAccessTokenActorContext)
	assert.True(t, ok)
	assert.Equal(t, ctx.ProgrammaticAccessID, programmaticAccessID)
	assert.Equal(t, ctx.IssuedAt, issuedAt)
	assert.Equal(t, ctx.ExpiresAt, &expiresAt)
}

func TestNewUserActorViaLegacyPersonalAccessToken(t *testing.T) {
	userID := uint64(12345)
	oauthAccessID := uint64(555)
	scopes := []string{"repo", "admin:org"}
	createdAt := time.Now().Add(-24 * time.Hour)
	issuedAt := time.Now().Add(-1 * time.Hour)
	expiresAt := time.Now().Add(23 * time.Hour)

	userActor := NewUserActorViaLegacyPersonalAccessToken(userID, oauthAccessID, scopes, createdAt, &issuedAt, &expiresAt, nil)

	assert.NotNil(t, userActor)
	assert.Equal(t, userActor.ID(), userID)
	assert.Equal(t, userActor.Type(), ActorTypeUser)
	assert.Equal(t, userActor.AuthenticatedCredentialType(), client.CredentialTypeLegacyPersonalAccessToken)

	ctx, ok := userActor.ActorContext().(*OauthAccessContext)
	assert.True(t, ok)
	assert.Equal(t, ctx.OauthAccessID, oauthAccessID)
	assert.ElementsMatch(t, ctx.Scopes, scopes)
	assert.Equal(t, ctx.CreatedAt, createdAt)
	assert.Equal(t, ctx.IssuedAt, &issuedAt)
	assert.Equal(t, ctx.ExpiresAt, &expiresAt)
}

func TestNewUserActorViaSSHPublicKey(t *testing.T) {
	userID := uint64(12345)
	publicKeyID := uint64(666)

	userActor := NewUserActorViaSSHPublicKey(userID, publicKeyID, nil)

	assert.NotNil(t, userActor)
	assert.Equal(t, userActor.ID(), userID)
	assert.Equal(t, userActor.Type(), ActorTypeUser)
	assert.Equal(t, userActor.AuthenticatedCredentialType(), client.CredentialTypeSSHPublicKey)

	ctx, ok := userActor.ActorContext().(*SSHPublicKeyContext)
	assert.True(t, ok)
	assert.Equal(t, ctx.PublicKeyID, publicKeyID)
}

func TestUserActorOauthAccess(t *testing.T) {
	userID := uint64(12345)
	applicationID := uint64(1)
	applicationOwnerID := uint64(67890)
	applicationOwnerType := ApplicationOwnerTypeUser
	oauthAccessID := uint64(222)

	userActor := NewUserActorViaUserToServerToken(userID, applicationID, applicationOwnerID, applicationOwnerType, oauthAccessID, nil)

	// Test when authenticatedCredentialType is UserToServerToken
	oauthContext, err := userActor.OauthAccess()
	assert.NoError(t, err)
	assert.NotNil(t, oauthContext)
	assert.Equal(t, oauthContext.OauthAccessID, oauthAccessID)

	// Test when authenticatedCredentialType is OauthApplicationAccessToken
	userActor = NewUserActorViaOauthApplicationAccessToken(userID, applicationID, applicationOwnerID, applicationOwnerType, oauthAccessID, nil, nil)

	oauthContext, err = userActor.OauthAccess()
	assert.NoError(t, err)
	assert.NotNil(t, oauthContext)
	assert.Equal(t, oauthContext.OauthAccessID, oauthAccessID)

	// Test when authenticatedCredentialType is LegacyPersonalAccessToken
	userActor = NewUserActorViaLegacyPersonalAccessToken(userID, oauthAccessID, nil, time.Now(), nil, nil, nil)

	oauthContext, err = userActor.OauthAccess()
	assert.NoError(t, err)
	assert.NotNil(t, oauthContext)
	assert.Equal(t, oauthContext.OauthAccessID, oauthAccessID)

	// Test when there is no valid OAuth context
	userActor = NewUserActorNoContext(userID)
	oauthContext, err = userActor.OauthAccess()
	assert.NoError(t, err)
	assert.Nil(t, oauthContext)
}
