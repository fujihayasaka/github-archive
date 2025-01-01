//go:build db && !proxima

package devicesintegrationtests

import (
	"context"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	integrationTesting "github.com/github/authnd/internal/api/testing"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestRevokeDeviceKeysByUserIdFailureWithMissingUserID(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{},
		},
	}

	resp, err := mdm.RevokeDeviceKeys(context.Background(), req)
	require.Nil(t, resp)
	require.NotNil(t, err)
	require.Error(t, err, twirp.RequiredArgumentError("UserId"))
}

func TestRevokeDeviceKeysByOauthAccessesSuccessWithNoOauthAccesses(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAllDeviceKeysByOauthAccessesRequest{
			RevokeAllDeviceKeysByOauthAccessesRequest: &pb.RevokeAllDeviceKeysByOauthAccessesRequest{},
		},
	}

	resp, err := mdm.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)
}

func TestRevokeDeviceKeysByIdsSuccessWithNoIds(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAllDeviceKeysByIdsRequest{
			RevokeAllDeviceKeysByIdsRequest: &pb.RevokeAllDeviceKeysByIdsRequest{},
		},
	}

	resp, err := mdm.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)
}

func TestRevokeDeviceKeysByUserIdSuccessWithNoDeviceRegisteredToUser(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{
				UserId: int64(testfixtures.UserIdWithoutMobileDevicesKey),
			},
		},
	}

	resp, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, 0, len(resp.OauthAccessIds))
}

func TestRevokeDeviceKeysByOauthAccessesSuccessWithNoDeviceRegistered(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAllDeviceKeysByOauthAccessesRequest{
			RevokeAllDeviceKeysByOauthAccessesRequest: &pb.RevokeAllDeviceKeysByOauthAccessesRequest{
				OauthAccessIds: []int64{testfixtures.OauthAccessIdNotBelongingToMobileDeviceKey},
			},
		},
	}

	resp, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)
}

func TestRevokeDeviceKeysByIdsSuccessWithNoDeviceRegistered(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAllDeviceKeysByIdsRequest{
			RevokeAllDeviceKeysByIdsRequest: &pb.RevokeAllDeviceKeysByIdsRequest{
				Ids: []int64{999},
			},
		},
	}

	resp, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)
}

func TestRevokeDeviceKeysByUserIdSuccessWithOneDeviceRegisteredToUser(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	// check DB seeded state (key exists before revoke)
	key, err := store.FindMobileDeviceKeysByUserId(context.Background(), models.DeviceKeyType_Auth, testfixtures.ValidMobileDeviceAuthKeyForUser9.UserId, time.Now())
	require.NoError(t, err)
	require.NotNil(t, key)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{
				UserId: int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.UserId),
			},
		},
	}

	resp, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, 1, len(resp.OauthAccessIds))

	// check DB state (all user device keys should not exist after revokation)
	checkAllDevicesRevoked(t, store, testfixtures.ValidMobileDeviceAuthKeyForUser9.UserId, resp.OauthAccessIds)
}

func TestRevokeDeviceKeysByOauthAccessesSuccessWithOneDeviceRegistered(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	// check DB seeded state (key exists before revoke)
	key, err := store.FindMobileDeviceKeysByUserId(context.Background(), models.DeviceKeyType_Auth, testfixtures.ValidMobileDeviceAuthKeyForUser9.UserId, time.Now())
	require.NoError(t, err)
	require.NotNil(t, key)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAllDeviceKeysByOauthAccessesRequest{
			RevokeAllDeviceKeysByOauthAccessesRequest: &pb.RevokeAllDeviceKeysByOauthAccessesRequest{
				OauthAccessIds: []int64{int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.OauthAccessId)},
			},
		},
	}

	resp, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)

	// check DB state (all user device keys should not exist after revokation)
	checkAllDevicesRevoked(t, store, testfixtures.ValidMobileDeviceAuthKeyForUser9.UserId, []int64{int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.OauthAccessId)})
}

func TestRevokeDeviceKeysByIdsSuccessWithOneDeviceRegistered(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	// check DB seeded state (key exists before revoke)
	key, err := store.FindMobileDeviceKeysByUserId(context.Background(), models.DeviceKeyType_Auth, testfixtures.ValidMobileDeviceAuthKeyForUser9.UserId, time.Now())
	require.NoError(t, err)
	require.NotNil(t, key)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAllDeviceKeysByIdsRequest{
			RevokeAllDeviceKeysByIdsRequest: &pb.RevokeAllDeviceKeysByIdsRequest{
				Ids: []int64{int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.ID)},
			},
		},
	}

	resp, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)

	// check DB state (all user device keys should not exist after revokation)
	checkAllDevicesRevoked(t, store, testfixtures.ValidMobileDeviceAuthKeyForUser9.UserId, []int64{int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.OauthAccessId)})
}

func TestRevokeDeviceKeysByUserIdSuccessWithMultipleDevicesRegisteredToUser(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	// check DB seeded state (key exists before revoke)
	key, err := store.FindMobileDeviceKeysByUserId(context.Background(), models.DeviceKeyType_Auth, testfixtures.UserIdWithMultipleValidDeviceKeys, time.Now())
	require.NoError(t, err)
	require.NotNil(t, key)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{
				UserId: int64(testfixtures.UserIdWithMultipleValidDeviceKeys),
			},
		},
	}

	resp, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, 3, len(resp.OauthAccessIds))

	// check DB state (all user device keys should not exist after revokation)
	checkAllDevicesRevoked(t, store, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId, resp.OauthAccessIds)
}

func TestRevokeDeviceKeysByOauthAccessesSuccessWithMultipleDevicesRegisteredToUser(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	// check DB seeded state (key exists before revoke)
	keys, err := store.FindMobileDeviceKeysByUserId(context.Background(), models.DeviceKeyType_Auth, testfixtures.UserIdWithMultipleValidDeviceKeys, time.Now())
	require.NoError(t, err)
	require.NotNil(t, keys)
	require.Equal(t, 3, len(keys))

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAllDeviceKeysByOauthAccessesRequest{
			RevokeAllDeviceKeysByOauthAccessesRequest: &pb.RevokeAllDeviceKeysByOauthAccessesRequest{
				OauthAccessIds: []int64{int64(testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId), int64(testfixtures.ValidMobileDeviceAuthKey2.OauthAccessId)},
			},
		},
	}

	resp, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)

	// check DB state (all user device keys should not exist after revokation)
	checkAllDevicesRevoked(t, store, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId, []int64{int64(testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId), int64(testfixtures.ValidMobileDeviceAuthKey2.OauthAccessId)})

	// check last key still valid
	keys, err = store.FindMobileDeviceKeysByUserId(context.Background(), models.DeviceKeyType_Auth, testfixtures.UserIdWithMultipleValidDeviceKeys, time.Now().Add(1*time.Minute))
	require.NoError(t, err)
	require.NotNil(t, keys)
	require.Equal(t, 1, len(keys))
}

func TestRevokeDeviceKeysByIdsSuccessWithMultipleDevicesRegisteredToUser(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	// check DB seeded state (key exists before revoke)
	keys, err := store.FindMobileDeviceKeysByUserId(context.Background(), models.DeviceKeyType_Auth, testfixtures.UserIdWithMultipleValidDeviceKeys, time.Now())
	require.NoError(t, err)
	require.NotNil(t, keys)
	require.Equal(t, 3, len(keys))

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAllDeviceKeysByIdsRequest{
			RevokeAllDeviceKeysByIdsRequest: &pb.RevokeAllDeviceKeysByIdsRequest{
				Ids: []int64{int64(testfixtures.ValidMobileDeviceAuthKey1.ID), int64(testfixtures.ValidMobileDeviceAuthKey2.ID)},
			},
		},
	}

	resp, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)

	// check DB state (all user device keys should not exist after revokation)
	checkAllDevicesRevoked(t, store, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId, []int64{int64(testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId), int64(testfixtures.ValidMobileDeviceAuthKey2.OauthAccessId)})

	// check last key still valid
	keys, err = store.FindMobileDeviceKeysByUserId(context.Background(), models.DeviceKeyType_Auth, testfixtures.UserIdWithMultipleValidDeviceKeys, time.Now().Add(1*time.Minute))
	require.NoError(t, err)
	require.NotNil(t, keys)
	require.Equal(t, 1, len(keys))
}

func TestRevokeDeviceKeysByUserIdSuccessWithDifferentDeviceKeyStates(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	// check DB seeded state (key exists before revoke)
	key, err := store.FindMobileDeviceKeysByUserId(context.Background(), models.DeviceKeyType_Auth, testfixtures.UserIdWithMultipleKeys, time.Now())
	require.NoError(t, err)
	require.NotNil(t, key)

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{
				UserId: int64(testfixtures.UserIdWithMultipleKeys),
			},
		},
	}

	resp, err := mobileDeviceManager.RevokeDeviceKeys(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RevokeDeviceKeysResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, 1, len(resp.OauthAccessIds))

	// check DB state (all user device keys should not exist after revokation)
	checkAllDevicesRevoked(t, store, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId, resp.OauthAccessIds)
}

// want to check each of the deviceKey result
func checkAllDevicesRevoked(t *testing.T, store store.Store, userId uint64, deviceKeys []int64) {
	for _, deviceKey := range deviceKeys {
		key, err := store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, userId, uint64(deviceKey), time.Now().Add(1*time.Second))
		require.Error(t, err)
		require.Nil(t, key)
	}
}
