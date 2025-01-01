package credentials

import (
	"context"
	"testing"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFindCredentials_UnsupportedTokenType(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.FindCredentialsRequest{
		Type:       "NotAKnownTokenType",
		Attributes: []*pb.Attribute{},
	}
	resp, err := c.FindCredentials(context.Background(), req)

	require.NoError(t, err)
	assert.Equal(t, pb.FindCredentialsResponse_RESULT_FAILED_NOT_SUPPORTED, resp.Result)
	assert.Equal(t, "specified credential type 'NotAKnownTokenType' is not supported", resp.Error)
	assert.Empty(t, resp.Credentials)
}

func TestFindCredentials_MissingRequiredAttribute(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.FindCredentialsRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, 42),
		},
	}
	resp, err := c.FindCredentials(context.Background(), req)

	require.NoError(t, err)
	assert.Equal(t, pb.FindCredentialsResponse_RESULT_FAILED_INVALID_ATTRIBUTES, resp.Result)
	assert.Equal(t, "attribute 'actor.type' is required", resp.Error)
	assert.Empty(t, resp.Credentials)
}

func TestFindCredentials_UnsupportedAttribute(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.FindCredentialsRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, 42),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewStringAttribute("cat", "tabby"),
		},
	}
	resp, err := c.FindCredentials(context.Background(), req)

	require.NoError(t, err)
	assert.Equal(t, pb.FindCredentialsResponse_RESULT_FAILED_INVALID_ATTRIBUTES, resp.Result)
	assert.Equal(t, "attribute id 'cat' cannot be used in a FindCredentials query", resp.Error)
	assert.Empty(t, resp.Credentials)
}

func TestFindCredentials_ByActor_NoResults(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.FindCredentialsRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, 42),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		},
	}
	resp, err := c.FindCredentials(context.Background(), req)

	require.NoError(t, err)
	assert.Equal(t, pb.FindCredentialsResponse_RESULT_SUCCESS, resp.Result)
	assert.Empty(t, resp.Error)
	assert.Len(t, resp.Credentials, 0)
}

func TestFindCredentials_ByActor_SomeResults(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.FindCredentialsRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.FindCredentialsUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		},
	}
	resp, err := c.FindCredentials(context.Background(), req)

	require.NoError(t, err)
	assert.Equal(t, pb.FindCredentialsResponse_RESULT_SUCCESS, resp.Result)
	assert.Empty(t, resp.Error)
	require.Len(t, resp.Credentials, 8)
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsLegacyAccess1NoCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsLegacyAccess1NoCat.TokenSuffix)),
		},
	}, resp.Credentials[0])
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsLegacyAccess1WithCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsLegacyAccess1WithCat.TokenSuffix)),
			pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.FindCredentialsLegacyAccess1WithCat.ExpiresAt.Time),
		},
	}, resp.Credentials[1])
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsLegacyAccess2NoCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsLegacyAccess2NoCat.TokenSuffix)),
		},
	}, resp.Credentials[2])
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsLegacyAccess2WithCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsLegacyAccess2WithCat.TokenSuffix)),
		},
	}, resp.Credentials[3])
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsAccess1NoCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsAccess1NoCat.TokenSuffix)),
		},
	}, resp.Credentials[4])
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsAccess1WithCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsAccess1WithCat.TokenSuffix)),
			pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.FindCredentialsAccess1WithCat.ExpiresAt.Time),
		},
	}, resp.Credentials[5])
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsAccess2NoCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsAccess2NoCat.TokenSuffix)),
		},
	}, resp.Credentials[6])
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsAccess2WithCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsAccess2WithCat.TokenSuffix)),
		},
	}, resp.Credentials[7])
}

func TestFindCredentials_ByActorAndAccess_NoResults(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.FindCredentialsRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, 42),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 42),
		},
	}
	resp, err := c.FindCredentials(context.Background(), req)

	require.NoError(t, err)
	assert.Equal(t, pb.FindCredentialsResponse_RESULT_SUCCESS, resp.Result)
	assert.Empty(t, resp.Error)
	assert.Len(t, resp.Credentials, 0)
}

func TestFindCredentials_ByActorAndAccess_SomeResults(t *testing.T) {
	c := createTestCredentialManager(t, nil)
	req := &pb.FindCredentialsRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.FindCredentialsUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 1),
		},
	}
	resp, err := c.FindCredentials(context.Background(), req)

	require.NoError(t, err)
	assert.Equal(t, pb.FindCredentialsResponse_RESULT_SUCCESS, resp.Result)
	assert.Empty(t, resp.Error)
	require.Len(t, resp.Credentials, 4)
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsLegacyAccess1NoCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsLegacyAccess1NoCat.TokenSuffix)),
		},
	}, resp.Credentials[0])
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsLegacyAccess1WithCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsLegacyAccess1WithCat.TokenSuffix)),
			pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.FindCredentialsLegacyAccess1WithCat.ExpiresAt.Time),
		},
	}, resp.Credentials[1])
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsAccess1NoCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsAccess1NoCat.TokenSuffix)),
		},
	}, resp.Credentials[2])
	assert.Equal(t, &pb.AttributeList{
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FindCredentialsAccess1WithCat.ID)),
			pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
			pb.NewStringAttribute(client.TokenSuffixAttribute, string(testfixtures.FindCredentialsAccess1WithCat.TokenSuffix)),
			pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.FindCredentialsAccess1WithCat.ExpiresAt.Time),
		},
	}, resp.Credentials[3])
}
