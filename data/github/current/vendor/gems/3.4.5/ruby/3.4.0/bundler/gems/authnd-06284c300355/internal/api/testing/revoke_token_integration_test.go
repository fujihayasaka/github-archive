//go:build db

package testing

import (
	"context"
	"sort"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	creds "github.com/github/authnd/internal/api/credentials"
	schema "github.com/github/authnd/internal/common/publisher/hydro/schemas/authnd/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/golang/protobuf/proto"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRevokeByCredentials_LegacyPrATToken(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestCredentialManagerServer(t, store, nil)

	credentialManager, _ := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value), // success
		pb.NewAccessTokenCredential(testfixtures.ExpiredLegacyProgrammaticAccessTokenPlainText.Value),  // success
		pb.NewAccessTokenCredential(testfixtures.RevokedLegacyProgrammaticAccessTokenPlainText.Value),  // already revoked
		pb.NewAccessTokenCredential(testfixtures.NotFoundToken.Value),                                  // not found
		pb.NewAccessTokenCredential("invalid"),                                                         // general failure
	}

	req := &pb.RevokeRequest{
		Reason: "integration-test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := revokeTokenWithRequestOptions(credentialManager, req)
	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 5)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[1].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_ALREADY_REVOKED, resp.Responses[2].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_NOT_FOUND, resp.Responses[3].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_NOT_SUPPORTED, resp.Responses[4].Result)

	// check that all the credentials we just revoked are actually revoked
	authServer := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(authServer.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	authResp, err := AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	assert.False(t, authResp.Succeeded())
	assert.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED, authResp.Result)

	// expired actually takes precedence over revoked
	authResp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.ExpiredLegacyProgrammaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	assert.False(t, authResp.Succeeded())
	assert.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, authResp.Result)
}

func TestRevokeById_LegacyPrATToken(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestCredentialManagerServer(t, store, nil)

	credentialManager, _ := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))

	ids := []int64{
		int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.ID), // success
		int64(testfixtures.ExpiredLegacyProgrammaticAccessToken.ID),  // success
		int64(testfixtures.RevokedLegacyProgrammaticAccessToken.ID),  // already revoked
		int64(99999), // not found
	}

	req := &pb.RevokeRequest{
		Reason: "integration-test",
		Kind: &pb.RevokeRequest_ById{
			ById: &pb.RevokeById{
				CredentialType: pb.ProgrammaticAccessTokenType,
				CredentialIds:  ids,
			},
		},
	}
	resp, err := revokeTokenWithRequestOptions(credentialManager, req)
	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 4)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[1].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_ALREADY_REVOKED, resp.Responses[2].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_NOT_FOUND, resp.Responses[3].Result)

	// check that all the credentials we just revoked are actually revoked
	authServer := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(authServer.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	authResp, err := AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	assert.False(t, authResp.Succeeded())
	assert.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED, authResp.Result)

	// expired actually takes precedence over revoked
	authResp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.ExpiredLegacyProgrammaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	assert.False(t, authResp.Succeeded())
	assert.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, authResp.Result)
}

func TestRevokeByCredentials_PrATToken(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	messageChan := make(chan hydro.Message, 10)
	server := CreateTestCredentialManagerServer(t, store, messageChan)

	credentialManager, err := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value), // success
		pb.NewAccessTokenCredential(testfixtures.ExpiredToken.Value),   // success
		pb.NewAccessTokenCredential(testfixtures.RevokedToken.Value),   // already revoked
		pb.NewAccessTokenCredential(testfixtures.NotFoundToken.Value),  // not found
		pb.NewAccessTokenCredential("invalid"),                         // general failure
	}

	req := &pb.RevokeRequest{
		Reason: "integration-test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := revokeTokenWithRequestOptions(credentialManager, req)
	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 5)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[1].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_ALREADY_REVOKED, resp.Responses[2].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_NOT_FOUND, resp.Responses[3].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_NOT_SUPPORTED, resp.Responses[4].Result)

	// check that all the credentials we just revoked are actually revoked
	authServer := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(authServer.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	authResp, err := AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.MonalisaToken1.Value))
	require.NoError(t, err)
	assert.False(t, authResp.Succeeded())
	assert.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED, authResp.Result)

	// expired actually takes precedence over revoked
	authResp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.ExpiredToken.Value))
	require.NoError(t, err)
	assert.False(t, authResp.Succeeded())
	assert.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, authResp.Result)

	// verify that prat notification events were published to hydro
	close(messageChan)
	var events []schema.ProgrammaticAccessEvent
	for msg := range messageChan {
		assert.Equal(t, msg.Topic, "authnd.credential.development.v0.ProgrammaticAccess.Event")
		var event schema.ProgrammaticAccessEvent
		err = proto.Unmarshal(GetEnvelope(t, msg.Value).Message, &event)
		require.NoError(t, err, "failed to unwrap event envelope")
		events = append(events, event)
	}
	require.Len(t, events, 2)

	sort.Slice(events, func(i, j int) bool {
		return events[i].CredentialId < events[j].CredentialId
	})

	message := events[0]
	require.Equal(t, testfixtures.MonalisaUser.ID, message.ActorId)
	require.Equal(t, int64(testfixtures.MonalisaProgrammaticAccessToken.MintTokenCommon.ID), message.CredentialId)
	require.InDelta(t, testfixtures.MonalisaProgrammaticAccessToken.ExpiresAt.ToProto().Seconds, message.CredentialExpiresAtUtc.Seconds, 1)
	require.Equal(t, "REVOKED", message.EventType.String())
	require.Equal(t, "integration-test", message.EventReason)
	require.Equal(t, true, message.SendNotification)
	if commonTesting.IsProximaMode() {
		require.Equal(t, int64(testfixtures.DefaultBusiness.ID), message.TenantId)
	}

	message = events[1]
	require.Equal(t, testfixtures.MonalisaUser.ID, message.ActorId)
	require.Equal(t, int64(testfixtures.ExpiredProgrammaticAccessToken.MintTokenCommon.ID), message.CredentialId)
	require.Equal(t, testfixtures.ExpiredProgrammaticAccessToken.ExpiresAt.ToProto(), message.CredentialExpiresAtUtc)
	require.Equal(t, "REVOKED", message.EventType.String())
	require.Equal(t, "integration-test", message.EventReason)
	require.Equal(t, true, message.SendNotification)
	if commonTesting.IsProximaMode() {
		require.Equal(t, int64(testfixtures.DefaultBusiness.ID), message.TenantId)
	}
}

func TestSecretScanningRevokeByCredentials_PrATTokenShouldNotNotify(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	messageChan := make(chan hydro.Message, 10)
	server := CreateTestCredentialManagerServer(t, store, messageChan)

	credentialManager, err := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value), // success
	}

	req := &pb.RevokeRequest{
		Reason: "CredentialExposed",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := revokeTokenWithRequestOptions(credentialManager, req)
	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)

	// sleep to ensure time for messages to publish
	time.Sleep(5 * time.Millisecond)

	// verify that prat notification events were published to hydro without triggering user notification
	close(messageChan)
	var publishedMessages []hydro.Message
	for msg := range messageChan {
		publishedMessages = append(publishedMessages, msg)
	}
	require.Len(t, publishedMessages, 1)

	assert.Equal(t, publishedMessages[0].Topic, "authnd.credential.development.v0.ProgrammaticAccess.Event")
	var message schema.ProgrammaticAccessEvent
	err = proto.Unmarshal(GetEnvelope(t, publishedMessages[0].Value).Message, &message)
	require.Equal(t, testfixtures.MonalisaUser.ID, message.ActorId)
	require.Equal(t, int64(testfixtures.MonalisaProgrammaticAccessToken.MintTokenCommon.ID), message.CredentialId)
	require.InDelta(t, testfixtures.MonalisaProgrammaticAccessToken.ExpiresAt.ToProto().Seconds, message.CredentialExpiresAtUtc.Seconds, 1)
	require.Equal(t, "REVOKED", message.EventType.String())
	require.Equal(t, "CredentialExposed", message.EventReason)
	require.Equal(t, false, message.SendNotification)
}

func TestRevokeByCredentials_PrATTokenShouldBeMarked(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	messageChan := make(chan hydro.Message, 10)
	server := CreateTestCredentialManagerServer(t, store, messageChan)

	credentialManager, err := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	credentials := []*pb.Credentials{
		pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value), // success
	}

	req := &pb.RevokeRequest{
		Reason: "integration-test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	token, err := store.FindProgrammaticAccessTokenByID(context.Background(), testfixtures.MonalisaProgrammaticAccessToken.MintTokenCommon.ID)
	assert.Equal(t, token.LastEventAt.Valid, false)

	reqTime := time.Now().UTC()
	resp, err := revokeTokenWithRequestOptions(credentialManager, req)
	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 1)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)

	// sleep to ensure time for messages to publish
	time.Sleep(15 * time.Millisecond)

	// verify that prat notification events were published to hydro without triggering user notification
	close(messageChan)
	var publishedMessages []hydro.Message
	for msg := range messageChan {
		publishedMessages = append(publishedMessages, msg)
	}
	require.Len(t, publishedMessages, 1)

	token, err = store.FindProgrammaticAccessTokenByID(context.Background(), testfixtures.MonalisaProgrammaticAccessToken.MintTokenCommon.ID)
	assert.True(t, token.LastEventAt.Valid)
	assert.True(t, token.LastEventAt.Time.Before(reqTime.Add(1*time.Second)))
	assert.True(t, token.LastEventAt.Time.After(reqTime.Add(-1*time.Second)))
}

func TestRevokeById_PrATToken(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	messageChan := make(chan hydro.Message, 10)
	server := CreateTestCredentialManagerServer(t, store, messageChan)

	credentialManager, err := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	ids := []int64{
		int64(testfixtures.MonalisaProgrammaticAccessToken.ID), // success
		int64(testfixtures.ExpiredProgrammaticAccessToken.ID),  // success
		int64(testfixtures.RevokedProgrammaticAccessToken.ID),  // already revoked
		int64(99999), // not found
	}

	req := &pb.RevokeRequest{
		Reason: "integration-test",
		Kind: &pb.RevokeRequest_ById{
			ById: &pb.RevokeById{
				CredentialType: pb.ProgrammaticAccessTokenType,
				CredentialIds:  ids,
			},
		},
	}
	resp, err := revokeTokenWithRequestOptions(credentialManager, req)
	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, 4)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[0].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_SUCCESS, resp.Responses[1].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_ALREADY_REVOKED, resp.Responses[2].Result)
	assert.Equal(t, pb.RevokeResponse_RESULT_NOT_FOUND, resp.Responses[3].Result)

	// check that all the credentials we just revoked are actually revoked
	authServer := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(authServer.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	authResp, err := AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.MonalisaToken1.Value))
	require.NoError(t, err)
	assert.False(t, authResp.Succeeded())
	assert.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED, authResp.Result)

	// expired actually takes precedence over revoked
	authResp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.ExpiredToken.Value))
	require.NoError(t, err)
	assert.False(t, authResp.Succeeded())
	assert.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, authResp.Result)

	// verify that prat notification events were published to hydro
	close(messageChan)
	var events []schema.ProgrammaticAccessEvent
	for msg := range messageChan {
		assert.Equal(t, msg.Topic, "authnd.credential.development.v0.ProgrammaticAccess.Event")
		var event schema.ProgrammaticAccessEvent
		err = proto.Unmarshal(GetEnvelope(t, msg.Value).Message, &event)
		require.NoError(t, err, "failed to unwrap event envelope")
		events = append(events, event)
	}
	require.Len(t, events, 2)

	sort.Slice(events, func(i, j int) bool {
		return events[i].CredentialId < events[j].CredentialId
	})
	message := events[0]
	require.Equal(t, testfixtures.MonalisaUser.ID, message.ActorId)
	require.Equal(t, int64(testfixtures.MonalisaProgrammaticAccessToken.MintTokenCommon.ID), message.CredentialId)
	require.InDelta(t, testfixtures.MonalisaProgrammaticAccessToken.ExpiresAt.ToProto().Seconds, message.CredentialExpiresAtUtc.Seconds, 1)
	require.Equal(t, "REVOKED", message.EventType.String())
	require.Equal(t, "integration-test", message.EventReason)
	require.Equal(t, true, message.SendNotification)
	if commonTesting.IsProximaMode() {
		require.Equal(t, int64(testfixtures.DefaultBusiness.ID), message.TenantId)
	}

	message = events[1]
	require.Equal(t, testfixtures.MonalisaUser.ID, message.ActorId)
	require.Equal(t, int64(testfixtures.ExpiredProgrammaticAccessToken.MintTokenCommon.ID), message.CredentialId)
	require.Equal(t, testfixtures.ExpiredProgrammaticAccessToken.ExpiresAt.ToProto(), message.CredentialExpiresAtUtc)
	require.Equal(t, "REVOKED", message.EventType.String())
	require.Equal(t, "integration-test", message.EventReason)
	require.Equal(t, true, message.SendNotification)
	if commonTesting.IsProximaMode() {
		require.Equal(t, int64(testfixtures.DefaultBusiness.ID), message.TenantId)
	}
}

func TestRevokeByCredentials_MaxBatchSizeExceeded(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestCredentialManagerServer(t, store, nil)

	credentialManager, _ := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))

	credentials := make([]*pb.Credentials, 0, creds.MaxRevokeBatchSize+1)
	for i := 0; i < creds.MaxRevokeBatchSize+1; i++ {
		credentials = append(credentials, pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value))
	}

	req := &pb.RevokeRequest{
		Reason: "integration-test",
		Kind: &pb.RevokeRequest_ByCredential{
			ByCredential: &pb.RevokeByCredential{
				Credentials: credentials,
			},
		},
	}
	resp, err := revokeTokenWithRequestOptions(credentialManager, req)
	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, creds.MaxRevokeBatchSize+1)
	for i := 0; i < creds.MaxRevokeBatchSize+1; i++ {
		assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_MAX_BATCH_SIZE_EXCEEDED, resp.Responses[i].Result)
	}
}

func TestRevokeByID_MaxBatchSizeExceeded(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestCredentialManagerServer(t, store, nil)

	credentialManager, _ := client.NewCredentialManager(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))

	ids := make([]int64, 0, creds.MaxRevokeBatchSize+1)
	for i := 0; i < creds.MaxRevokeBatchSize+1; i++ {
		ids = append(ids, int64(testfixtures.MonalisaProgrammaticAccessToken.ID))
	}

	req := &pb.RevokeRequest{
		Reason: "integration-test",
		Kind: &pb.RevokeRequest_ById{
			ById: &pb.RevokeById{
				CredentialType: pb.ProgrammaticAccessTokenType,
				CredentialIds:  ids,
			},
		},
	}
	resp, err := revokeTokenWithRequestOptions(credentialManager, req)
	assert.NoError(t, err)
	require.NotNil(t, resp)
	require.Len(t, resp.Responses, creds.MaxRevokeBatchSize+1)
	for i := 0; i < creds.MaxRevokeBatchSize+1; i++ {
		assert.Equal(t, pb.RevokeResponse_RESULT_FAILED_MAX_BATCH_SIZE_EXCEEDED, resp.Responses[i].Result)
	}
}

func revokeTokenWithRequestOptions(credentialManager client.CredentialManager, req *pb.RevokeRequest) (*pb.BatchRevokeResponse, error) {
	if commonTesting.IsProximaMode() {
		return credentialManager.RevokeCredentials(context.Background(), req,
			client.WithTenant(int(testfixtures.DefaultBusiness.ID), testfixtures.DefaultBusiness.Shortcode))
	}

	return credentialManager.RevokeCredentials(context.Background(), req)
}
