package testfixtures

import (
	"time"

	"github.com/github/authnd/internal/common/models"
	"gopkg.in/guregu/null.v4"
)

var OAuthApplications = []*models.OAuthApplication{
	DefaultOAuthApplication,
	SuspendedOAuthApplication,
	SpammyOAuthApplication,
}

var DefaultOAuthApplication = &models.OAuthApplication{
	ID:        1,
	Name:      null.StringFrom("default-application"),
	UserID:    null.IntFrom(UserOne.ID),
	State:     0,
	CreatedAt: models.NullMysqlDateTimeFromTime(time.Now()),
	Key:       null.StringFrom(OAuthApplicationKey),
}

var SuspendedOAuthApplication = &models.OAuthApplication{
	ID:        2,
	Name:      null.StringFrom("suspended-application"),
	UserID:    null.IntFrom(UserOne.ID),
	State:     1,
	CreatedAt: models.NullMysqlDateTimeFromTime(time.Now()),
	Key:       null.StringFrom(SuspendedOAuthApplicationKey),
}

var SpammyOAuthApplication = &models.OAuthApplication{
	ID:        3,
	Name:      null.StringFrom("spammy-owned-application"),
	UserID:    null.IntFrom(SpammyUser.ID),
	State:     1,
	CreatedAt: models.NullMysqlDateTimeFromTime(time.Now()),
	Key:       null.StringFrom(SpammyOAuthApplicationKey),
}
