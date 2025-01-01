//go:build db && !proxima

package devicesintegrationtests

import (
	"context"
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

func TestRegisterDeviceAuthKeySuccess(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, false)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_AuthKeyRequest{
			AuthKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mobileDeviceManager.RegisterDeviceKey(context.Background(), req)

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, int64(1), resp.Id)
}

func TestRegisterDeviceAuthKeySuccessMissingDeviceNameAndModel(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, false)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_AuthKeyRequest{
			AuthKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mobileDeviceManager.RegisterDeviceKey(context.Background(), req)

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, int64(1), resp.Id)

	deviceKey, err := store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, uint64(1), uint64(2), time.Now().Add(1*time.Second))
	require.NoError(t, err)
	require.NotNil(t, deviceKey)
	require.Equal(t, resp.Id, int64(deviceKey.ID))
	require.Equal(t, "Unknown iOS Device", deviceKey.DeviceName)
	require.Equal(t, "Unknown iOS Device Model", deviceKey.DeviceModel)
}

func TestRegisterDeviceAuthKeyAllowsSamePublicKeyForSameOauthAccessId(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, false)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_AuthKeyRequest{
			AuthKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mobileDeviceManager.RegisterDeviceKey(context.Background(), req)

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, int64(1), resp.Id)

	resp, err = mobileDeviceManager.RegisterDeviceKey(context.Background(), req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, int64(2), resp.Id)
}

func TestRegisterDeviceAuthKeyDisallowsSamePublicKeyForDifferentOauthAccessId(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, false)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_AuthKeyRequest{
			AuthKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mobileDeviceManager.RegisterDeviceKey(context.Background(), req)

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, int64(1), resp.Id)

	req.GetAuthKeyRequest().OauthAccessId = 3
	resp, err = mobileDeviceManager.RegisterDeviceKey(context.Background(), req)
	require.Error(t, err)
	require.Equal(t, "twirp error internal: duplicate fingerprint", err.Error())
	require.Nil(t, resp)
}

func TestRegisterDeviceAuthKeySuccessForOauthAccessIdThatHasValidKey(t *testing.T) {
	userId := testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.UserId
	oauthAccessId := testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId

	// seed the store with mobile device key test fixtures
	store := testfixtures.CreateTestDatabaseStore(t, true)

	// verify there is an oauth access id with a valid auth key
	deviceKey, err := store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, uint64(userId), uint64(oauthAccessId), time.Now())
	require.NoError(t, err)
	require.NotNil(t, deviceKey)
	require.Equal(t, testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.ID, deviceKey.ID)

	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_AuthKeyRequest{
			AuthKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         int64(userId),
				OauthAccessId:                  int64(oauthAccessId),
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mobileDeviceManager.RegisterDeviceKey(context.Background(), req)

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, int64(len(testfixtures.MobileDeviceKeyReferences)+1), resp.Id)

	// verify the only active key is the one we just registered for this oauth access id
	deviceKey, err = store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, uint64(userId), uint64(oauthAccessId), time.Now().Add(1*time.Second))
	require.NoError(t, err)
	require.NotNil(t, deviceKey)
	require.Equal(t, resp.Id, int64(deviceKey.ID))
}

// this should never happen, but we should handle it gracefully
// this is a case where an oauth access id ends up with multiple valid device auth keys
// we protect against this at device auth key registration time
func TestRegisterDeviceAuthKeySuccessForOauthAccessIdThatHasValidKeys(t *testing.T) {
	userId := testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId
	oauthAccessId := testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.OauthAccessId

	// seed the store with mobile device key test fixtures
	store := testfixtures.CreateTestDatabaseStore(t, true)

	// verify that the store is in a state where there are two valid auth keys for the same oauth access id
	// expect the query to return unexpected multiple results error
	_, err := store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, uint64(userId), uint64(oauthAccessId), time.Now())
	require.EqualError(t, err, common.StoreErrUnexpectedMultipleResults.Error())

	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_AuthKeyRequest{
			AuthKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         int64(userId),
				OauthAccessId:                  int64(oauthAccessId),
				DeviceName:                     "mona's phone",
				DeviceModel:                    "iPhone0",
				DeviceOs:                       "iOS",
				IsHardwareBacked:               false,
				PublicKey:                      testfixtures.ValidUnregisteredMobileDeviceKey,
				PublicKeyVerificationSignature: testfixtures.ValidUnregisteredMobileDeviceKeyVerificationSignature,
				PublicKeyVerificationMessage:   testfixtures.ValidUnregisteredMobileDeviceKeyVerificationMessage,
			},
		},
	}
	resp, err := mobileDeviceManager.RegisterDeviceKey(context.Background(), req)

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, int64(len(testfixtures.MobileDeviceKeyReferences)+1), resp.Id)

	// verify the only active key is now the one we just registered for this oauth access id
	deviceKey, err := store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Auth, uint64(userId), uint64(oauthAccessId), time.Now().Add(1*time.Second))
	require.NoError(t, err)
	require.NotNil(t, deviceKey)
	require.Equal(t, resp.Id, int64(deviceKey.ID))
}

func TestRegisterDeviceAuthKeySuccessNoPublicKeyVerification(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, false)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_AuthKeyRequest{
			AuthKeyRequest: &pb.DeviceKeyRequest{
				UserId:           1,
				OauthAccessId:    2,
				DeviceName:       "mona's phone",
				DeviceModel:      "iPhone0",
				DeviceOs:         "iOS",
				IsHardwareBacked: false,
				PublicKey:        testfixtures.ValidUnregisteredMobileDeviceKey,
			},
		},
	}
	resp, err := mobileDeviceManager.RegisterDeviceKey(context.Background(), req)

	require.NoError(t, err)
	require.NotNil(t, resp)
	require.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_SUCCESS, resp.Result)
	require.Equal(t, int64(1), resp.Id)
}
