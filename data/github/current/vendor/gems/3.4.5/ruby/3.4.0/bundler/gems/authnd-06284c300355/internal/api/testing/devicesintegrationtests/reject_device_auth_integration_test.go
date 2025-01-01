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
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"gopkg.in/guregu/null.v4"
)

func TestRejectDeviceAuthUnknownRequest(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)
	req := &pb.CompleteDeviceAuthRequest{}
	resp, err := mdm.CompleteDeviceAuth(context.Background(), req)
	assert.Nil(t, resp)
	assert.NotNil(t, err)
	assert.Equal(t, twirp.InternalError("unknown complete device auth request: <nil>").Error(), err.Error())
}

func TestRejectDeviceAuthMissingRequestId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{}
	testRejectDeviceAuthWithMessage(t, []*models.MobileAuthRequest{}, message, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, twirp.RequiredArgumentError("AuthRequestId"))
}

func TestRejectDeviceAuthMissingOauthAccessId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		UserId:        2,
	}
	testRejectDeviceAuthWithMessage(t, []*models.MobileAuthRequest{}, message, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, twirp.RequiredArgumentError("OauthAccessId"))
}

func TestRejectDeviceAuthMissingUserId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		OauthAccessId: 2,
	}
	testRejectDeviceAuthWithMessage(t, []*models.MobileAuthRequest{}, message, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, twirp.RequiredArgumentError("UserId"))
}

func TestRejectDeviceAuthSuccess(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(1*time.Minute))
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_SUCCESS, nil)
}

func TestRejectDeviceAuthWithoutChallengeSuccess(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestWithoutChallengeForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(1*time.Minute))
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_SUCCESS, nil)
}

func TestRejectDeviceAuthFailureWithKeyCreatedAfterAuthRequest(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(-1*time.Minute))
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND, nil)
}

func TestRejectDeviceAuthFailureRevokedMobileDeviceAuthKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.RevokedMobileDeviceAuthKeyForUser8.UserId))
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.RevokedMobileDeviceAuthKeyForUser8, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND, nil)
}

func TestRejectDeviceAuthFailureExpiredMobileDeviceAuthKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ExpiredMobileDeviceAuthKeyForUser7.UserId))
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ExpiredMobileDeviceAuthKeyForUser7, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND, nil)
}

func TestRejectDeviceAuthFailureDeviceKeyNotFound(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.MobileDeviceAuthKeyNotInStore, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND, nil)
}

// this should never happen, but we should handle it gracefully
// this is a case where an oauth access id ends up with multiple valid device auth keys
// we protect against this at device auth key registration time
func TestRejectDeviceAuthFailureWhenMultipleKeysForOauthAccessId(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId), time.Now().Add(1*time.Minute))
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND, nil)
}

func TestRejectDeviceAuthFailureAuthRequestNotFound(t *testing.T) {
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{}, int64(1), testfixtures.MobileAuthRequestNotInStore, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_FOUND, nil)
}

func TestRejectDeviceAuthFailureExpiredAuthRequest(t *testing.T) {
	seed := testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE, nil)
}

func TestRejectDeviceAuthFailureApprovedAuthRequest(t *testing.T) {
	seed := testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE, nil)
}

func TestRejectDeviceAuthFailureRejectedAuthRequest(t *testing.T) {
	seed := testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_ALREADY_REJECTED, nil)
}

func TestRejectDeviceAuthFailureApprovedAndExpiredAuthRequest(t *testing.T) {
	mobileAuthRequest := &models.MobileAuthRequest{
		UserId:          uint64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId),
		Payload:         testfixtures.MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		ApprovedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
	}
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{mobileAuthRequest}, int64(1), mobileAuthRequest, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE, nil)
}

func TestRejectDeviceAuthFailureRejectedAndExpiredAuthRequest(t *testing.T) {
	mobileAuthRequest := &models.MobileAuthRequest{
		UserId:          uint64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId),
		Payload:         testfixtures.MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		RejectedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
	}
	testRejectDeviceAuth(t, []*models.MobileAuthRequest{mobileAuthRequest}, int64(1), mobileAuthRequest, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_ALREADY_REJECTED, nil)
}

func testRejectDeviceAuth(t *testing.T, seeds []*models.MobileAuthRequest, mobileAuthRequestID int64, mobileAuthRequest *models.MobileAuthRequest, deviceKey *testfixtures.MobileDeviceKeysWithPrivateKey, expectedResult pb.CompleteDeviceAuthResponse_Result, expectedErr error) {
	// does not require signature
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: int64(mobileAuthRequestID),
		UserId:        int64(deviceKey.UserId),
		OauthAccessId: int64(deviceKey.ID),
	}
	testRejectDeviceAuthWithMessage(t, seeds, message, expectedResult, expectedErr)
}

func testRejectDeviceAuthWithMessage(t *testing.T, seeds []*models.MobileAuthRequest, message *pb.CompleteDeviceAuthMessage, expectedResult pb.CompleteDeviceAuthResponse_Result, expectedErr error) {
	req := &pb.CompleteDeviceAuthRequest{
		Kind: &pb.CompleteDeviceAuthRequest_Reject{
			Reject: message,
		},
	}
	store := testfixtures.CreateTestDatabaseStore(t, true)
	integrationTesting.SeedMobileAuthRequests(t, seeds)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))

	resp, err := mdm.CompleteDeviceAuth(context.Background(), req)

	if expectedErr != nil {
		assert.NotNil(t, err)
		assert.Equal(t, expectedErr.Error(), err.Error())
		assert.Nil(t, resp)
	} else {
		assert.Nil(t, err)
		assert.NotNil(t, resp)
		assert.Equal(t, expectedResult, resp.Result)

		if expectedResult == pb.CompleteDeviceAuthResponse_RESULT_SUCCESS {
			// verify that the device's last_used_at_utc was updated
			deviceReq := &pb.FindDeviceKeyRegistrationRequest{
				Kind: &pb.FindDeviceKeyRegistrationRequest_AuthRegistrationRequest{
					AuthRegistrationRequest: &pb.RegistrationRequest{
						UserId:        message.UserId,
						OauthAccessId: message.OauthAccessId,
					},
				},
			}
			deviceResp, err := mdm.FindDeviceKeyRegistration(context.Background(), deviceReq)
			require.NoError(t, err)
			assert.Equal(t, deviceResp.Result, pb.FindDeviceKeyRegistrationResponse_RESULT_SUCCESS)
			require.NotNil(t, deviceResp.Registration)
			require.NotNil(t, deviceResp.Registration.LastUsedAtTime)
			// make sure `last_updated_at` is set and within 2s of the start of the test
			assert.InDelta(t, time.Now().Unix(), deviceResp.Registration.LastUsedAtTime.AsTime().Unix(), 2)
		}
	}
}
