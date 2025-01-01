package devices

import (
	"context"
	"testing"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"
	"gopkg.in/guregu/null.v4"
)

func TestGetDeviceAuthStatusMissingId(t *testing.T) {
	req := &pb.GetDeviceAuthStatusRequest{
		UserId: 2,
	}
	testGetDeviceAuthStatusMissingArgs(t, req, twirp.RequiredArgumentError("Id"))
}

func TestGetDeviceAuthStatusMissingUserId(t *testing.T) {
	req := &pb.GetDeviceAuthStatusRequest{
		Id: 1,
	}
	testGetDeviceAuthStatusMissingArgs(t, req, twirp.RequiredArgumentError("UserId"))
}

func TestGetDeviceAuthStatusNotFoundById(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testGetDeviceAuthStatus(t, 222, 999, pb.GetDeviceAuthStatusResponse_RESULT_FAILED_NOT_FOUND, pb.GetDeviceAuthStatusResponse_STATUS_UNKNOWN)
}

func TestGetDeviceAuthStatusNotFoundByUserId(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testGetDeviceAuthStatus(t, seed.ID, 1, pb.GetDeviceAuthStatusResponse_RESULT_FAILED_NOT_FOUND, pb.GetDeviceAuthStatusResponse_STATUS_UNKNOWN)
}

func TestGetDeviceAuthStatusActive(t *testing.T) {
	seed := testfixtures.BuildActiveMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testGetDeviceAuthStatus(t, seed.ID, 999, pb.GetDeviceAuthStatusResponse_RESULT_SUCCESS, pb.GetDeviceAuthStatusResponse_STATUS_ACTIVE)
}

func TestGetDeviceAuthStatusRejected(t *testing.T) {
	seed := testfixtures.BuildRejectedMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testGetDeviceAuthStatus(t, seed.ID, 999, pb.GetDeviceAuthStatusResponse_RESULT_SUCCESS, pb.GetDeviceAuthStatusResponse_STATUS_REJECTED)
}

func TestGetDeviceAuthStatusApproved(t *testing.T) {
	seed := testfixtures.BuildApprovedMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testGetDeviceAuthStatus(t, seed.ID, 999, pb.GetDeviceAuthStatusResponse_RESULT_SUCCESS, pb.GetDeviceAuthStatusResponse_STATUS_APPROVED)
}

func TestGetDeviceAuthStatusExpired(t *testing.T) {
	seed := testfixtures.BuildExpiredMobileAuthRequestForUser(t, 999)
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{seed})
	testGetDeviceAuthStatus(t, seed.ID, 999, pb.GetDeviceAuthStatusResponse_RESULT_SUCCESS, pb.GetDeviceAuthStatusResponse_STATUS_EXPIRED)
}

func TestGetDeviceAuthStatusExpiredAndRejected(t *testing.T) {
	mobileAuthRequest := &models.MobileAuthRequest{
		UserId:          uint64(999),
		Payload:         testfixtures.MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		RejectedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
	}
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{mobileAuthRequest})
	testGetDeviceAuthStatus(t, mobileAuthRequest.ID, 999, pb.GetDeviceAuthStatusResponse_RESULT_SUCCESS, pb.GetDeviceAuthStatusResponse_STATUS_EXPIRED)
}

func TestGetDeviceAuthStatusExpiredAndApproved(t *testing.T) {
	mobileAuthRequest := &models.MobileAuthRequest{
		UserId:          uint64(999),
		Payload:         testfixtures.MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		ApprovedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
	}
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{mobileAuthRequest})
	testGetDeviceAuthStatus(t, mobileAuthRequest.ID, 999, pb.GetDeviceAuthStatusResponse_RESULT_SUCCESS, pb.GetDeviceAuthStatusResponse_STATUS_EXPIRED)
}

// rejected and approved (not a valid scenario, but including it in tests for completeness)
func TestGetDeviceAuthStatusRejectedAndApproved(t *testing.T) {
	mobileAuthRequest := &models.MobileAuthRequest{
		UserId:          uint64(999),
		Payload:         testfixtures.MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		ApprovedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		RejectedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
	}
	testfixtures.AuthStore.SeedMobileAuthRequests(t, []*models.MobileAuthRequest{mobileAuthRequest})
	testGetDeviceAuthStatus(t, mobileAuthRequest.ID, 999, pb.GetDeviceAuthStatusResponse_RESULT_SUCCESS, pb.GetDeviceAuthStatusResponse_STATUS_REJECTED)
}

func testGetDeviceAuthStatus(t *testing.T, id uint64, userId uint64, expectedResult pb.GetDeviceAuthStatusResponse_Result, expectedStatus pb.GetDeviceAuthStatusResponse_Status) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)

	req := &pb.GetDeviceAuthStatusRequest{
		Id:     int64(id),
		UserId: int64(userId),
	}
	resp, err := mdm.GetDeviceAuthStatus(context.Background(), req)

	assert.Nil(t, err)
	assert.NotNil(t, resp)
	assert.Equal(t, expectedResult, resp.Result)
	assert.Equal(t, expectedStatus, resp.Status)
}

func testGetDeviceAuthStatusMissingArgs(t *testing.T, req *pb.GetDeviceAuthStatusRequest, expectedErr error) {
	mdm := createTestMobileDeviceManager(t, time.Now(), nil)
	resp, err := mdm.GetDeviceAuthStatus(context.Background(), req)
	assert.NotNil(t, resp)
	assert.Equal(t, pb.GetDeviceAuthStatusResponse_RESULT_FAILED_GENERIC, resp.Result)
	assert.NotNil(t, err)
	assert.Equal(t, err, expectedErr)
}
