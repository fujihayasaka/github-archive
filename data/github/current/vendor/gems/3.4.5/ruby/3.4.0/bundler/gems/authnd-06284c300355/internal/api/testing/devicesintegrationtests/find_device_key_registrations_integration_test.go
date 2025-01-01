//go:build db && !proxima

package devicesintegrationtests

import (
	"context"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	integrationTesting "github.com/github/authnd/internal/api/testing"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestFindDeviceKeyRegistrationsSuccessful(t *testing.T) {
	devices := []*pb.DeviceKeyRegistration{
		{
			Id:             int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.ID),
			DeviceName:     testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceName,
			DeviceModel:    testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceModel,
			DeviceOs:       testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceOs,
			CreatedAtTime:  timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.CreatedAt.Time.Round(time.Second)),
			ExpiresAtTime:  timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.ExpiresAt.Time.Round(time.Second)),
			LastUsedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.LastUsedAt.Time.Round(time.Second)),
			OauthAccessId:  int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.OauthAccessId),
		},
	}
	testFindDeviceKeyRegistrations(t, testfixtures.ValidMobileDeviceAuthKeyForUser9.UserId, pb.FindDeviceKeyRegistrationsResponse_RESULT_SUCCESS, devices)
}

func TestFindDeviceKeyRegistrationsFiltersInvalidDevices(t *testing.T) {
	devices := []*pb.DeviceKeyRegistration{
		{
			Id:            int64(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.ID),
			DeviceName:    testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.DeviceName,
			DeviceModel:   testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.DeviceModel,
			DeviceOs:      testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.DeviceOs,
			CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.CreatedAt.Time.Round(time.Second)),
			ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.ExpiresAt.Time.Round(time.Second)),
			OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId),
		},
	}
	testFindDeviceKeyRegistrations(t, testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.UserId, pb.FindDeviceKeyRegistrationsResponse_RESULT_SUCCESS, devices)
}

func TestFindDeviceKeyRegistrationsMultipleValidDevices(t *testing.T) {
	devices := []*pb.DeviceKeyRegistration{
		{
			Id:            int64(testfixtures.ValidMobileDeviceAuthKey1.ID),
			DeviceName:    testfixtures.ValidMobileDeviceAuthKey1.DeviceName,
			DeviceModel:   testfixtures.ValidMobileDeviceAuthKey1.DeviceModel,
			DeviceOs:      testfixtures.ValidMobileDeviceAuthKey1.DeviceOs,
			CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey1.CreatedAt.Time.Round(time.Second)),
			ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey1.ExpiresAt.Time.Round(time.Second)),
			OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId),
		},
		{
			Id:            int64(testfixtures.ValidMobileDeviceAuthKey2.ID),
			DeviceName:    testfixtures.ValidMobileDeviceAuthKey2.DeviceName,
			DeviceModel:   testfixtures.ValidMobileDeviceAuthKey2.DeviceModel,
			DeviceOs:      testfixtures.ValidMobileDeviceAuthKey2.DeviceOs,
			CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey2.CreatedAt.Time.Round(time.Second)),
			ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey2.ExpiresAt.Time.Round(time.Second)),
			OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKey2.OauthAccessId),
		},
		{
			Id:            int64(testfixtures.ValidMobileDeviceAuthKey3.ID),
			DeviceName:    testfixtures.ValidMobileDeviceAuthKey3.DeviceName,
			DeviceModel:   testfixtures.ValidMobileDeviceAuthKey3.DeviceModel,
			DeviceOs:      testfixtures.ValidMobileDeviceAuthKey3.DeviceOs,
			CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey3.CreatedAt.Time.Round(time.Second)),
			ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey3.ExpiresAt.Time.Round(time.Second)),
			OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKey3.OauthAccessId),
		},
	}
	testFindDeviceKeyRegistrations(t, testfixtures.UserIdWithMultipleValidDeviceKeys, pb.FindDeviceKeyRegistrationsResponse_RESULT_SUCCESS, devices)
}

func TestFindDeviceKeyRegistrationsNoDevices(t *testing.T) {
	testFindDeviceKeyRegistrations(t, testfixtures.UserIdWithoutMobileDevicesKey, pb.FindDeviceKeyRegistrationsResponse_RESULT_SUCCESS, nil)
}

func testFindDeviceKeyRegistrations(t *testing.T, userID uint64, expectedResult pb.FindDeviceKeyRegistrationsResponse_Result, expectedDevices []*pb.DeviceKeyRegistration) {
	mdm := getManager(t)
	req := &pb.FindDeviceKeyRegistrationsRequest{
		Kind: &pb.FindDeviceKeyRegistrationsRequest_AuthRegistrationsRequest{
			AuthRegistrationsRequest: &pb.RegistrationsRequest{
				UserId: int64(userID),
			},
		},
	}
	resp, err := mdm.FindDeviceKeyRegistrations(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, expectedResult, resp.Result)
	assert.Equal(t, expectedDevices, resp.Registrations)
}

func getManager(t *testing.T) client.MobileDeviceManager {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)
	return mdm
}
