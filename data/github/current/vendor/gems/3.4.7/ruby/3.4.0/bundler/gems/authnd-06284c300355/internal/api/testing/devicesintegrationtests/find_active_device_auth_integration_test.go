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
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"gopkg.in/guregu/null.v4"
)

func TestFindActiveDeviceAuthMissingUserId(t *testing.T) {
	req := &pb.FindActiveDeviceAuthRequest{
		OauthAccessId: 2,
	}
	testFindActiveDeviceAuthMissingArgs(t, req, twirp.RequiredArgumentError("UserId"))
}

func TestFindActiveDeviceAuthMissingOAuthAccessId(t *testing.T) {
	req := &pb.FindActiveDeviceAuthRequest{
		UserId: 1,
	}
	testFindActiveDeviceAuthMissingArgs(t, req, twirp.RequiredArgumentError("OauthAccessId"))
}

func TestFindActiveDeviceAuthSuccessful(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, 999, testfixtures.MobileDeviceAuthKeyNotInStore.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, 1, false, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthSuccessfulWithoutChallenge(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestWithoutChallengeForUser(t, 999)
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, 999, testfixtures.MobileDeviceAuthKeyNotInStore.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, 1, false, false, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthSuccessfulWithAValidDeviceKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, 1, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthSuccessfulWithKeyCreatedAfterAuthRequest(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId), time.Now().Add(-1*time.Minute))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, 1, false, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

// this should never happen, but we should handle it gracefully
// this is a case where an oauth access id ends up with multiple valid device auth keys
// we protect against this at device auth key registration time
func TestFindActiveDeviceAuthSuccessfulWithMultipleValidDeviceKeysForOauthAccessId(t *testing.T) {
	userId := testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId
	oauthAccessId := testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.OauthAccessId
	expectedHasValidKey := false
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(userId))
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, userId, oauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, 1, expectedHasValidKey, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthMultipleStatesOneActive(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	seeds := []*models.MobileAuthRequest{
		seed,
		testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
	}
	testFindActiveDeviceAuth(t, seeds, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, 1, true, true, common.MobileRequestTypeTwoFactorLoginName, true)
}

func TestFindActiveDeviceAuthMultipleStatesMultipleActive(t *testing.T) {
	seeds := []*models.MobileAuthRequest{
		testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
	}
	testFindActiveDeviceAuth(t, seeds, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, true)
}

func TestFindActiveDeviceAuthMultipleStatesNoneActive(t *testing.T) {
	seeds := []*models.MobileAuthRequest{
		testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
	}
	testFindActiveDeviceAuth(t, seeds, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, true)
}

func TestFindActiveDeviceAuthNotFound(t *testing.T) {
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthNotFoundNoDeviceKeys(t *testing.T) {
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.MobileDeviceAuthKeyNotInStore.UserId, testfixtures.MobileDeviceAuthKeyNotInStore.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, false, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthRejected(t *testing.T) {
	seed := testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthApproved(t *testing.T) {
	seed := testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthExpired(t *testing.T) {
	seed := testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, true)
}

func TestFindActiveDeviceAuthExpiredAndRejected(t *testing.T) {
	seed := testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthExpiredAndApproved(t *testing.T) {
	mobileAuthRequest := &models.MobileAuthRequest{
		UserId:          uint64(testfixtures.ValidMobileDeviceAuthKey1.UserId),
		Payload:         testfixtures.MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		ApprovedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
	}
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{mobileAuthRequest}, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

// rejected and approved (not a valid scenario, but including it in tests for completeness)
func TestFindActiveDeviceAuthRejectedAndApproved(t *testing.T) {
	mobileAuthRequest := &models.MobileAuthRequest{
		UserId:          uint64(testfixtures.ValidMobileDeviceAuthKey1.UserId),
		Payload:         testfixtures.MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		ApprovedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		RejectedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	}
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{mobileAuthRequest}, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindDeviceKeyRegistrationWithNoRequestTypeProvided(t *testing.T) {
	userID := testfixtures.ValidMobileDeviceAuthKey1.UserId
	seed := testfixtures.BuildActiveMobileAuthRequestWithRequestTypeForUser(t, int64(userID), "")
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, userID, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, 1, true, false, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindDeviceKeyRegistrationWith2FALoginRequestTypeProvided(t *testing.T) {
	userID := testfixtures.ValidMobileDeviceAuthKey1.UserId
	seed := testfixtures.BuildActiveMobileAuthRequestWithRequestTypeForUser(t, int64(userID), common.MobileRequestTypeTwoFactorLoginName)
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, userID, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, 1, true, false, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindDeviceKeyRegistrationWithDeviceVerificationRequestTypeProvided(t *testing.T) {
	userID := testfixtures.ValidMobileDeviceAuthKey1.UserId
	seed := testfixtures.BuildActiveMobileAuthRequestWithRequestTypeForUser(t, int64(userID), common.MobileRequestTypeDeviceVerificationName)
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, userID, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, 1, true, false, common.MobileRequestTypeDeviceVerificationName, false)
}

func TestFindDeviceKeyRegistrationWith2FAPasswordResetRequestTypeProvided(t *testing.T) {
	userID := testfixtures.ValidMobileDeviceAuthKey1.UserId
	seed := testfixtures.BuildActiveMobileAuthRequestWithRequestTypeForUser(t, int64(userID), common.MobileRequestTypeTwoFactorPasswordResetName)
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, userID, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, 1, true, false, common.MobileRequestTypeTwoFactorPasswordResetName, false)
}

func TestFindDeviceKeyRegistrationWith2FASudoChallengeRequestTypeProvided(t *testing.T) {
	userID := testfixtures.ValidMobileDeviceAuthKey1.UserId
	seed := testfixtures.BuildActiveMobileAuthRequestWithRequestTypeForUser(t, int64(userID), common.MobileRequestTypeTwoFactorSudoChallengeName)
	testFindActiveDeviceAuth(t, []*models.MobileAuthRequest{seed}, userID, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, 1, true, false, common.MobileRequestTypeTwoFactorSudoChallengeName, false)
}

func testFindActiveDeviceAuth(t *testing.T, seeds []*models.MobileAuthRequest, userID uint64, oauthAccessId uint64, expectedResult pb.FindActiveDeviceAuthResponse_Result, expectedId int, expectedHasValidDeviceKey bool, expectedChallengeRequired bool, expectedRequestTypeName string, expectedHasExpiredAuthRequest bool) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	integrationTesting.SeedMobileAuthRequests(t, seeds)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.FindActiveDeviceAuthRequest{
		UserId:        int64(userID),
		OauthAccessId: int64(oauthAccessId),
	}
	resp, err := mdm.FindActiveDeviceAuth(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, expectedResult, resp.Result)
	assert.NotNil(t, resp.Id)
	assert.Equal(t, int64(expectedId), resp.Id)
	assert.NotNil(t, resp.Payload)
	assert.Equal(t, expectedHasValidDeviceKey, resp.HasValidDeviceKey)
	assert.Equal(t, expectedHasExpiredAuthRequest, resp.HasExpiredAuthRequest)

	if expectedResult == pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS {
		assert.Equal(t, expectedChallengeRequired, resp.ChallengeRequired)
		assert.NotNil(t, resp.Type)
		assert.Equal(t, expectedRequestTypeName, resp.Type)
	}
}

func testFindActiveDeviceAuthMissingArgs(t *testing.T, req *pb.FindActiveDeviceAuthRequest, expectedErr error) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)
	resp, err := mdm.FindActiveDeviceAuth(context.Background(), req)
	assert.Nil(t, resp)
	assert.NotNil(t, err)
	assert.Equal(t, err, expectedErr)
}
