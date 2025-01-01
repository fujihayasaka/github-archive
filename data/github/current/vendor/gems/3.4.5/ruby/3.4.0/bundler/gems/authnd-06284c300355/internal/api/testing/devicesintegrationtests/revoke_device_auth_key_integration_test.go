//go:build db && !proxima

package devicesintegrationtests

import (
	"context"
	"database/sql"
	"errors"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	integrationTesting "github.com/github/authnd/internal/api/testing"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/require"
)

func TestRevokeDeviceAuthKeySuccess(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))

	// check DB seeded state (key exists before revoke)
	key, err := store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.UserId, testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId, time.Now())
	require.NoError(t, err)
	require.NotNil(t, key)

	require.NoError(t, err)
	req := &pb.RevokeDeviceKeyRequest{
		Kind: &pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest{
			RevokeAuthKeyRequest: &pb.RevokeDeviceAuthKeyRequest{
				OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId),
			},
		},
	}
	resp, err := mobileDeviceManager.RevokeDeviceKey(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeyResponse_RESULT_SUCCESS, resp.Result)

	// check DB state (key does not exist after revoke)
	key, err = store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.UserId, testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId, time.Now().Add(1*time.Second))
	require.True(t, errors.Is(err, common.StoreErrDeviceKeyUnexpectedRevoked))
	require.Nil(t, key)
}

func TestRevokeDeviceAuthKeySuccessForOauthAccessIdThatHasMultipleValidAuthKeys(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	// check DB seeded state (key exists before revoke)
	_, err = store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.OauthAccessId, time.Now())
	require.True(t, errors.Is(err, common.StoreErrUnexpectedMultipleResults))

	req := &pb.RevokeDeviceKeyRequest{
		Kind: &pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest{
			RevokeAuthKeyRequest: &pb.RevokeDeviceAuthKeyRequest{
				OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.OauthAccessId),
			},
		},
	}
	resp, err := mobileDeviceManager.RevokeDeviceKey(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeyResponse_RESULT_SUCCESS, resp.Result)

	// check DB state (key does not exist after revoke)
	key, err := store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.OauthAccessId, time.Now().Add(1*time.Second))
	require.True(t, errors.Is(err, common.StoreErrDeviceKeyUnexpectedRevoked))
	require.Nil(t, key)
}

func TestRevokeDeviceAuthKeyNotFoundReturnsSuccess(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	// check DB seeded state (key does not exists before revoke)
	_, err = store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, testfixtures.UserIdWithoutMobileDevicesKey, testfixtures.OauthAccessIdNotBelongingToMobileDeviceKey, time.Now())
	require.True(t, errors.Is(err, sql.ErrNoRows))

	req := &pb.RevokeDeviceKeyRequest{
		Kind: &pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest{
			RevokeAuthKeyRequest: &pb.RevokeDeviceAuthKeyRequest{
				OauthAccessId: testfixtures.OauthAccessIdNotBelongingToMobileDeviceKey,
			},
		},
	}
	resp, err := mobileDeviceManager.RevokeDeviceKey(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
}

func TestRevokeDeviceAuthKeyAlreadyRevokedReturnsSuccess(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	// check DB seeded state (key exists already revoked before revoke)
	_, err = store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, testfixtures.RevokedMobileDeviceAuthKeyForUserWithMultipleKeys.UserId, testfixtures.RevokedMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId, time.Now())
	require.True(t, errors.Is(err, common.StoreErrDeviceKeyUnexpectedRevoked))

	req := &pb.RevokeDeviceKeyRequest{
		Kind: &pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest{
			RevokeAuthKeyRequest: &pb.RevokeDeviceAuthKeyRequest{
				OauthAccessId: int64(testfixtures.RevokedMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId),
			},
		},
	}
	resp, err := mobileDeviceManager.RevokeDeviceKey(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeyResponse_RESULT_SUCCESS, resp.Result)

	// check DB state (key still revoked after revoke)
	_, err = store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, testfixtures.RevokedMobileDeviceAuthKeyForUserWithMultipleKeys.UserId, testfixtures.RevokedMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId, time.Now().Add(1*time.Second))
	require.True(t, errors.Is(err, common.StoreErrDeviceKeyUnexpectedRevoked))
}

func TestRevokeDeviceAuthKeyAlreadyExpiredReturnsSuccess(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	// check DB seeded state (key exists already expired before revoke)
	_, err = store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, testfixtures.ExpiredMobileDeviceAuthKeyForUserWithMultipleKeys.UserId, testfixtures.ExpiredMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId, time.Now())
	require.True(t, errors.Is(err, common.StoreErrDeviceKeyUnexpectedExpired))

	req := &pb.RevokeDeviceKeyRequest{
		Kind: &pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest{
			RevokeAuthKeyRequest: &pb.RevokeDeviceAuthKeyRequest{
				OauthAccessId: int64(testfixtures.ExpiredMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId),
			},
		},
	}
	resp, err := mobileDeviceManager.RevokeDeviceKey(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeyResponse_RESULT_SUCCESS, resp.Result)

	// check DB state (key still determined as "expired" meaning it hasn't been overridden as revoked)
	_, err = store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, testfixtures.ExpiredMobileDeviceAuthKeyForUserWithMultipleKeys.UserId, testfixtures.ExpiredMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId, time.Now().Add(1*time.Second))
	require.True(t, errors.Is(err, common.StoreErrDeviceKeyUnexpectedExpired))
}
