//go:build db

package testing

import (
	"context"
	"testing"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFindCredentials_ByActor_SomeResults(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestCredentialManagerServer(t, store, nil)
	credentialManager, _ := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))

	req := &pb.FindCredentialsRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.FindCredentialsUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		},
	}
	resp, err := findCredentialsWithRequestOptions(credentialManager, req)

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

func TestFindCredentials_ByActorAndAccess_SomeResults(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestCredentialManagerServer(t, store, nil)
	credentialManager, _ := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))

	req := &pb.FindCredentialsRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.FindCredentialsUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 1),
		},
	}
	resp, err := findCredentialsWithRequestOptions(credentialManager, req)

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

func TestFindCredentials_ByActor_Unknown(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestCredentialManagerServer(t, store, nil)
	credentialManager, _ := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))

	req := &pb.FindCredentialsRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.UnknownUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		},
	}
	resp, err := findCredentialsWithRequestOptions(credentialManager, req)

	require.NoError(t, err)

	// we only lookup and assert user existence in proxima mode
	if commonTesting.IsProximaMode() {
		assert.Equal(t, pb.FindCredentialsResponse_RESULT_FAILED_USER_UNKNOWN, resp.Result)
	} else {
		assert.Equal(t, pb.FindCredentialsResponse_RESULT_SUCCESS, resp.Result)
	}
	assert.Empty(t, resp.Error)
}

func TestFindCredentials_ByActor_Suspended(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestCredentialManagerServer(t, store, nil)
	credentialManager, _ := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))

	req := &pb.FindCredentialsRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.SuspendedUser.ID),
			pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		},
	}
	resp, err := findCredentialsWithRequestOptions(credentialManager, req)

	require.NoError(t, err)
	// always success, in dotcom and proxima - we don't care if a user is suspended for find credentials
	assert.Equal(t, pb.FindCredentialsResponse_RESULT_SUCCESS, resp.Result)
	assert.Empty(t, resp.Error)
}

func findCredentialsWithRequestOptions(credentialManager client.CredentialManager, req *pb.FindCredentialsRequest) (*pb.FindCredentialsResponse, error) {
	if commonTesting.IsProximaMode() {
		return credentialManager.FindCredentials(context.Background(), req,
			client.WithTenant(int(testfixtures.DefaultBusiness.ID), testfixtures.DefaultBusiness.Shortcode))
	}

	return credentialManager.FindCredentials(context.Background(), req)
}
