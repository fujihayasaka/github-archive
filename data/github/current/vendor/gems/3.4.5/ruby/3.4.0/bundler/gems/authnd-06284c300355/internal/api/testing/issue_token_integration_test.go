//go:build db

package testing

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	schema "github.com/github/authnd/internal/common/publisher/hydro/schemas/authnd/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/github/authnd/internal/common/tokens/fgpat"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/golang/protobuf/proto"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestIssuePrATToken(t *testing.T) {
	// create seeded DB store
	store := testfixtures.CreateTestDatabaseStore(t, true)

	// issue the token
	messageChan := make(chan hydro.Message, 10)
	testTwirpServer := CreateTestCredentialManagerServer(t, store, messageChan)
	credentialManager, err := client.NewCredentialManager(testTwirpServer.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", testfixtures.MonalisaUser.ID),
			pb.NewInt64Attribute("access.id", 12),
			pb.NewStringAttribute("actor.type", "User"),
			pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, time.Now().Add(time.Hour*24*7)),
		},
	}
	resp, err := issueTokenWithRequestOptions(credentialManager, req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.IssueTokenResponse_RESULT_SUCCESS, resp.Result)

	// verify new PRAT tokens are issued with the `github_pat_` prefix
	parts := strings.Split(resp.Token, "_")
	prefix, tokenType := parts[0], parts[1]
	require.Equal(t, string(fgpat.V1Prefix), prefix)
	require.Equal(t, "pat", tokenType)

	// verify the authnd client can validate the checksum
	require.True(t, client.IsAuthndToken(resp.Token))
	require.True(t, client.IsChecksumValid(resp.Token))

	// verify the token can be authenticated
	testTwirpServer = CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(testTwirpServer.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)
	authResp, err := AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(resp.Token))
	require.NoError(t, err)
	require.True(t, authResp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_SUCCESS, authResp.Result)

	// verify that prat notification events were published to hydro
	close(messageChan)
	var publishedMessages []hydro.Message
	for msg := range messageChan {
		publishedMessages = append(publishedMessages, msg)
	}
	assert.Equal(t, len(publishedMessages), 1)

	if len(publishedMessages) == 1 {
		assert.Equal(t, publishedMessages[0].Topic, "authnd.credential.development.v0.ProgrammaticAccess.Event")
		var message schema.ProgrammaticAccessEvent
		err = proto.Unmarshal(GetEnvelope(t, publishedMessages[0].Value).Message, &message)
		require.Equal(t, int64(testfixtures.MonalisaUser.ID), message.ActorId)
		require.Equal(t, resp.TokenId, message.CredentialId)
		require.Equal(t, "ISSUED", message.EventType.String())
		require.Equal(t, "IssueProgrammaticAccessToken", message.EventReason)
		require.Equal(t, resp.ExpiresAtTime, message.CredentialExpiresAtUtc)
		require.Equal(t, true, message.SendNotification)
		if commonTesting.IsProximaMode() {
			require.Equal(t, int64(testfixtures.DefaultBusiness.ID), message.TenantId)
		}
	}
}

func TestIssuePrATTokenUnknownUser(t *testing.T) {
	// create seeded DB store
	store := testfixtures.CreateTestDatabaseStore(t, true)

	// issue the token
	messageChan := make(chan hydro.Message, 10)
	testTwirpServer := CreateTestCredentialManagerServer(t, store, messageChan)
	credentialManager, err := client.NewCredentialManager(testTwirpServer.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", testfixtures.UnknownUser.ID),
			pb.NewInt64Attribute("access.id", 12),
			pb.NewStringAttribute("actor.type", "User"),
			pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, time.Now().Add(time.Hour*24*7)),
		},
	}
	resp, err := issueTokenWithRequestOptions(credentialManager, req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// we only lookup and assert user existence in proxima mode
	if commonTesting.IsProximaMode() {
		require.Equal(t, pb.IssueTokenResponse_RESULT_FAILED_USER_UNKNOWN, resp.Result)
	} else {
		require.Equal(t, pb.IssueTokenResponse_RESULT_SUCCESS, resp.Result)
	}
}

func TestIssuePrATTokenSuspendedUser(t *testing.T) {
	// create seeded DB store
	store := testfixtures.CreateTestDatabaseStore(t, true)

	// issue the token
	messageChan := make(chan hydro.Message, 10)
	testTwirpServer := CreateTestCredentialManagerServer(t, store, messageChan)
	credentialManager, err := client.NewCredentialManager(testTwirpServer.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", testfixtures.SuspendedUser.ID),
			pb.NewInt64Attribute("access.id", 12),
			pb.NewStringAttribute("actor.type", "User"),
			pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, time.Now().Add(time.Hour*24*7)),
		},
	}
	resp, err := issueTokenWithRequestOptions(credentialManager, req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	// we only lookup and assert user existence in proxima mode
	if commonTesting.IsProximaMode() {
		require.Equal(t, pb.IssueTokenResponse_RESULT_FAILED_USER_SUSPENDED, resp.Result)
	} else {
		require.Equal(t, pb.IssueTokenResponse_RESULT_SUCCESS, resp.Result)
	}
}

func TestAuthndTesterIssuePrATTokenShouldNotNotify(t *testing.T) {
	// create seeded DB store
	store := testfixtures.CreateTestDatabaseStore(t, true)

	// issue the token
	messageChan := make(chan hydro.Message, 10)
	testTwirpServer := CreateTestCredentialManagerServer(t, store, messageChan)
	credentialManager, err := client.NewCredentialManager(testTwirpServer.URL, "authnd_tester", client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	req := &pb.IssueTokenRequest{
		Type: pb.ProgrammaticAccessTokenType,
		Attributes: []*pb.Attribute{
			pb.NewInt64Attribute("actor.id", testfixtures.MonalisaUser.ID),
			pb.NewInt64Attribute("access.id", 12),
			pb.NewStringAttribute("actor.type", "User"),
			pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, time.Now().Add(time.Hour*24*7)),
		},
	}
	resp, err := issueTokenWithRequestOptions(credentialManager, req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.IssueTokenResponse_RESULT_SUCCESS, resp.Result)

	time.Sleep(5 * time.Millisecond)

	// verify that prat notification events were published to hydro without triggering user notification
	close(messageChan)
	var publishedMessages []hydro.Message
	for msg := range messageChan {
		publishedMessages = append(publishedMessages, msg)
	}
	assert.Equal(t, len(publishedMessages), 1)

	if len(publishedMessages) == 1 {
		assert.Equal(t, publishedMessages[0].Topic, "authnd.credential.development.v0.ProgrammaticAccess.Event")
		var message schema.ProgrammaticAccessEvent
		err = proto.Unmarshal(GetEnvelope(t, publishedMessages[0].Value).Message, &message)
		require.Equal(t, int64(testfixtures.MonalisaUser.ID), message.ActorId)
		require.Equal(t, resp.TokenId, message.CredentialId)
		require.Equal(t, "ISSUED", message.EventType.String())
		require.Equal(t, "IssueProgrammaticAccessToken", message.EventReason)
		require.Equal(t, resp.ExpiresAtTime, message.CredentialExpiresAtUtc)
		require.Equal(t, false, message.SendNotification)
		if commonTesting.IsProximaMode() {
			require.Equal(t, int64(testfixtures.DefaultBusiness.ID), message.TenantId)
		}
	}
}

func issueTokenWithRequestOptions(credentialManager client.CredentialManager, req *pb.IssueTokenRequest) (*pb.IssueTokenResponse, error) {
	if commonTesting.IsProximaMode() {
		return credentialManager.IssueToken(context.Background(), req,
			client.WithTenant(int(testfixtures.DefaultBusiness.ID), testfixtures.DefaultBusiness.Shortcode))
	}

	return credentialManager.IssueToken(context.Background(), req)
}
