package testfixtures

import (
	"testing"
	"time"

	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
	"github.com/github/authnd/internal/common/models"
	"gopkg.in/guregu/null.v4"
)

func BuildActiveMobileAuthRequestForUser(t *testing.T, userId int64) *models.MobileAuthRequest {
	t.Helper()
	return &models.MobileAuthRequest{
		UserId:          uint64(userId),
		Payload:         MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Second * 60)),
	}
}

func BuildActiveMobileAuthRequestWithoutChallengeForUser(t *testing.T, userId int64) *models.MobileAuthRequest {
	t.Helper()
	return &models.MobileAuthRequest{
		UserId:    uint64(userId),
		Payload:   MustGeneratePayload(time.Now()),
		CreatedAt: models.NullMysqlDateTimeFromTime(time.Now()),
		ExpiresAt: models.NullMysqlDateTimeFromTime(time.Now().Add(time.Second * 60)),
	}
}

func BuildActiveMobileAuthRequestForUserWithCreatedAtTime(t *testing.T, userId int64, createdAtTime time.Time) *models.MobileAuthRequest {
	t.Helper()
	return &models.MobileAuthRequest{
		UserId:          uint64(userId),
		Payload:         MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(createdAtTime),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Second * 60)),
	}
}

func BuildActiveMobileAuthRequestWithoutChallengeForUserWithCreatedAtTime(t *testing.T, userId int64, createdAtTime time.Time) *models.MobileAuthRequest {
	t.Helper()
	return &models.MobileAuthRequest{
		UserId:    uint64(userId),
		Payload:   MustGeneratePayload(time.Now()),
		CreatedAt: models.NullMysqlDateTimeFromTime(createdAtTime),
		ExpiresAt: models.NullMysqlDateTimeFromTime(time.Now().Add(time.Second * 60)),
	}
}

func BuildExpiredMobileAuthRequestForUser(t *testing.T, userId int64) *models.MobileAuthRequest {
	t.Helper()
	return &models.MobileAuthRequest{
		UserId:          uint64(userId),
		Payload:         MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(-time.Minute)),
	}
}

func BuildApprovedMobileAuthRequestForUser(t *testing.T, userId int64) *models.MobileAuthRequest {
	t.Helper()
	return &models.MobileAuthRequest{
		UserId:          uint64(userId),
		Payload:         MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		ApprovedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Second * 60)),
		Type:            common.MobileRequestTypeTwoFactorLogin,
	}
}

func BuildActiveMobileAuthRequestWithRequestTypeForUser(t *testing.T, userId int64, requestType string) *models.MobileAuthRequest {
	t.Helper()
	requestTypeValue, _ := mobiledeviceauth.GetRequestTypeValue(requestType)
	return &models.MobileAuthRequest{
		UserId:    uint64(userId),
		Payload:   MustGeneratePayload(time.Now()),
		CreatedAt: models.NullMysqlDateTimeFromTime(time.Now()),
		ExpiresAt: models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * 24)),
		Type:      requestTypeValue,
	}
}

func BuildRejectedMobileAuthRequestForUser(t *testing.T, userId int64) *models.MobileAuthRequest {
	t.Helper()
	return &models.MobileAuthRequest{
		UserId:          uint64(userId),
		Payload:         MustGeneratePayload(time.Now()),
		ChallengeNumber: null.IntFrom(1),
		CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
		RejectedAt:      models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
		ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Second * 60)),
	}
}

var MobileAuthRequestNotInStore = &models.MobileAuthRequest{
	ID:              9876,
	UserId:          uint64(1010),
	Payload:         MustGeneratePayload(time.Now()),
	ChallengeNumber: null.IntFrom(1),
	CreatedAt:       models.NullMysqlDateTimeFromTime(time.Now()),
	ExpiresAt:       models.NullMysqlDateTimeFromTime(time.Now().Add(time.Second * 60)),
}

func MustGeneratePayload(t time.Time) []byte {
	payload, err := mobiledeviceauth.GeneratePayload(t)
	if err != nil {
		panic(err)
	}
	return payload
}
