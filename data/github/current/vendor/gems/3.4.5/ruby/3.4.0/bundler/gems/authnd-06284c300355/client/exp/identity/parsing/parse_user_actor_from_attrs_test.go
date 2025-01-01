package parsing

import (
	"testing"
	"time"

	"github.com/github/authnd/client"
	"github.com/github/authnd/client/exp/identity"
	"github.com/stretchr/testify/assert"
)

func TestParseUserActorForLegacyPersonalAccessToken_Success(t *testing.T) {
	actorID := uint64(123)
	credentialID := uint64(456)

	// Creating mock attributes
	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialScopesAttribute:    []string{"scope1", "scope2"},
			client.CredentialCreatedAtAttribute: time.Now(),
			client.CredentialIssuedAtAttribute:  time.Now().Add(-time.Hour),
			client.CredentialExpiresAtAttribute: time.Now().Add(time.Hour),
		},
	}

	// Call the function
	actor, err := parseUserActorForLegacyPersonalAccessToken(actorID, credentialID, attrs)

	// Assertions
	assert.NoError(t, err)
	assert.NotNil(t, actor)
	assert.Equal(t, actorID, actor.ID())
	assert.True(t, actor.IsAuthenticatedViaLegacyPersonalAccessToken())
	oauth, err := actor.OauthAccess()
	assert.NoError(t, err)
	assert.NotNil(t, oauth)
	assert.Equal(t, []string{"scope1", "scope2"}, oauth.Scopes)
}

func TestParseUserActorForLegacyPersonalAccessToken_MissingScopes(t *testing.T) {
	actorID := uint64(123)
	credentialID := uint64(456)

	// Creating mock attributes without scopes
	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialCreatedAtAttribute: time.Now(),
		},
	}

	// Call the function
	actor, err := parseUserActorForLegacyPersonalAccessToken(actorID, credentialID, attrs)

	// Assertions
	assert.Error(t, err)
	assert.Nil(t, actor)
	assert.Equal(t, "missing required attribute credential.scopes", err.Error())
}

func TestParseUserActorForLegacyPersonalAccessToken_MissingCreatedAt(t *testing.T) {
	actorID := uint64(123)
	credentialID := uint64(456)

	// Creating mock attributes without createdAt
	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialScopesAttribute: []string{"scope1", "scope2"},
		},
	}

	// Call the function
	actor, err := parseUserActorForLegacyPersonalAccessToken(actorID, credentialID, attrs)

	// Assertions
	assert.Error(t, err)
	assert.Nil(t, actor)
	assert.Equal(t, "missing required attribute credential.created_at_utc", err.Error())
}

func TestParseUserActorForLegacyPersonalAccessToken_MissingIssuedAt(t *testing.T) {
	actorID := uint64(123)
	credentialID := uint64(456)

	// Creating mock attributes without issuedAt
	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialScopesAttribute:    []string{"scope1", "scope2"},
			client.CredentialCreatedAtAttribute: time.Now(),
		},
	}

	// Call the function
	actor, err := parseUserActorForLegacyPersonalAccessToken(actorID, credentialID, attrs)

	// Assertions
	assert.NoError(t, err)
	assert.NotNil(t, actor)
	oauth, err := actor.OauthAccess()
	assert.NoError(t, err)
	assert.NotNil(t, oauth)
	assert.Nil(t, oauth.IssuedAt) // IssuedAt should be nil since it was missing
}

func TestParseUserActorForLegacyPersonalAccessToken_MissingExpiresAt(t *testing.T) {
	actorID := uint64(123)
	credentialID := uint64(456)

	// Creating mock attributes without expiresAt
	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialScopesAttribute:    []string{"scope1", "scope2"},
			client.CredentialCreatedAtAttribute: time.Now(),
			client.CredentialIssuedAtAttribute:  time.Now().Add(-time.Hour),
		},
	}

	// Call the function
	actor, err := parseUserActorForLegacyPersonalAccessToken(actorID, credentialID, attrs)

	// Assertions
	assert.NoError(t, err)
	assert.NotNil(t, actor)
	oauth, err := actor.OauthAccess()
	assert.NoError(t, err)
	assert.NotNil(t, oauth)
	assert.Nil(t, oauth.ExpiresAt) // ExpiresAt should be nil since it was missing
}

func TestParseUserActorForLegacyPersonalAccessToken_ExpiredCredential(t *testing.T) {
	actorID := uint64(123)
	credentialID := uint64(456)

	// Creating mock attributes where expiresAt is in the past
	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialScopesAttribute:    []string{"scope1", "scope2"},
			client.CredentialCreatedAtAttribute: time.Now(),
			client.CredentialIssuedAtAttribute:  time.Now().Add(-time.Hour),
			client.CredentialExpiresAtAttribute: time.Now().Add(-time.Hour * 2),
		},
	}

	// Call the function
	actor, err := parseUserActorForLegacyPersonalAccessToken(actorID, credentialID, attrs)

	// Assertions
	assert.NoError(t, err)
	assert.NotNil(t, actor)
	oauth, err := actor.OauthAccess()
	assert.NoError(t, err)
	assert.NotNil(t, oauth)
	assert.True(t, oauth.ExpiresAt.Before(time.Now())) // Should be expired
}

func TestParseUserActorForLegacyPersonalAccessToken_InvalidScopesFormat(t *testing.T) {
	actorID := uint64(123)
	credentialID := uint64(456)

	// Creating mock attributes with invalid scope format (string instead of list of strings)
	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialScopesAttribute:    "invalid_scope_format",
			client.CredentialCreatedAtAttribute: time.Now(),
		},
	}

	// Call the function
	actor, err := parseUserActorForLegacyPersonalAccessToken(actorID, credentialID, attrs)

	// Assertions
	assert.Error(t, err)
	assert.Nil(t, actor)
	assert.Contains(t, err.Error(), "invalid attribute type for credential.scopes, expected []string but got string") // Expecting an invalid format error for scopes
}

func TestParseUserActorForLegacyPersonalAccessToken_EmptyScopes(t *testing.T) {
	actorID := uint64(123)
	credentialID := uint64(456)

	// Creating mock attributes with empty scopes list
	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialScopesAttribute:    []string{},
			client.CredentialCreatedAtAttribute: time.Now(),
		},
	}

	// Call the function
	actor, err := parseUserActorForLegacyPersonalAccessToken(actorID, credentialID, attrs)

	// Assertions
	assert.NoError(t, err)
	oauth, err := actor.OauthAccess()
	assert.NoError(t, err)
	assert.Equal(t, []string{}, oauth.Scopes) // Expecting an empty scopes list
}

func TestParseUserActorForLegacyPersonalAccessToken_InvalidTimeFormat(t *testing.T) {
	actorID := uint64(123)
	credentialID := uint64(456)

	// Creating mock attributes with an invalid time format
	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialScopesAttribute:    []string{"scope1", "scope2"},
			client.CredentialCreatedAtAttribute: "invalid_time_format", // Invalid time format
		},
	}

	// Call the function
	actor, err := parseUserActorForLegacyPersonalAccessToken(actorID, credentialID, attrs)

	// Assertions
	assert.Error(t, err)
	assert.Nil(t, actor)
	assert.Contains(t, err.Error(), "invalid attribute type for credential.created_at_utc, expected time.Time but got string")
}

func TestParseUserActorForLegacyPersonalAccessToken_NilExpiresAndIssuedAtAttributes(t *testing.T) {
	actorID := uint64(123)
	credentialID := uint64(456)

	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialScopesAttribute:    []string{"scope1", "scope2"},
			client.CredentialCreatedAtAttribute: time.Now(),
			client.CredentialExpiresAtAttribute: nil,
			client.CredentialIssuedAtAttribute:  nil,
		},
	}

	// Call the function
	actor, err := parseUserActorForLegacyPersonalAccessToken(actorID, credentialID, attrs)

	// Assertions
	assert.NoError(t, err)
	assert.NotNil(t, actor)
	oauth, err := actor.OauthAccess()
	assert.NoError(t, err)
	assert.Nil(t, oauth.ExpiresAt)
	assert.Nil(t, oauth.IssuedAt)
}

func TestParseUserActorForFinedGrainedPersonalAccessToken_NilExpiredAtAtribute(t *testing.T) {
	actorID := uint64(123)
	accessID := int64(456)

	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.ProgrammaticAccessIDAttribute: accessID,
			client.CredentialIssuedAtAttribute:   time.Now(),
			client.CredentialExpiresAtAttribute:  nil,
		},
	}

	// Call the function
	actor, err := parseUserActorForFineGrainedPersonalAccessToken(actorID, attrs)

	// Assertions
	assert.NoError(t, err)
	assert.NotNil(t, actor)
	assert.True(t, actor.IsAuthenticatedViaFineGrainedPersonalAccessToken())
	fineGrainedPatContext := actor.ActorContext().(*identity.FineGrainedPersonalAccessTokenActorContext)
	assert.NoError(t, err)
	assert.Nil(t, fineGrainedPatContext.ExpiresAt)
}

func TestParseUserActorForSignedAuthToken_WithIntVersionAttr(t *testing.T) {
	actorID := uint64(123)
	credID := uint64(456)

	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialExpiresAtAttribute: time.Now().Add(time.Hour),
			client.CredentialVersionAttribute:   int64(1),
		},
	}

	// Call the function
	actor, err := parseUserActorForSignedAuthToken(actorID, credID, attrs)

	// Assertions
	assert.NoError(t, err)
	assert.NotNil(t, actor)
	assert.True(t, actor.IsAuthenticatedViaSignedAuthToken())
	signedAuthTokenContext := actor.ActorContext().(*identity.SignedAuthTokenActorContext)
	assert.NoError(t, err)
	assert.Equal(t, "1", signedAuthTokenContext.Version)
}

func TestParseUserActorForSignedAuthToken_WithStringVersionAttr(t *testing.T) {
	actorID := uint64(123)
	credID := uint64(456)

	attrs := &attrActorParser{
		attrs: map[string]interface{}{
			client.CredentialExpiresAtAttribute: time.Now().Add(time.Hour),
			client.CredentialVersionAttribute:   "hex",
		},
	}

	// Call the function
	actor, err := parseUserActorForSignedAuthToken(actorID, credID, attrs)

	// Assertions
	assert.NoError(t, err)
	assert.NotNil(t, actor)
	assert.True(t, actor.IsAuthenticatedViaSignedAuthToken())
	signedAuthTokenContext := actor.ActorContext().(*identity.SignedAuthTokenActorContext)
	assert.NoError(t, err)
	assert.Equal(t, "hex", signedAuthTokenContext.Version)
}
