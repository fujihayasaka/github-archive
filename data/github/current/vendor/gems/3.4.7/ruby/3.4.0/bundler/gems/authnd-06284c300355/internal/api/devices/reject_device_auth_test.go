package devices

import (
	"context"
	"testing"
	"time"

	"github.com/pkg/errors"
	"gopkg.in/guregu/null.v4"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestRejectDeviceAuthUnknownRequest(t *testing.T) {
	req := &pb.CompleteDeviceAuthRequest{}
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)
	resp, err := mdm.CompleteDeviceAuth(context.Background(), req)
	require.NotNil(t, resp)
	assert.Equal(t, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, resp.Result)
	require.NotNil(t, err)
	assert.Equal(t, errors.New("unknown complete device auth request: <nil>").Error(), err.Error())
}

func TestRejectDeviceAuthMissingRequestId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{}
	testRejectDeviceAuthParamChecking(t, message, twirp.RequiredArgumentError("AuthRequestId"))
}

func TestRejectDeviceAuthMissingOauthAccessId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		UserId:        2,
	}
	testRejectDeviceAuthParamChecking(t, message, twirp.RequiredArgumentError("OauthAccessId"))
}

func TestRejectDeviceAuthMissingUserId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		OauthAccessId: 2,
	}
	testRejectDeviceAuthParamChecking(t, message, twirp.RequiredArgumentError("UserId"))
}

func TestRejectDeviceAuthSuccess(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(1*time.Minute))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRejectDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_SUCCESS)
}

func TestRejectDeviceAuthWithoutChallengeSuccess(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestWithoutChallengeForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(1*time.Minute))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRejectDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_SUCCESS)
}

func TestRejectDeviceAuthFailureWithKeyCreatedAfterAuthRequest(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(-1*time.Minute))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRejectDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND)
}

func TestRejectDeviceAuthFailureRevokedMobileDeviceAuthKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.RevokedMobileDeviceAuthKeyForUser8.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRejectDeviceAuth(t, seed, testfixtures.RevokedMobileDeviceAuthKeyForUser8, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND)
}

func TestRejectDeviceAuthFailureExpiredMobileDeviceAuthKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ExpiredMobileDeviceAuthKeyForUser7.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRejectDeviceAuth(t, seed, testfixtures.ExpiredMobileDeviceAuthKeyForUser7, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND)
}

func TestRejectDeviceAuthFailureDeviceKeyNotFound(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRejectDeviceAuth(t, seed, testfixtures.MobileDeviceAuthKeyNotInStore, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND)
}

// this should never happen, but we should handle it gracefully
// this is a case where an oauth access id ends up with multiple valid device auth keys
// we protect against this at device auth key registration time
func TestRejectDeviceAuthFailureWhenMultipleKeysForOauthAccessId(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId), time.Now().Add(1*time.Minute))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRejectDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND)
}

func TestRejectDeviceAuthFailureAuthRequestNotFound(t *testing.T) {
	testRejectDeviceAuth(t, testfixtures.MobileAuthRequestNotInStore, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_FOUND)
}

func TestRejectDeviceAuthFailureExpiredAuthRequest(t *testing.T) {
	seed := testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRejectDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE)
}

func TestRejectDeviceAuthFailureApprovedAuthRequest(t *testing.T) {
	seed := testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRejectDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE)
}

func TestRejectDeviceAuthFailureRejectedAuthRequest(t *testing.T) {
	seed := testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRejectDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_ALREADY_REJECTED)
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
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{mobileAuthRequest})
	testRejectDeviceAuth(t, mobileAuthRequest, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE)
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
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{mobileAuthRequest})
	testRejectDeviceAuth(t, mobileAuthRequest, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_ALREADY_REJECTED)
}

func testRejectDeviceAuth(t *testing.T, mobileAuthRequest *models.MobileAuthRequest, deviceKey *testfixtures.MobileDeviceKeysWithPrivateKey, expectedResult pb.CompleteDeviceAuthResponse_Result) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)
	req := &pb.CompleteDeviceAuthRequest{
		Kind: &pb.CompleteDeviceAuthRequest_Reject{
			// does not require signature
			Reject: &pb.CompleteDeviceAuthMessage{
				AuthRequestId: int64(mobileAuthRequest.ID),
				OauthAccessId: int64(deviceKey.OauthAccessId),
				UserId:        int64(deviceKey.UserId),
			},
		},
	}
	resp, err := mdm.CompleteDeviceAuth(context.Background(), req)
	assert.Nil(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, expectedResult, resp.Result)
}

func testRejectDeviceAuthParamChecking(t *testing.T, message *pb.CompleteDeviceAuthMessage, expectedErr error) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)
	req := &pb.CompleteDeviceAuthRequest{
		Kind: &pb.CompleteDeviceAuthRequest_Reject{
			Reject: message,
		},
	}
	resp, err := mdm.CompleteDeviceAuth(context.Background(), req)
	require.NotNil(t, resp)
	assert.Equal(t, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, resp.Result)
	require.NotNil(t, err)
	assert.Equal(t, expectedErr.Error(), err.Error())
}
