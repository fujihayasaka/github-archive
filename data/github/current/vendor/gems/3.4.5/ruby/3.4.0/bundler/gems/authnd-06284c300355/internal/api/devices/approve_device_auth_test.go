package devices

import (
	"context"
	"testing"
	"time"

	"gopkg.in/guregu/null.v4"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/crypto"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestApproveDeviceAuthUnknownRequest(t *testing.T) {
	req := &pb.CompleteDeviceAuthRequest{}
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)
	resp, err := mdm.CompleteDeviceAuth(context.Background(), req)
	require.NotNil(t, resp)
	assert.Equal(t, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, resp.Result)
	require.NotNil(t, err)
	assert.Equal(t, errors.New("unknown complete device auth request: <nil>").Error(), err.Error())
}

func TestApproveDeviceAuthMissingRequestId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{}
	testApproveDeviceAuthParamChecking(t, message, twirp.RequiredArgumentError("AuthRequestId"))
}

func TestApproveDeviceAuthMissingOauthAccessId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		UserId:        2,
	}
	testApproveDeviceAuthParamChecking(t, message, twirp.RequiredArgumentError("OauthAccessId"))
}

func TestApproveDeviceAuthMissingUserId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		OauthAccessId: 2,
	}
	testApproveDeviceAuthParamChecking(t, message, twirp.RequiredArgumentError("UserId"))
}

func TestApproveDeviceAuthMissingSignature(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		UserId:        3,
		OauthAccessId: 2,
	}
	testApproveDeviceAuthParamChecking(t, message, twirp.RequiredArgumentError("Signature"))
}

func TestApproveDeviceAuthMissingSignatureVersion(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		UserId:        3,
		OauthAccessId: 2,
		Signature:     "sig",
	}
	testApproveDeviceAuthParamChecking(t, message, twirp.RequiredArgumentError("SignatureVersion"))
}

func TestApproveDeviceAuthBadSignatureVersion(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId:    1,
		UserId:           3,
		OauthAccessId:    2,
		Signature:        "sig",
		SignatureVersion: 2,
	}
	testApproveDeviceAuthParamChecking(t, message, twirp.InvalidArgumentError("SignatureVersion", "not a supported version"))
}

func TestApproveDeviceAuthSuccess(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(1*time.Minute))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testApproveDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_SUCCESS)
}

func TestApproveDeviceAuthWithoutChallengeSuccess(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestWithoutChallengeForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(1*time.Minute))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testApproveDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_SUCCESS)
}

func TestApproveDeviceAuthFailureWithKeyCreatedAfterAuthRequest(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(-1*time.Minute))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testApproveDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND)
}

func TestApproveDeviceAuthFailureRevokedMobileDeviceAuthKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.RevokedMobileDeviceAuthKeyForUser8.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testApproveDeviceAuth(t, seed, testfixtures.RevokedMobileDeviceAuthKeyForUser8, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND)
}

func TestApproveDeviceAuthFailureExpiredMobileDeviceAuthKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ExpiredMobileDeviceAuthKeyForUser7.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testApproveDeviceAuth(t, seed, testfixtures.ExpiredMobileDeviceAuthKeyForUser7, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND)
}

func TestApproveDeviceAuthFailureDeviceKeyNotFound(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testApproveDeviceAuth(t, seed, testfixtures.MobileDeviceAuthKeyNotInStore, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND)
}

// this should never happen, but we should handle it gracefully
// this is a case where an oauth access id ends up with multiple valid device auth keys
// we protect against this at device auth key registration time
func TestApproveDeviceAuthFailureWhenMultipleKeysForOauthAccessId(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId), time.Now().Add(1*time.Minute))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testApproveDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND)
}

func TestApproveDeviceAuthFailureAuthRequestNotFound(t *testing.T) {
	testApproveDeviceAuth(t, testfixtures.MobileAuthRequestNotInStore, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_FOUND)
}

func TestApproveDeviceAuthFailureExpiredAuthRequest(t *testing.T) {
	seed := testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testApproveDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE)
}

func TestApproveDeviceAuthFailureApprovedAuthRequest(t *testing.T) {
	seed := testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testApproveDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_ALREADY_APPROVED)
}

func TestApproveDeviceAuthFailureRejectedAuthRequest(t *testing.T) {
	seed := testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testApproveDeviceAuth(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE)
}

func TestApproveDeviceAuthFailureApprovedAndExpiredAuthRequest(t *testing.T) {
	mobileAuthRequest := &models.MobileAuthRequest{
		UserId:          uint64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId),
		Payload:         testfixtures.MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		ApprovedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
	}
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{mobileAuthRequest})
	testApproveDeviceAuth(t, mobileAuthRequest, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_ALREADY_APPROVED)
}

func TestApproveDeviceAuthFailureRejectedAndExpiredAuthRequest(t *testing.T) {
	mobileAuthRequest := &models.MobileAuthRequest{
		UserId:          uint64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId),
		Payload:         testfixtures.MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		RejectedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
	}
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{mobileAuthRequest})
	testApproveDeviceAuth(t, mobileAuthRequest, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE)
}

func TestApproveDeviceAuthFailureWithSignatureWithoutChallenge(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	signatureWithoutChallenge := crypto.MustSignMessageHash(testfixtures.ValidMobileDeviceAuthKeyForUser1.PrivateKey, mobiledeviceauth.CreateExpectedApproveMessageWithoutChallengeHash(1, seed.Payload))
	testApproveDeviceAuthWithSignature(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, signatureWithoutChallenge, 1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_NOT_VERIFIED, nil)
}

func TestApproveDeviceAuthFailureBadSignature(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testApproveDeviceAuthWithSignature(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, "notEvenBase64Encoding", 1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, twirp.InternalError("There was a problem verifying the signature"))
}

// create an invalid signature by using a random private key to make the signature
func TestApproveDeviceAuthFailureInvalidSignatureRandomPrivateKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	randomPrivateKey := crypto.MustCreateECDSAPrivateKey()
	invalidSignature := crypto.MustSignMessageHash(randomPrivateKey, mobiledeviceauth.CreateExpectedApproveMessageHash(1, seed.Payload, seed.ChallengeNumber.Int64))
	testApproveDeviceAuthWithSignature(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, invalidSignature, 1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_NOT_VERIFIED, nil)
}

// create an invalid signature by creating the wrong expected message
func TestApproveDeviceAuthFailureInvalidSignatureWrongMessage(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	invalidSignature := crypto.MustSignMessageHash(testfixtures.ValidMobileDeviceAuthKeyForUser1.PrivateKey, []byte("not_the_secret_message"))
	testApproveDeviceAuthWithSignature(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, invalidSignature, 1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_NOT_VERIFIED, nil)
}

// create an invalid signature by creating the wrong expected message (using the wrong "version")
func TestApproveDeviceAuthFailureInvalidSignatureWrongMessageByVersion(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	invalidSignature := crypto.MustSignMessageHash(testfixtures.ValidMobileDeviceAuthKeyForUser1.PrivateKey, mobiledeviceauth.CreateExpectedApproveMessageHash(2, seed.Payload, seed.ChallengeNumber.Int64))
	testApproveDeviceAuthWithSignature(t, seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, invalidSignature, 1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_NOT_VERIFIED, nil)
}

func testApproveDeviceAuth(t *testing.T, mobileAuthRequest *models.MobileAuthRequest, deviceKey *testfixtures.MobileDeviceKeysWithPrivateKey, expectedResult pb.CompleteDeviceAuthResponse_Result) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	var approvalSignature string
	if mobileAuthRequest.ChallengeNumber.Valid {
		approvalSignature = crypto.MustSignMessageHash(deviceKey.PrivateKey, mobiledeviceauth.CreateExpectedApproveMessageHash(1, mobileAuthRequest.Payload, mobileAuthRequest.ChallengeNumber.Int64))
	} else {
		approvalSignature = crypto.MustSignMessageHash(deviceKey.PrivateKey, mobiledeviceauth.CreateExpectedApproveMessageWithoutChallengeHash(1, mobileAuthRequest.Payload))
	}
	// test approve
	req := &pb.CompleteDeviceAuthRequest{
		Kind: &pb.CompleteDeviceAuthRequest_Approve{
			Approve: &pb.CompleteDeviceAuthMessage{
				AuthRequestId:    int64(mobileAuthRequest.ID),
				OauthAccessId:    int64(deviceKey.OauthAccessId),
				UserId:           int64(deviceKey.UserId),
				Signature:        approvalSignature,
				SignatureVersion: 1,
			},
		},
	}
	resp, err := mdm.CompleteDeviceAuth(context.Background(), req)
	assert.Nil(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, expectedResult, resp.Result)
}

func testApproveDeviceAuthWithSignature(t *testing.T, mobileAuthRequest *models.MobileAuthRequest, deviceKey *testfixtures.MobileDeviceKeysWithPrivateKey, signature string, signatureVersion int, expectedResult pb.CompleteDeviceAuthResponse_Result, expectedErr error) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.CompleteDeviceAuthRequest{
		Kind: &pb.CompleteDeviceAuthRequest_Approve{
			Approve: &pb.CompleteDeviceAuthMessage{
				AuthRequestId:    int64(mobileAuthRequest.ID),
				OauthAccessId:    int64(deviceKey.OauthAccessId),
				UserId:           int64(deviceKey.UserId),
				Signature:        signature,
				SignatureVersion: int64(signatureVersion),
			},
		},
	}
	resp, err := mdm.CompleteDeviceAuth(context.Background(), req)
	if expectedErr != nil {
		require.NotNil(t, err)
		assert.Equal(t, expectedErr.Error(), err.Error())
	} else {
		assert.Nil(t, err)
	}
	require.NotNil(t, resp)
	assert.Equal(t, expectedResult, resp.Result)
}

func testApproveDeviceAuthParamChecking(t *testing.T, message *pb.CompleteDeviceAuthMessage, expectedErr error) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)
	req := &pb.CompleteDeviceAuthRequest{
		Kind: &pb.CompleteDeviceAuthRequest_Approve{
			Approve: message,
		},
	}
	resp, err := mdm.CompleteDeviceAuth(context.Background(), req)
	require.NotNil(t, resp)
	assert.Equal(t, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, resp.Result)
	require.NotNil(t, err)
	assert.Equal(t, expectedErr.Error(), err.Error())
}
