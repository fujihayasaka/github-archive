package devices

import (
	"context"
	"testing"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/feature"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/publisher"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/golang/mock/gomock"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestRequestDeviceAuthMissingId(t *testing.T) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.RequestDeviceAuthRequest{}
	resp, err := mdm.RequestDeviceAuth(context.Background(), req)

	require.NotNil(t, resp)
	assert.Equal(t, pb.RequestDeviceAuthResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.EqualError(t, err, "twirp error invalid_argument: UserId is required")
}

// user with one valid mobile device record and no existing requests and a request for another user is active
func TestRequestDeviceAuthSuccess(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)

	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), NewSignInRequestLayoutData(), gomock.Any()).Times(1)

	// seed the store with a request for user 999
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRequestDeviceAuth(t, mockPublisher, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, "")
}

func TestRequestDeviceAuthSuccessSkipChallengeTrue(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)

	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), NewSignInRequestLayoutData(), gomock.Any()).Times(1)
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRequestDeviceAuthWithSkipChallenge(t, mockPublisher, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, true, "", false)
}

func TestRequestDeviceAuthSuccessSkipChallengeFalse(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)

	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), NewSignInRequestLayoutData(), gomock.Any()).Times(1)
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRequestDeviceAuthWithSkipChallenge(t, mockPublisher, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, "", false)
}

// test layoutdata with ff enabled

func TestRequestDeviceAuthSuccessWithNotifydFFEnabled(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	expectedLayoutData := NewSignInRequestLayoutData()
	expectedLayoutData.AuthorProfileName = "GitHub"
	expectedLayoutData.AvatarUrl = "https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png"
	expectedLayoutData.ThreadType = common.MobileRequestTypeTwoFactorLoginName
	expectedLayoutData.ThreadId = "2" // number of preseeded requests + 1, see SeedMobileAuthRequests comment

	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), expectedLayoutData, gomock.Any()).Times(1)
	testRequestDeviceAuthWithSkipChallenge(t, mockPublisher, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, "", true)
}

// user with at least one valid mobile device record and no existing requests
func TestRequestDeviceAuthMultipleDeviceKeyStates(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)

	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.UserIdWithMultipleKeys), NewSignInRequestLayoutData(), gomock.Any()).Times(1)

	testRequestDeviceAuth(t, mockPublisher, testfixtures.UserIdWithMultipleKeys, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, "")
}

// user with valid mobile device record and existing rejected request
func TestRequestDeviceAuthValidRejected(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)

	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), NewSignInRequestLayoutData(), gomock.Any()).Times(1)

	seed := testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})

	testRequestDeviceAuth(t, mockPublisher, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, "")
}

// user with valid mobile device record and existing approved request
func TestRequestDeviceAuthValidApproved(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)

	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), NewSignInRequestLayoutData(), gomock.Any()).Times(1)

	seed := testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})

	testRequestDeviceAuth(t, mockPublisher, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, "")
}

// user with valid mobile device record and existing expired request
func TestRequestDeviceAuthValidExpired(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)

	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), NewSignInRequestLayoutData(), gomock.Any()).Times(1)

	seed := testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})

	testRequestDeviceAuth(t, mockPublisher, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, "")
}

func TestRequestDeviceAuthValidApprovedDeviceVerificationType(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), NewDeviceVerificationLayoutData(), gomock.Any()).Times(1)

	seed := testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})

	testRequestDeviceAuth(t, mockPublisher, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, common.MobileRequestTypeDeviceVerificationName)
}

func TestRequestDeviceAuthValidPasswordResetType(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), NewPasswordResetLayoutData(), gomock.Any()).Times(1)

	// ensure we tolerate an already approved request
	seed := testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})

	testRequestDeviceAuth(t, mockPublisher, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, common.MobileRequestTypeTwoFactorPasswordResetName)
}

func TestRequestDeviceAuthValidSudoChallengeType(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), NewSudoChallengeLayoutData(), gomock.Any()).Times(1)

	// ensure we tolerate an already approved request
	seed := testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})

	testRequestDeviceAuth(t, mockPublisher, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, common.MobileRequestTypeTwoFactorSudoChallengeName)
}

// user with valid mobile device record and an active request
func TestRequestDeviceAuthValidActive(t *testing.T) {
	mockPublisher := createTestMockPublisher(t)
	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId), NewSignInRequestLayoutData(), gomock.Any()).Times(1)

	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testRequestDeviceAuth(t, mockPublisher, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, common.MobileRequestTypeTwoFactorLoginName)
}

// user with no mobile device records
func TestRequestDeviceAuthNoMobileDevice(t *testing.T) {
	testRequestDeviceAuth(t, nil, testfixtures.UserIdWithoutMobileDevicesKey, pb.RequestDeviceAuthResponse_RESULT_FAILED_NO_VALID_DEVICE_KEYS, "")
}

// user with only a expired mobile device records
func TestRequestDeviceAuthExpiredMobileDevice(t *testing.T) {
	testRequestDeviceAuth(t, nil, testfixtures.ExpiredMobileDeviceAuthKeyForUser7.UserId, pb.RequestDeviceAuthResponse_RESULT_FAILED_NO_VALID_DEVICE_KEYS, "")
}

// user with only a revoked mobile device records
func TestRequestDeviceAuthRevokedMobileDevice(t *testing.T) {
	testRequestDeviceAuth(t, nil, testfixtures.RevokedMobileDeviceAuthKeyForUser8.UserId, pb.RequestDeviceAuthResponse_RESULT_FAILED_NO_VALID_DEVICE_KEYS, "")
}

// when there is no mobile auth request provided
func TestRequestDeviceAuthWithNoTypeProvided(t *testing.T) {
	actualRequestType, _ := mobiledeviceauth.GetRequestTypeValue("")
	assert.Equal(t, common.MobileRequestTypeTwoFactorLogin, actualRequestType)
}

// when the mobile auth request is 2fa_login
func TestRequestDeviceAuthWith2FALoginProvided(t *testing.T) {
	actualRequestType, _ := mobiledeviceauth.GetRequestTypeValue(common.MobileRequestTypeTwoFactorLoginName)
	assert.Equal(t, common.MobileRequestTypeTwoFactorLogin, actualRequestType)
}

// when the mobile auth request is device_verification
func TestRequestDeviceAuthWithDeviceVerificationProvided(t *testing.T) {
	actualRequestType, _ := mobiledeviceauth.GetRequestTypeValue(common.MobileRequestTypeDeviceVerificationName)
	assert.Equal(t, common.MobileRequestTypeDeviceVerification, actualRequestType)
}

// when the mobile auth request is 2fa_password_reset
func TestRequestDeviceAuthWit2FAPasswordResetProvided(t *testing.T) {
	actualRequestType, _ := mobiledeviceauth.GetRequestTypeValue(common.MobileRequestTypeTwoFactorPasswordResetName)
	assert.Equal(t, common.MobileRequestTypeTwoFactorPasswordReset, actualRequestType)
}

// when the mobile auth request is 2fa_password_reset
func TestRequestDeviceAuthWit2FASudoChallengeProvided(t *testing.T) {
	actualRequestType, _ := mobiledeviceauth.GetRequestTypeValue(common.MobileRequestTypeTwoFactorSudoChallengeName)
	assert.Equal(t, common.MobileRequestTypeTwoFactorSudoChallenge, actualRequestType)
}

// when an invalid mobile auth type is provided
func TestRequestDeviceAuthWithInvalidTypeProvided(t *testing.T) {
	_, err := mobiledeviceauth.GetRequestTypeValue("testing")

	assert.Equal(t, err, twirp.InvalidArgumentError("Type", "Invalid request type testing"))
}

func testRequestDeviceAuth(t *testing.T, mockPublisher publisher.NotificationPublisher, userId uint64, expectedResult pb.RequestDeviceAuthResponse_Result, requestType string) {
	now := time.Now()
	mdm := createTestMobileDeviceManager(t, now, mockPublisher)
	lifetime := time.Minute
	if requestType == common.MobileRequestTypeDeviceVerificationName {
		lifetime = time.Minute * 2
	}

	req := &pb.RequestDeviceAuthRequest{
		UserId: int64(userId),
		Type:   requestType,
	}
	resp, err := mdm.RequestDeviceAuth(context.Background(), req)

	assert.Nil(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, expectedResult.String(), resp.Result.String())
	if expectedResult == pb.RequestDeviceAuthResponse_RESULT_SUCCESS {
		assert.NotNil(t, resp.Id)
		assert.NotNil(t, resp.Challenge)
		assert.Equal(t, timestamppb.New(now.Add(lifetime)), resp.ExpiresAtTime)
	}
}

func testRequestDeviceAuthWithSkipChallenge(t *testing.T, mockPublisher publisher.NotificationPublisher, userId uint64, expectedResult pb.RequestDeviceAuthResponse_Result, skipChallenge bool, requestType string, notifydFFEnabled bool) {
	now := time.Now()
	mdm := createTestMobileDeviceManager(t, now, mockPublisher)
	lifetime := time.Minute

	req := &pb.RequestDeviceAuthRequest{
		UserId:        int64(userId),
		SkipChallenge: skipChallenge,
		Type:          requestType,
	}

	ctx := context.Background()
	features := make(map[string]bool)
	if notifydFFEnabled {
		features["notifyd_rich_mobile_push"] = true
		ctx = feature.NewContext(ctx, features)
	}

	resp, err := mdm.RequestDeviceAuth(ctx, req)

	assert.Nil(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, expectedResult, resp.Result)
	if expectedResult == pb.RequestDeviceAuthResponse_RESULT_SUCCESS {
		assert.NotNil(t, resp.Id)
		assert.NotNil(t, resp.Challenge)
		assert.Equal(t, timestamppb.New(now.Add(lifetime)), resp.ExpiresAtTime)
	}

	if skipChallenge {
		assert.Equal(t, "", resp.Challenge)
	} else {
		assert.NotEqual(t, "", resp.Challenge)
	}
}
