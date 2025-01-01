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

func TestFindDeviceKeyRegistrationUnknownRequest(t *testing.T) {
	req := new(pb.FindDeviceKeyRegistrationRequest)
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)
	resp, err := mdm.FindDeviceKeyRegistration(context.Background(), req)
	require.NotNil(t, resp)
	assert.Equal(t, pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.EqualError(t, err, "unknown FindDeviceKeyRegistration request: <nil>")
}

func TestFindDeviceKeyRegistrationMissingUserId(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.FindDeviceKeyRegistrationRequest{
		Kind: &pb.FindDeviceKeyRegistrationRequest_AuthRegistrationRequest{
			AuthRegistrationRequest: &pb.RegistrationRequest{
				OauthAccessId: 1,
			},
		},
	}
	resp, err := mdm.FindDeviceKeyRegistration(context.Background(), req)

	require.NotNil(t, resp)
	assert.Equal(t, pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.EqualError(t, err, "twirp error invalid_argument: UserId is required")
}

func TestFindDeviceKeyRegistrationMissingOauthAccessId(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.FindDeviceKeyRegistrationRequest{
		Kind: &pb.FindDeviceKeyRegistrationRequest_AuthRegistrationRequest{
			AuthRegistrationRequest: &pb.RegistrationRequest{
				UserId: 1,
			},
		},
	}
	resp, err := mdm.FindDeviceKeyRegistration(context.Background(), req)

	require.NotNil(t, resp)
	assert.Equal(t, pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.EqualError(t, err, "twirp error invalid_argument: OauthAccessId is required")
}

func TestFindDeviceKeyRegistrationSuccessful(t *testing.T) {
	device := &pb.DeviceKeyRegistration{
		Id:             int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.ID),
		DeviceName:     testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceName,
		DeviceModel:    testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceModel,
		DeviceOs:       testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceOs,
		CreatedAtTime:  timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.CreatedAt.Time),
		ExpiresAtTime:  timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.ExpiresAt.Time),
		LastUsedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.LastUsedAt.Time),
		OauthAccessId:  int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.OauthAccessId),
	}
	testFindDeviceKeyRegistration(t, testfixtures.ValidMobileDeviceAuthKeyForUser9.UserId, testfixtures.ValidMobileDeviceAuthKeyForUser9.OauthAccessId, pb.FindDeviceKeyRegistrationResponse_RESULT_SUCCESS, device)
}

func TestFindDeviceKeyRegistrationFiltersInvalidDevices(t *testing.T) {
	device := &pb.DeviceKeyRegistration{
		Id:            int64(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.ID),
		DeviceName:    testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.DeviceName,
		DeviceModel:   testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.DeviceModel,
		DeviceOs:      testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.DeviceOs,
		CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.CreatedAt.Time),
		ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.ExpiresAt.Time),
		OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId),
	}
	testFindDeviceKeyRegistration(t, testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.UserId, testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.OauthAccessId, pb.FindDeviceKeyRegistrationResponse_RESULT_SUCCESS, device)
}

func TestFindDeviceKeyRegistrationFiltersExpiredDevices(t *testing.T) {
	testFindDeviceKeyRegistration(t, testfixtures.ExpiredMobileDeviceAuthKeyForUser7.UserId, testfixtures.ExpiredMobileDeviceAuthKeyForUser7.OauthAccessId, pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_NOT_FOUND, nil)
}

func TestFindDeviceKeyRegistrationFiltersRevokedDevices(t *testing.T) {
	testFindDeviceKeyRegistration(t, testfixtures.RevokedMobileDeviceAuthKeyForUser8.UserId, testfixtures.RevokedMobileDeviceAuthKeyForUser8.OauthAccessId, pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_NOT_FOUND, nil)
}

func TestFindDeviceKeyRegistrationMultipleValidDevices(t *testing.T) {
	device := &pb.DeviceKeyRegistration{
		Id:            int64(testfixtures.ValidMobileDeviceAuthKey1.ID),
		DeviceName:    testfixtures.ValidMobileDeviceAuthKey1.DeviceName,
		DeviceModel:   testfixtures.ValidMobileDeviceAuthKey1.DeviceModel,
		DeviceOs:      testfixtures.ValidMobileDeviceAuthKey1.DeviceOs,
		CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey1.CreatedAt.Time),
		ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey1.ExpiresAt.Time),
		OauthAccessId: int64(testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId),
	}
	testFindDeviceKeyRegistration(t, testfixtures.UserIdWithMultipleValidDeviceKeys, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindDeviceKeyRegistrationResponse_RESULT_SUCCESS, device)
}

func TestFindDeviceKeyRegistrationMultipleDevicesForOauthAccess(t *testing.T) {
	// this scenario shouldn't be possible but should be gracefully handled
	testFindDeviceKeyRegistration(t, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.OauthAccessId, pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_GENERIC, nil)
}

func TestFindDeviceKeyRegistrationNoDevices(t *testing.T) {
	testFindDeviceKeyRegistration(t, testfixtures.UserIdWithoutMobileDevicesKey, 1, pb.FindDeviceKeyRegistrationResponse_RESULT_FAILED_NOT_FOUND, nil)
}

func testFindDeviceKeyRegistration(t *testing.T, UserId uint64, OauthAccessId uint64, expectedResult pb.FindDeviceKeyRegistrationResponse_Result, expectedDevice *pb.DeviceKeyRegistration) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.FindDeviceKeyRegistrationRequest{
		Kind: &pb.FindDeviceKeyRegistrationRequest_AuthRegistrationRequest{
			AuthRegistrationRequest: &pb.RegistrationRequest{
				UserId:        int64(UserId),
				OauthAccessId: int64(OauthAccessId),
			},
		},
	}

	resp, err := mdm.FindDeviceKeyRegistration(context.Background(), req)

	assert.Nil(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, expectedResult, resp.Result)
	assert.Equal(t, expectedDevice, resp.Registration)
}
