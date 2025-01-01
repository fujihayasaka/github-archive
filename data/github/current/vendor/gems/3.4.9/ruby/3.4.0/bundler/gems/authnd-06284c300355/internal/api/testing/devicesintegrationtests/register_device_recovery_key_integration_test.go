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
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/stretchr/testify/require"
)

func TestRegisterDeviceRecoveryKeySuccess(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, false)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
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

func TestRegisterDeviceRecoveryKeySuccessMissingDeviceNameAndModel(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, false)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         1,
				OauthAccessId:                  2,
				DeviceOs:                       "Android",
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

	deviceKey, err := store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Recovery, uint64(1), uint64(2), time.Now().Add(1*time.Second))
	require.NoError(t, err)
	require.NotNil(t, deviceKey)
	require.Equal(t, resp.Id, int64(deviceKey.ID))
	require.Equal(t, "Unknown Android Device", deviceKey.DeviceName)
	require.Equal(t, "Unknown Android Device Model", deviceKey.DeviceModel)
}

func TestRegisterDeviceRecoveryKeySuccessForOauthAccessIdThatHasValidKey(t *testing.T) {
	userId := testfixtures.ValidMobileDeviceRecoveryKey1.UserId
	oauthAccessId := testfixtures.ValidMobileDeviceRecoveryKey1.OauthAccessId

	// seed the store with mobile device key test fixtures
	store := testfixtures.CreateTestDatabaseStore(t, true)

	// verify there is an oauth access id with a valid recovery key
	deviceKey, err := store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Recovery, uint64(userId), uint64(oauthAccessId), time.Now())
	require.NoError(t, err)
	require.NotNil(t, deviceKey)
	require.Equal(t, testfixtures.ValidMobileDeviceRecoveryKey1.ID, deviceKey.ID)

	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
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
	deviceKey, err = store.FindMobileDeviceKeyByUserIdAndOauthAccessId(context.Background(), models.DeviceKeyType_Recovery, uint64(userId), uint64(oauthAccessId), time.Now().Add(1*time.Second))
	require.NoError(t, err)
	require.NotNil(t, deviceKey)
	require.Equal(t, resp.Id, int64(deviceKey.ID))
}

func TestRegisterDeviceRecoveryKeySuccessRevokesExcessiveRecoveryKeys(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, false)
	ctx := commonTesting.NewLoggerContext(t)

	lruKey := testfixtures.ValidMobileDeviceRecoveryKey1
	store.InsertMobileDeviceKey(context.Background(), lruKey.MobileDeviceKey, time.Now().UTC())

	newKeysTime := lruKey.CreatedAt.Time.Add(time.Hour)
	for i := 0; i < 49; i++ {
		newerKey := testfixtures.CreateMobileDeviceKey(uint64(100+i), lruKey.UserId, uint64(100+i), models.DeviceKeyType_Recovery, newKeysTime)
		store.InsertMobileDeviceKey(context.Background(), newerKey.MobileDeviceKey, time.Now().UTC())
	}

	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mobileDeviceManager, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RegisterDeviceKeyRequest{
		Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
			RecoveryKeyRequest: &pb.DeviceKeyRequest{
				UserId:                         int64(lruKey.UserId),
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
	resp, err := mobileDeviceManager.RegisterDeviceKey(ctx, req)
	require.Equal(t, pb.RegisterDeviceKeyResponse_RESULT_SUCCESS, resp.Result)

	var remainingKeys []*models.MobileDeviceKey
	for i := 0; i < 100; i++ {
		if len(remainingKeys) == 50 {
			break
		}

		remainingKeys, err = store.FindMobileDeviceKeysByUserId(context.Background(), models.DeviceKeyType_Recovery, lruKey.UserId, time.Now())
		time.Sleep(time.Millisecond * 4)
	}
	require.Equal(t, 50, len(remainingKeys))
	require.NotContains(t, remainingKeys, lruKey.MobileDeviceKey)
}
