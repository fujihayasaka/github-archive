package devices

import (
	"context"
	"testing"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestFindDeviceKeyRegistrationsUnknownRequest(t *testing.T) {
	req := new(pb.FindDeviceKeyRegistrationsRequest)
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)
	resp, err := mdm.FindDeviceKeyRegistrations(context.Background(), req)
	require.NotNil(t, resp)
	assert.Equal(t, pb.FindDeviceKeyRegistrationsResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.EqualError(t, err, "unknown find device key registrations request: <nil>")
}

func TestFindDeviceKeyRegistrationsMissingUserId(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.FindDeviceKeyRegistrationsRequest{
		Kind: &pb.FindDeviceKeyRegistrationsRequest_AuthRegistrationsRequest{
			AuthRegistrationsRequest: &pb.RegistrationsRequest{},
		},
	}
	resp, err := mdm.FindDeviceKeyRegistrations(context.Background(), req)

	require.NotNil(t, resp)
	assert.Equal(t, pb.FindDeviceKeyRegistrationsResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.EqualError(t, err, "twirp error invalid_argument: UserId is required")
}

func TestFindDeviceKeyRegistrationsSuccessful(t *testing.T) {
	devices := []*pb.DeviceKeyRegistration{
		{
			Id:             int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.ID),
			DeviceName:     testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceName,
			DeviceModel:    testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceModel,
			DeviceOs:       testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceOs,
			CreatedAtTime:  timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.CreatedAt.Time),
			ExpiresAtTime:  timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.ExpiresAt.Time),
			LastUsedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.LastUsedAt.Time),
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
			CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.CreatedAt.Time),
			ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.ExpiresAt.Time),
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
			CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey1.CreatedAt.Time),
			ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey1.ExpiresAt.Time),
			OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId),
		},
		{
			Id:            int64(testfixtures.ValidMobileDeviceAuthKey2.ID),
			DeviceName:    testfixtures.ValidMobileDeviceAuthKey2.DeviceName,
			DeviceModel:   testfixtures.ValidMobileDeviceAuthKey2.DeviceModel,
			DeviceOs:      testfixtures.ValidMobileDeviceAuthKey2.DeviceOs,
			CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey2.CreatedAt.Time),
			ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey2.ExpiresAt.Time),
			OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKey2.OauthAccessId),
		},
		{
			Id:            int64(testfixtures.ValidMobileDeviceAuthKey3.ID),
			DeviceName:    testfixtures.ValidMobileDeviceAuthKey3.DeviceName,
			DeviceModel:   testfixtures.ValidMobileDeviceAuthKey3.DeviceModel,
			DeviceOs:      testfixtures.ValidMobileDeviceAuthKey3.DeviceOs,
			CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey3.CreatedAt.Time),
			ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey3.ExpiresAt.Time),
			OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKey3.OauthAccessId),
		},
	}
	testFindDeviceKeyRegistrations(t, testfixtures.UserIdWithMultipleValidDeviceKeys, pb.FindDeviceKeyRegistrationsResponse_RESULT_SUCCESS, devices)
}

func TestFindDeviceKeyRegistrationsNoDevices(t *testing.T) {
	testFindDeviceKeyRegistrations(t, testfixtures.UserIdWithoutMobileDevicesKey, pb.FindDeviceKeyRegistrationsResponse_RESULT_SUCCESS, nil)
}

func testFindDeviceKeyRegistrations(t *testing.T, userID uint64, expectedResult pb.FindDeviceKeyRegistrationsResponse_Result, expectedDevices []*pb.DeviceKeyRegistration) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.FindDeviceKeyRegistrationsRequest{
		Kind: &pb.FindDeviceKeyRegistrationsRequest_AuthRegistrationsRequest{
			AuthRegistrationsRequest: &pb.RegistrationsRequest{
				UserId: int64(userID),
			},
		},
	}
	resp, err := mdm.FindDeviceKeyRegistrations(context.Background(), req)

	assert.Nil(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, expectedResult, resp.Result)
	assert.Equal(t, expectedDevices, resp.Registrations)
}
