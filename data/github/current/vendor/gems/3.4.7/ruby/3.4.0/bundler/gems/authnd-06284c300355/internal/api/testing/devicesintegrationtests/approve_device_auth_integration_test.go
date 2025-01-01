//go:build db && !proxima

package devicesintegrationtests

import (
	"context"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	integrationTesting "github.com/github/authnd/internal/api/testing"
	"github.com/github/authnd/internal/common/crypto"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
	"github.com/github/authnd/internal/common/models"
	commonStore "github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"gopkg.in/guregu/null.v4"
)

func TestApproveDeviceAuthUnknownRequest(t *testing.T) {
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

func TestApproveDeviceAuthMissingRequestId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{}
	testApproveDeviceAuthWithMessage(t, []*models.MobileAuthRequest{}, message, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, twirp.RequiredArgumentError("AuthRequestId"))
}

func TestApproveDeviceAuthMissingOauthAccessId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		UserId:        2,
	}
	testApproveDeviceAuthWithMessage(t, []*models.MobileAuthRequest{}, message, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, twirp.RequiredArgumentError("OauthAccessId"))
}

func TestApproveDeviceAuthMissingUserId(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		OauthAccessId: 2,
	}
	testApproveDeviceAuthWithMessage(t, []*models.MobileAuthRequest{}, message, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, twirp.RequiredArgumentError("UserId"))
}

func TestApproveDeviceAuthMissingSignature(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		UserId:        3,
		OauthAccessId: 2,
	}
	testApproveDeviceAuthWithMessage(t, []*models.MobileAuthRequest{}, message, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, twirp.RequiredArgumentError("Signature"))
}

func TestApproveDeviceAuthMissingSignatureVersion(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: 1,
		UserId:        3,
		OauthAccessId: 2,
		Signature:     "sig",
	}
	testApproveDeviceAuthWithMessage(t, []*models.MobileAuthRequest{}, message, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, twirp.RequiredArgumentError("SignatureVersion"))
}

func TestApproveDeviceAuthBadSignatureVersion(t *testing.T) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId:    1,
		UserId:           3,
		OauthAccessId:    2,
		Signature:        "sig",
		SignatureVersion: 2,
	}
	testApproveDeviceAuthWithMessage(t, []*models.MobileAuthRequest{}, message, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, twirp.InvalidArgumentError("SignatureVersion", "not a supported version"))
}

func TestApproveDeviceAuthSuccess(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(1*time.Minute))
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_SUCCESS, nil)
}

func TestApproveDeviceAuthWithoutChallengeSuccess(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestWithoutChallengeForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(1*time.Minute))
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_SUCCESS, nil)
}

func TestApproveDeviceAuthFailureWithKeyCreatedAfterAuthRequest(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), time.Now().Add(-1*time.Minute))
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND, nil)
}

func TestApproveDeviceAuthFailureRevokedMobileDeviceAuthKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.RevokedMobileDeviceAuthKeyForUser8.UserId))
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.RevokedMobileDeviceAuthKeyForUser8, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND, nil)
}

func TestApproveDeviceAuthFailureExpiredMobileDeviceAuthKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ExpiredMobileDeviceAuthKeyForUser7.UserId))
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ExpiredMobileDeviceAuthKeyForUser7, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND, nil)
}

func TestApproveDeviceAuthFailureDeviceKeyNotFound(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.MobileDeviceAuthKeyNotInStore, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND, nil)
}

// this should never happen, but we should handle it gracefully
// this is a case where an oauth access id ends up with multiple valid device auth keys
// we protect against this at device auth key registration time
func TestApproveDeviceAuthFailureWhenMultipleKeysForOauthAccessId(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId), time.Now().Add(1*time.Minute))
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId, pb.CompleteDeviceAuthResponse_RESULT_FAILED_VALID_DEVICE_KEY_NOT_FOUND, nil)
}

func TestApproveDeviceAuthFailureAuthRequestNotFound(t *testing.T) {
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{}, int64(1), testfixtures.MobileAuthRequestNotInStore, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_FOUND, nil)
}

func TestApproveDeviceAuthFailureExpiredAuthRequest(t *testing.T) {
	seed := testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE, nil)
}

func TestApproveDeviceAuthFailureApprovedAuthRequest(t *testing.T) {
	seed := testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_ALREADY_APPROVED, nil)
}

func TestApproveDeviceAuthFailureRejectedAuthRequest(t *testing.T) {
	seed := testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{seed}, int64(1), seed, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE, nil)
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
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{mobileAuthRequest}, int64(1), mobileAuthRequest, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_ALREADY_APPROVED, nil)
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
	testApproveDeviceAuth(t, []*models.MobileAuthRequest{mobileAuthRequest}, int64(1), mobileAuthRequest, testfixtures.ValidMobileDeviceAuthKeyForUser1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_AUTH_REQUEST_NOT_ACTIVE, nil)
}

func TestApproveDeviceAuthFailureIncorrectlyEncodedSignature(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testApproveDeviceAuthWithSignatureInfo(t, []*models.MobileAuthRequest{seed}, int64(1), testfixtures.ValidMobileDeviceAuthKeyForUser1, "notEvenBase64Encoding", 1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_GENERIC, twirp.InternalError("There was a problem verifying the signature"))
}

func TestApproveDeviceAuthFailureWithSignatureWithoutChallengeWhenChallengeIsRequired(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	signatureWithoutChallenge := crypto.MustSignMessageHash(testfixtures.ValidMobileDeviceAuthKeyForUser1.PrivateKey, mobiledeviceauth.CreateExpectedApproveMessageWithoutChallengeHash(1, seed.Payload))
	testApproveDeviceAuthWithSignatureInfo(t, []*models.MobileAuthRequest{seed}, int64(1), testfixtures.ValidMobileDeviceAuthKeyForUser1, signatureWithoutChallenge, 1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_NOT_VERIFIED, nil)
	assertRequestMarkedAsRejected(t, uint64(1), testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId)
}

// create an invalid signature by using a random private key to make the signature
func TestApproveDeviceAuthFailureInvalidSignatureRandomPrivateKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	randomPrivateKey := crypto.MustCreateECDSAPrivateKey()
	invalidSignature := crypto.MustSignMessageHash(randomPrivateKey, mobiledeviceauth.CreateExpectedApproveMessageHash(1, seed.Payload, seed.ChallengeNumber.Int64))
	testApproveDeviceAuthWithSignatureInfo(t, []*models.MobileAuthRequest{seed}, int64(1), testfixtures.ValidMobileDeviceAuthKeyForUser1, invalidSignature, 1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_NOT_VERIFIED, nil)
	assertRequestMarkedAsRejected(t, uint64(1), testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId)
}

// create an invalid signature by creating the wrong expected message
func TestApproveDeviceAuthFailureInvalidSignatureWrongMessage(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	invalidSignature := crypto.MustSignMessageHash(testfixtures.ValidMobileDeviceAuthKeyForUser1.PrivateKey, []byte("not_the_secret_message"))
	testApproveDeviceAuthWithSignatureInfo(t, []*models.MobileAuthRequest{seed}, int64(1), testfixtures.ValidMobileDeviceAuthKeyForUser1, invalidSignature, 1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_NOT_VERIFIED, nil)
	assertRequestMarkedAsRejected(t, uint64(1), testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId)
}

// create an invalid signature by using the wrong challenge number
func TestApproveDeviceAuthFailureInvalidSignatureWrongChallenge(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	signatureWithWrongChallenge := crypto.MustSignMessageHash(testfixtures.ValidMobileDeviceAuthKeyForUser1.PrivateKey, mobiledeviceauth.CreateExpectedApproveMessageHash(1, seed.Payload, seed.ChallengeNumber.Int64+1))
	testApproveDeviceAuthWithSignatureInfo(t, []*models.MobileAuthRequest{seed}, int64(1), testfixtures.ValidMobileDeviceAuthKeyForUser1, signatureWithWrongChallenge, 1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_NOT_VERIFIED, nil)
	assertRequestMarkedAsRejected(t, uint64(1), testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId)
}

// create an invalid signature by creating the wrong expected message (using the wrong "version")
func TestApproveDeviceAuthFailureInvalidSignatureWrongMessageByVersion(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	invalidSignature := crypto.MustSignMessageHash(testfixtures.ValidMobileDeviceAuthKeyForUser1.PrivateKey, mobiledeviceauth.CreateExpectedApproveMessageHash(2, seed.Payload, seed.ChallengeNumber.Int64))
	testApproveDeviceAuthWithSignatureInfo(t, []*models.MobileAuthRequest{seed}, int64(1), testfixtures.ValidMobileDeviceAuthKeyForUser1, invalidSignature, 1, pb.CompleteDeviceAuthResponse_RESULT_FAILED_NOT_VERIFIED, nil)
	assertRequestMarkedAsRejected(t, uint64(1), testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId)
}

func testApproveDeviceAuth(t *testing.T, seeds []*models.MobileAuthRequest, mobileAuthRequestID int64, mobileAuthRequest *models.MobileAuthRequest, deviceKey *testfixtures.MobileDeviceKeysWithPrivateKey, expectedResult pb.CompleteDeviceAuthResponse_Result, expectedErr error) {
	var approvalSignature string
	if mobileAuthRequest.ChallengeNumber.Valid {
		approvalSignature = crypto.MustSignMessageHash(deviceKey.PrivateKey, mobiledeviceauth.CreateExpectedApproveMessageHash(1, mobileAuthRequest.Payload, mobileAuthRequest.ChallengeNumber.Int64))
	} else {
		approvalSignature = crypto.MustSignMessageHash(deviceKey.PrivateKey, mobiledeviceauth.CreateExpectedApproveMessageWithoutChallengeHash(1, mobileAuthRequest.Payload))
	}
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId:    int64(mobileAuthRequestID),
		UserId:           int64(deviceKey.UserId),
		OauthAccessId:    int64(deviceKey.ID),
		Signature:        approvalSignature,
		SignatureVersion: 1,
	}
	testApproveDeviceAuthWithMessage(t, seeds, message, expectedResult, expectedErr)
}

func testApproveDeviceAuthWithSignatureInfo(t *testing.T, seeds []*models.MobileAuthRequest, mobileAuthRequestID int64, deviceKey *testfixtures.MobileDeviceKeysWithPrivateKey, signature string, signatureVersion int, expectedResult pb.CompleteDeviceAuthResponse_Result, expectedErr error) {
	message := &pb.CompleteDeviceAuthMessage{
		AuthRequestId:    int64(mobileAuthRequestID),
		UserId:           int64(deviceKey.UserId),
		OauthAccessId:    int64(deviceKey.ID),
		Signature:        signature,
		SignatureVersion: int64(signatureVersion),
	}

	// run the test with the message with the bad signature
	testApproveDeviceAuthWithMessage(t, seeds, message, expectedResult, expectedErr)
}

func assertRequestMarkedAsRejected(t *testing.T, mobileAuthRequestID uint64, userID uint64) {
	dbGetter := commonTesting.NewTestDatabaseGetter(t)
	store, err := commonStore.NewStore(dbGetter, false)
	require.NoError(t, err)

	authRequest, err := store.FindMobileAuthRequestByIdAndUserId(context.Background(), mobileAuthRequestID, userID)
	assert.Nil(t, err)
	assert.NotNil(t, authRequest)
	assert.True(t, authRequest.IsRejected(time.Now().Add(1*time.Second)))
}

func testApproveDeviceAuthWithMessage(t *testing.T, seeds []*models.MobileAuthRequest, message *pb.CompleteDeviceAuthMessage, expectedResult pb.CompleteDeviceAuthResponse_Result, expectedErr error) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	integrationTesting.SeedMobileAuthRequests(t, seeds)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.CompleteDeviceAuthRequest{
		Kind: &pb.CompleteDeviceAuthRequest_Approve{
			Approve: message,
		},
	}
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
