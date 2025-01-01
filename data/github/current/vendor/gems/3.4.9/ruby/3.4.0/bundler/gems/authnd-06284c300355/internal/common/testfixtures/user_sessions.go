package testfixtures

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/github/authnd/internal/common/models"
	"gopkg.in/guregu/null.v4"
)

var UserSessions = map[int64]*models.UserSession{
	MonalisaValidUserSession.ID:             MonalisaValidUserSession,
	MonalisaExpiredUserSession.ID:           MonalisaExpiredUserSession,
	MonalisaRevokedUserSession.ID:           MonalisaRevokedUserSession,
	ImpersonatedUserSession.ID:              ImpersonatedUserSession,
	MonalisaHardExpiredUserSession.ID:       MonalisaHardExpiredUserSession,
	MonalisaExpiredAndRevokedUserSession.ID: MonalisaExpiredAndRevokedUserSession,
}

var MonalisaValidUserSession = &models.UserSession{
	ID:         6,
	UserID:     MonalisaUser.ID,
	AccessedAt: models.NullMysqlDateTimeFromTime(time.Date(2080, 1, 11, 10, 1, 2, 0, time.UTC)),
}

var MonalisaExpiredUserSession = &models.UserSession{
	ID:         1,
	UserID:     MonalisaUser.ID,
	AccessedAt: models.NullMysqlDateTimeFromTime(time.Date(2020, 1, 11, 10, 1, 2, 0, time.UTC)),
}

var MonalisaRevokedUserSession = &models.UserSession{
	ID:         2,
	UserID:     MonalisaUser.ID,
	AccessedAt: models.NullMysqlDateTimeFromTime(time.Date(2080, 1, 11, 10, 1, 2, 0, time.UTC)),
	RevokedAt:  models.NullMysqlDateTimeFromTime(time.Date(2020, 1, 11, 10, 1, 2, 0, time.UTC)),
}

var ImpersonatedUserSession = &models.UserSession{
	ID:                    3,
	UserID:                RandomUser.ID,
	AccessedAt:            models.NullMysqlDateTimeFromTime(time.Date(2080, 1, 11, 10, 1, 2, 0, time.UTC)),
	ImpersonatorSessionId: null.IntFrom(MonalisaValidUserSession.ID),
}

var MonalisaExpiredAndRevokedUserSession = &models.UserSession{
	ID:         4,
	UserID:     MonalisaUser.ID,
	AccessedAt: models.NullMysqlDateTimeFromTime(time.Date(2020, 1, 11, 10, 1, 2, 0, time.UTC)),
	RevokedAt:  models.NullMysqlDateTimeFromTime(time.Date(2020, 1, 11, 10, 1, 2, 0, time.UTC)),
}

var MonalisaHardExpiredUserSession = &models.UserSession{
	ID:         5,
	UserID:     MonalisaUser.ID,
	AccessedAt: models.NullMysqlDateTimeFromTime(time.Date(2080, 1, 11, 10, 1, 2, 0, time.UTC)),
	ExpiresAt:  models.NullMysqlDateTimeFromTime(time.Date(2020, 1, 11, 10, 1, 2, 0, time.UTC)),
}

// Don't seed this into the DB
var MonalisaUnknownUserSession = &models.UserSession{
	ID:         999999,
	UserID:     MonalisaUser.ID,
	AccessedAt: models.NullMysqlDateTimeFromTime(time.Date(2080, 1, 11, 10, 1, 2, 0, time.UTC)),
	RevokedAt:  models.NullMysqlDateTimeFromTime(time.Date(2020, 1, 11, 10, 1, 2, 0, time.UTC)),
}

func MustCreateUserSessionHydroPayload(t *testing.T, model models.UserSession) []byte {
	payload, err := json.Marshal(model)
	if err != nil {
		t.Fatal(err)
	}

	return MustCreatePayloadBytes(t, json.RawMessage(payload))
}
