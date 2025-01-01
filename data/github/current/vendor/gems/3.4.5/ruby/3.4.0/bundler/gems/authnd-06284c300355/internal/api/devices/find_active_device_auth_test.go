package devices

import (
	"context"
	"testing"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
	"gopkg.in/guregu/null.v4"
)

func TestFindActiveDeviceAuthMissingUserId(t *testing.T) {
	req := &pb.FindActiveDeviceAuthRequest{
		OauthAccessId: 222,
	}
	testFindActiveDeviceAuthMissingArgs(t, req, twirp.RequiredArgumentError("UserId"))
}

func TestFindActiveDeviceAuthMissingOAuthAccessId(t *testing.T) {
	req := &pb.FindActiveDeviceAuthRequest{
		UserId: 111,
	}
	testFindActiveDeviceAuthMissingArgs(t, req, twirp.RequiredArgumentError("OauthAccessId"))
}

func TestFindActiveDeviceAuthSuccessful(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, 999, testfixtures.MobileDeviceAuthKeyNotInStore.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, int(seed.ID), false, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthSuccessfulWithoutChallenge(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestWithoutChallengeForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, 999, testfixtures.MobileDeviceAuthKeyNotInStore.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, int(seed.ID), false, false, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthSuccessfulWithAValidDeviceKey(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, int(seed.ID), true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthSuccessfulWithKeyCreatedAfterAuthRequest(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId), time.Now().Add(-1*time.Minute))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, int(seed.ID), false, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

// this should never happen, but we should handle it gracefully
// this is a case where an oauth access id ends up with multiple valid device auth keys
// we protect against this at device auth key registration time
func TestFindActiveDeviceAuthSuccessfulWithMultipleValidDeviceKeysForOauthAccessId(t *testing.T) {
	userId := testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.UserId
	oauthAccessId := testfixtures.ValidMobileDeviceAuthKeyForUser2WithMultipleValidKeysForOauthAccessId.OauthAccessId
	expectedHasValidKey := false
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(userId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, userId, oauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, int(seed.ID), expectedHasValidKey, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthMultipleStatesOneActive(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	seeds := []*models.MobileAuthRequest{
		seed,
		testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
	}
	testfixtures.AuthStore.SeedMobileAuthRequests(t, seeds)

	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, int(seed.ID), true, true, common.MobileRequestTypeTwoFactorLoginName, true)
}

func TestFindActiveDeviceAuthMultipleStatesMultipleActive(t *testing.T) {
	seeds := []*models.MobileAuthRequest{
		testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
	}
	testfixtures.AuthStore.SeedMobileAuthRequests(t, seeds)

	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, true)
}

func TestFindActiveDeviceAuthMultipleStatesNoneActive(t *testing.T) {
	seeds := []*models.MobileAuthRequest{
		testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
		testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId)),
	}
	testfixtures.AuthStore.SeedMobileAuthRequests(t, seeds)

	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, true)
}

func TestFindActiveDeviceAuthNotFound(t *testing.T) {
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthNotFoundNoDeviceKeys(t *testing.T) {
	testFindActiveDeviceAuth(t, testfixtures.MobileDeviceAuthKeyNotInStore.UserId, testfixtures.MobileDeviceAuthKeyNotInStore.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, false, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthRejected(t *testing.T) {
	seed := testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthApproved(t *testing.T) {
	seed := testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindActiveDeviceAuthExpired(t *testing.T) {
	seed := testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, true)
}

func TestFindActiveDeviceAuthExpiredAndRejected(t *testing.T) {
	seed := testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
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
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{mobileAuthRequest})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
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
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{mobileAuthRequest})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND, 0, true, true, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindDeviceKeyRegistrationWithNoRequestTypeProvided(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestWithRequestTypeForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId), "")
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, int(seed.ID), true, false, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindDeviceKeyRegistrationWith2FALoginRequestTypeProvided(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestWithRequestTypeForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId), common.MobileRequestTypeTwoFactorLoginName)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, int(seed.ID), true, false, common.MobileRequestTypeTwoFactorLoginName, false)
}

func TestFindDeviceKeyRegistrationWithDeviceVerificationRequestTypeProvided(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestWithRequestTypeForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId), common.MobileRequestTypeDeviceVerificationName)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, int(seed.ID), true, false, common.MobileRequestTypeDeviceVerificationName, false)
}

func TestFindDeviceKeyRegistrationWith2FAPasswordResetRequestTypeProvided(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestWithRequestTypeForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId), common.MobileRequestTypeTwoFactorPasswordResetName)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, int(seed.ID), true, false, common.MobileRequestTypeTwoFactorPasswordResetName, false)
}

func TestFindDeviceKeyRegistrationWith2FASudoChallengeRequestTypeProvided(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestWithRequestTypeForUser(t, int64(testfixtures.ValidMobileDeviceAuthKey1.UserId), common.MobileRequestTypeTwoFactorSudoChallengeName)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testFindActiveDeviceAuth(t, testfixtures.ValidMobileDeviceAuthKey1.UserId, testfixtures.ValidMobileDeviceAuthKey1.OauthAccessId, pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS, int(seed.ID), true, false, common.MobileRequestTypeTwoFactorSudoChallengeName, false)
}

func testFindActiveDeviceAuth(t *testing.T, userID uint64, oauthAccessId uint64, expectedResult pb.FindActiveDeviceAuthResponse_Result, expectedId int, expectedHasValidDeviceKey bool, expectedChallengeRequired bool, expectedRequestTypeName string, expectedHasExpiredAuthRequest bool) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

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
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)
	resp, err := mdm.FindActiveDeviceAuth(context.Background(), req)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.FindActiveDeviceAuthResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, expectedErr)
}
