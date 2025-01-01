//go:build db && !proxima

package devicesintegrationtests

import (
	"context"
	"testing"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/assert"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestFindDeviceKeyRegistrationSuccessful(t *testing.T) {
	device := &pb.DeviceKeyRegistration{
		Id:             int64(testfixtures.ValidMobileDeviceAuthKeyForUser9.ID),
		DeviceName:     testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceName,
		DeviceModel:    testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceModel,
		DeviceOs:       testfixtures.ValidMobileDeviceAuthKeyForUser9.DeviceOs,
		CreatedAtTime:  timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.CreatedAt.Time.Round(time.Second)),
		ExpiresAtTime:  timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.ExpiresAt.Time.Round(time.Second)),
		LastUsedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUser9.LastUsedAt.Time.Round(time.Second)),
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
		CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.CreatedAt.Time.Round(time.Second)),
		ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKeyForUserWithMultipleKeys.ExpiresAt.Time.Round(time.Second)),
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

func TestFindDeviceKeyRegistrationMultipleValidDevicesForUser(t *testing.T) {
	device := &pb.DeviceKeyRegistration{
		Id:            int64(testfixtures.ValidMobileDeviceAuthKey1.ID),
		DeviceName:    testfixtures.ValidMobileDeviceAuthKey1.DeviceName,
		DeviceModel:   testfixtures.ValidMobileDeviceAuthKey1.DeviceModel,
		DeviceOs:      testfixtures.ValidMobileDeviceAuthKey1.DeviceOs,
		CreatedAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey1.CreatedAt.Time.Round(time.Second)),
		ExpiresAtTime: timestamppb.New(testfixtures.ValidMobileDeviceAuthKey1.ExpiresAt.Time.Round(time.Second)),
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

func testFindDeviceKeyRegistration(t *testing.T, userID uint64, oauthAccessID uint64, expectedResult pb.FindDeviceKeyRegistrationResponse_Result, expectedDevice *pb.DeviceKeyRegistration) {
	mdm := getManager(t)

	req := &pb.FindDeviceKeyRegistrationRequest{
		Kind: &pb.FindDeviceKeyRegistrationRequest_AuthRegistrationRequest{
			AuthRegistrationRequest: &pb.RegistrationRequest{
				UserId:        int64(userID),
				OauthAccessId: int64(oauthAccessID),
			},
		},
	}

	resp, err := mdm.FindDeviceKeyRegistration(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, expectedResult, resp.Result)
	assert.Equal(t, expectedDevice, resp.Registration)
}
