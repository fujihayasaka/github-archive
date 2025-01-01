//go:build db && !proxima

package devicesintegrationtests

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/github/authnd/client"
	clientMiddleware "github.com/github/authnd/client/middleware"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/devices"
	"github.com/github/authnd/internal/api/middleware"
	"github.com/github/authnd/internal/api/testhelpers"
	apiTesting "github.com/github/authnd/internal/api/testing"
	integrationTesting "github.com/github/authnd/internal/api/testing"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/github/authnd/internal/mocks"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	layoutProto "github.com/github/notifyd/proto/layouts/mobile"
	"github.com/golang/mock/gomock"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestRequestDeviceAuthMissingId(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RequestDeviceAuthRequest{}
	resp, err := mdm.RequestDeviceAuth(context.Background(), req)

	assert.Nil(t, resp)
	require.NotNil(t, err)
	assert.Equal(t, err, twirp.RequiredArgumentError("UserId"))
}

// user with at least one valid mobile device record and no existing requests
func TestRequestDeviceAuthMultipleDeviceKeyStates(t *testing.T) {
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.UserIdWithMultipleKeys, 0, 1, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, false, "", 0, []string{})
}

func TestRequestDeviceAuthMultipleDeviceKeyStatesSkipChallengeTrue(t *testing.T) {
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.UserIdWithMultipleKeys, 0, 1, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, true, true, "", 0, []string{})
}

// user with valid mobile device record and existing rejected request
func TestRequestDeviceAuthValidRejected(t *testing.T) {
	seed := testfixtures.BuildRejectedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{seed}, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, 1, 2, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, false, "", 0, []string{})
}

// user with valid mobile device record and existing approved request
func TestRequestDeviceAuthValidApproved(t *testing.T) {
	seed := testfixtures.BuildApprovedMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{seed}, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, 1, 2, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, false, "", 0, []string{})
}

// user with valid mobile device record and existing expired request
func TestRequestDeviceAuthValidExpired(t *testing.T) {
	seed := testfixtures.BuildExpiredMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{seed}, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, 1, 2, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, false, "", 0, []string{})
}

// user with valid mobile device record and an active request
func TestRequestDeviceAuthValidActive(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{seed}, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, 1, 2, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, false, "", 0, []string{})
	// verify the seed is no longer valid
	assertExpiredMobileAuthRequest(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
}

func TestRequestDeviceAuthValidActiveAndOverrideAndForcesSkipChallenge(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{seed}, testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId, 1, 2, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, true, false, "", 0, []string{})
	// verify the seed is no longer valid
	assertExpiredMobileAuthRequest(t, int64(testfixtures.ValidMobileDeviceAuthKeyForUser1.UserId))
}

// user with no mobile device records
func TestRequestDeviceAuthNoMobileDevice(t *testing.T) {
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.UserIdWithoutMobileDevicesKey, 0, 0, 0, pb.RequestDeviceAuthResponse_RESULT_FAILED_NO_VALID_DEVICE_KEYS, false, false, "", 0, []string{})
}

// user with only a expired mobile device records
func TestRequestDeviceAuthExpiredMobileDevice(t *testing.T) {
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.ExpiredMobileDeviceAuthKeyForUser7.UserId, 0, 0, 0, pb.RequestDeviceAuthResponse_RESULT_FAILED_NO_VALID_DEVICE_KEYS, false, false, "", 0, []string{})
}

// user with only a revoked mobile device record
func TestRequestDeviceAuthRevokedMobileDevice(t *testing.T) {
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.RevokedMobileDeviceAuthKeyForUser8.UserId, 0, 0, 0, pb.RequestDeviceAuthResponse_RESULT_FAILED_NO_VALID_DEVICE_KEYS, false, false, "", 0, []string{})
}

// user with at least one valid mobile device will have request expired if the message publishing fails
func TestRequestDeviceAuthExpiresRequestOnFailure(t *testing.T) {
	userId := testfixtures.UserIdWithMultipleValidDeviceKeys
	resp := testRequestDeviceAuthWithPublisher(t, userId, common.MobileRequestTypeTwoFactorLoginName, devices.NewSignInRequestLayoutData())
	assert.Equal(t, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, resp.Result)
	assertExpiredMobileAuthRequest(t, int64(userId))
}

// user with at least one valid mobile device will have request expired if the message publishing fails
func TestRequestDeviceAuthDeviceVerificationRequest(t *testing.T) {
	userId := testfixtures.UserIdWithMultipleValidDeviceKeys
	resp := testRequestDeviceAuthWithPublisher(t, userId, common.MobileRequestTypeDeviceVerificationName, devices.NewDeviceVerificationLayoutData())
	assert.Equal(t, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, resp.Result)
	assertExpiredMobileAuthRequest(t, int64(userId))
}

// user with at least one valid mobile device will have request expired if the message publishing fails
func TestRequestDeviceAuthPasswordResetRequest(t *testing.T) {
	userId := testfixtures.UserIdWithMultipleValidDeviceKeys
	resp := testRequestDeviceAuthWithPublisher(t, userId, common.MobileRequestTypeTwoFactorPasswordResetName, devices.NewPasswordResetLayoutData())
	assert.Equal(t, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, resp.Result)
	assertExpiredMobileAuthRequest(t, int64(userId))
}

// user with at least one valid mobile device will have request expired if the message publishing fails
func TestRequestDeviceAuthSudoChallengeRequest(t *testing.T) {
	userId := testfixtures.UserIdWithMultipleValidDeviceKeys
	resp := testRequestDeviceAuthWithPublisher(t, userId, common.MobileRequestTypeTwoFactorSudoChallengeName, devices.NewSudoChallengeLayoutData())
	assert.Equal(t, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, resp.Result)
	assertExpiredMobileAuthRequest(t, int64(userId))
}

func testRequestDeviceAuthWithPublisher(t *testing.T, userId int, requestType string, notificationLayout *layoutProto.Basic) *pb.RequestDeviceAuthResponse {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	errString := "writing message to topic `localhost.ingest.notifyd.v0.Notify`: kafka: client has run out of available brokers to talk to (Is your cluster reachable?)"
	mockPublisher := mocks.NewMockNotificationPublisher(ctrl)

	mockPublisher.EXPECT().PublishNotification(gomock.Any(), int64(userId), notificationLayout, gomock.Any()).Times(1).Return(errors.New(errString))

	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := devices.NewMobileDeviceManagerServer(
		store,
		mockPublisher,
		middleware.NewServerHooks(apiTesting.TestApiConfig(), testhelpers.GetTestLogger(), stats.NullStatter, apiTesting.TestHMACKey),
	)

	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServerWithMockedPublisher(t, server, store)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	assertMobileAuthRequestCountForUser(t, int64(userId), 0)

	req := &pb.RequestDeviceAuthRequest{
		UserId: int64(userId),
		Type:   requestType,
	}
	resp, err := mdm.RequestDeviceAuth(context.Background(), req)

	return resp
}

func TestRequestDeviceAuthWithNoRequestType(t *testing.T) {
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.UserIdWithMultipleKeys, 0, 1, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, false, "", 0, []string{})
}

func TestRequestDeviceAuthWithRequestTypeTwoFactorLogin(t *testing.T) {
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.UserIdWithMultipleKeys, 0, 1, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, false, "2fa_login", 0, []string{})
}

func TestRequestDeviceAuthWithRequestTypeDeviceVerification(t *testing.T) {
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.UserIdWithMultipleKeys, 0, 1, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, false, "device_verification", 1, []string{})
}

func TestRequestDeviceAuthWithRequestTypeTwoFactorPasswordReset(t *testing.T) {
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.UserIdWithMultipleKeys, 0, 1, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, false, "2fa_password_reset", 2, []string{})
}

func TestRequestDeviceAuthWithRequestTypeTwoFactorSudoChallenge(t *testing.T) {
	testRequestDeviceAuth(t, []*models.MobileAuthRequest{}, testfixtures.UserIdWithMultipleKeys, 0, 1, 1, pb.RequestDeviceAuthResponse_RESULT_SUCCESS, false, false, "2fa_sudo_challenge", 3, []string{})
}

func TestRequestDeviceAuthWithInvalidRequestType(t *testing.T) {
	requestType := "fake_type"
	userId := testfixtures.UserIdWithMultipleKeys
	store := testfixtures.CreateTestDatabaseStore(t, true)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, nil)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	req := &pb.RequestDeviceAuthRequest{
		UserId: int64(userId),
		Type:   requestType,
	}
	resp, err := mdm.RequestDeviceAuth(context.Background(), req)

	assert.Nil(t, resp)
	require.NotNil(t, err)
	assert.EqualError(t, err, "twirp error invalid_argument: Type Invalid request type fake_type")
}

type featureFlaggedHttpClient struct {
	delegate        pb.HTTPClient
	enabledFeatures []string
}

func newFeatureFlaggedHttpClient(c pb.HTTPClient, enabledFeatures []string) pb.HTTPClient {
	return &featureFlaggedHttpClient{
		delegate:        c,
		enabledFeatures: enabledFeatures,
	}
}

func (f *featureFlaggedHttpClient) Do(req *http.Request) (*http.Response, error) {
	serialized, err := json.Marshal(f.enabledFeatures)
	if err != nil {
		return nil, err
	}
	encoded := base64.StdEncoding.EncodeToString(serialized)
	req.Header.Set("X-GitHub-Features", encoded)
	return f.delegate.Do(req)
}

func testRequestDeviceAuth(t *testing.T, seeds []*models.MobileAuthRequest, userId uint64, initialRequestCountForUser int, expectedRequestCountForUser int, expectedPublishedCountForUser int, expectedResult pb.RequestDeviceAuthResponse_Result, requestSkipChallenge bool, expectChallenge bool, requestType string, expectedRequestTypeValue int, enabledFeatures []string) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	integrationTesting.SeedMobileAuthRequests(t, seeds)
	messageChan := make(chan hydro.Message, 10)
	mobileDeviceServer := integrationTesting.CreateTestMobileDeviceManagerServer(t, store, messageChan)

	customHttpClient := pb.HTTPClient(http.DefaultClient)
	customHttpClient = newFeatureFlaggedHttpClient(customHttpClient, enabledFeatures)
	customHttpClient = clientMiddleware.ApplyHMACKey(customHttpClient, integrationTesting.TestHMACKey)
	mdm, err := client.NewMobileDeviceManager(mobileDeviceServer.URL, integrationTesting.TestCatalogServiceName, client.WithCustomHTTPClient(customHttpClient), client.WithHMACKey(integrationTesting.TestHMACKey))
	require.NoError(t, err)

	assertMobileAuthRequestCountForUser(t, int64(userId), initialRequestCountForUser)

	req := &pb.RequestDeviceAuthRequest{
		UserId:        int64(userId),
		SkipChallenge: requestSkipChallenge,
		Type:          requestType,
	}
	resp, err := mdm.RequestDeviceAuth(context.Background(), req)

	assert.Nil(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, expectedResult, resp.Result)
	if expectedResult == pb.RequestDeviceAuthResponse_RESULT_SUCCESS {
		assert.NotNil(t, resp.Id)
		assert.NotNil(t, resp.ExpiresAtTime)

		assertMobileAuthRequestType(t, expectedRequestTypeValue)

		if expectChallenge {
			assert.Equal(t, "", resp.Challenge)
			assertNilMobileAuthRequestChallenge(t, resp.Id)
		} else {
			assert.NotEqual(t, "", resp.Challenge)
		}
	}

	assertMobileAuthRequestCountForUser(t, int64(userId), expectedRequestCountForUser)

	close(messageChan)
	var publishedMessages []hydro.Message
	for msg := range messageChan {
		publishedMessages = append(publishedMessages, msg)
	}
	assert.Equal(t, len(publishedMessages), expectedPublishedCountForUser)

	if len(publishedMessages) == 1 {
		assert.Equal(t, "notifyd.v1.Notify", publishedMessages[0].Topic)
	}
}

func assertMobileAuthRequestCountForUser(t *testing.T, userId int64, expectedCount int) {
	authndDB, _, _, _ := commonTesting.OpenTestDBs(t)
	t.Cleanup(func() {
		// ensure we close db connections after each test
		authndDB.Close()
	})
	var count int
	err := authndDB.QueryRow("SELECT COUNT(*) FROM mobile_auth_requests WHERE user_id = ?", userId).Scan(&count)
	require.NoError(t, err)
	require.Equal(t, expectedCount, count)
}

func assertNilMobileAuthRequestChallenge(t *testing.T, mobileAuthRequestId int64) {
	authndDB, _, _, _ := commonTesting.OpenTestDBs(t)
	t.Cleanup(func() {
		// ensure we close db connections after each test
		authndDB.Close()
	})
	var count int
	err := authndDB.QueryRow("SELECT COUNT(*) FROM mobile_auth_requests WHERE id = ? AND challenge_number IS NULL", mobileAuthRequestId).Scan(&count)
	require.NoError(t, err)
	require.Equal(t, 1, count)
}

func assertExpiredMobileAuthRequest(t *testing.T, userId int64) {
	authndDB, _, _, _ := commonTesting.OpenTestDBs(t)
	t.Cleanup(func() {
		// ensure we close db connections after each test
		authndDB.Close()
	})

	var count int
	err := authndDB.QueryRow("SELECT COUNT(*) FROM mobile_auth_requests WHERE expires_at_utc < ? AND user_id = ?", time.Now().Add(time.Second), userId).Scan(&count)
	require.NoError(t, err)
	require.Equal(t, 1, count)
}

// create helper to validate the mobile auth request type
func assertMobileAuthRequestType(t *testing.T, expectedValue int) {
	authndDB, _, _, _ := commonTesting.OpenTestDBs(t)
	t.Cleanup(func() {
		// ensure we close db connections after each test
		authndDB.Close()
	})

	var requestTypeValue int
	err := authndDB.QueryRow("SELECT type FROM mobile_auth_requests").Scan(&requestTypeValue)
	require.NoError(t, err)
	require.Equal(t, expectedValue, requestTypeValue)
}
