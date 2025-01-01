package testfixtures

import (
	"testing"
	"time"

	"github.com/github/authnd/internal/common/models"
	"golang.org/x/crypto/bcrypt"
	"gopkg.in/guregu/null.v4"
)

var Users = map[string]*models.User{
	UserOne.Login:               UserOne,
	MonalisaUser.Login:          MonalisaUser,
	TrollUser.Login:             TrollUser,
	DeployUser.Login:            DeployUser,
	MissingPublicKeyUser.Login:  MissingPublicKeyUser,
	MismatchPublicKeyUser.Login: MismatchPublicKeyUser,
	RandomUser.Login:            RandomUser,
	FindCredentialsUser.Login:   FindCredentialsUser,
	SuspendedUser.Login:         SuspendedUser,
	BotUser.Login:               BotUser,
	SuspendedBotUser.Login:      SuspendedBotUser,
	SpammyUser.Login:            SpammyUser,
	OrgOne.Login:                OrgOne,
}

// Used by legacy PrAT tests
var UserOne = &models.User{
	ID:    1,
	Type:  "User",
	Login: "userone",
}

var MonalisaUser = &models.User{
	ID:              2,
	Type:            "User",
	Login:           "monalisa",
	BcryptAuthToken: null.StringFrom(mustGenerateFromPassword("passworD1")),
	TokenSecret:     null.StringFrom("567f2e98993f8d05bf6c1c3a374d16766a0d0fa9"),
}

var TrollUser = &models.User{
	ID:              3,
	Type:            "User",
	Login:           "troll",
	BcryptAuthToken: null.StringFrom(mustGenerateFromPassword("trollyourfriends")),
	TokenSecret:     null.StringFrom("6c6504019ad1c7c776caa303f5d8ee306318de4a"),
	SuspendedAt:     OneHundredHoursAgoNullMysqlDateTime,
}

// Don't seed this user into the database
var UnknownUser = &models.User{
	ID:              999999,
	Type:            "User",
	Login:           "whodis",
	BcryptAuthToken: null.StringFrom(mustGenerateFromPassword("newphone")),
	TokenSecret:     null.StringFrom("b09cda2e43bd8f56d95f10d5e65772a3d3fe6adb"),
}

var DeployUser = &models.User{
	ID:    42,
	Type:  "User",
	Login: "deployer",
}

var MissingPublicKeyUser = &models.User{
	ID:    7,
	Type:  "User",
	Login: "missing",
}

var MismatchPublicKeyUser = &models.User{
	ID:    8,
	Type:  "User",
	Login: "mismatch",
}

// NOTE: users 4 and 5 are intentionally missing
var RandomUser = &models.User{
	ID:              6,
	Type:            "User",
	Login:           "yes",
	BcryptAuthToken: null.StringFrom(mustGenerateFromPassword("sure")),
	TokenSecret:     null.StringFrom("afb537f8160cdfc74287df470b8b1444492f576c"),
}

// FindCredentialsUser is a user used for looking up tokens in FindCredentials
var FindCredentialsUser = &models.User{
	ID:    9,
	Type:  "User",
	Login: "findcredentials",
}

var SuspendedUser = &models.User{
	ID:          10,
	Type:        "User",
	Login:       "suspended",
	SuspendedAt: models.NullMysqlDateTimeFromTime(time.Now().Add(time.Hour * -24)),
}

var BotUser = &models.User{
	ID:    11,
	Type:  "Bot",
	Login: "github-app-bot",
}

var SuspendedBotUser = &models.User{
	ID:          12,
	Type:        "User",
	Login:       "suspended-bot",
	SuspendedAt: models.NullMysqlDateTimeFromTime(time.Now().Add(-24 * time.Hour)),
}

var SpammyUser = &models.User{
	ID:              13,
	Type:            "User",
	Login:           "spammy-user",
	BcryptAuthToken: null.StringFrom(mustGenerateFromPassword("passworD1")),
	TokenSecret:     null.StringFrom("789f2e98993f8d05bf6c1c3a374d16766a0d0fa9"),
	Spammy:          null.IntFrom(1),
}

var OrgOne = &models.User{
	ID:    14,
	Login: "org",
	Type:  "Organization",
}

func MustCreateUserHydroPayload(t *testing.T, model models.User) []byte {
	userJSON := map[string]interface{}{
		"id":                         model.ID,
		"login":                      model.Login,
		"created_at":                 model.CreatedAt,
		"suspended_at":               model.SuspendedAt,
		"disabled":                   model.Disabled,
		"password_hash":              model.PasswordHash,
		"weak_password_check_result": model.WeakPasswordCheckResult,
		"spammy":                     model.Spammy,
	}

	if model.BcryptAuthToken.Valid {
		userJSON["bcrypt_auth_token"] = model.BcryptAuthToken.String
	}

	if model.TokenSecret.Valid {
		userJSON["token_secret"] = model.TokenSecret.String
	}

	return MustCreatePayloadBytes(t, userJSON)
}

// mustGenerateFromPassword generates a bcrypt hash of the given password
func mustGenerateFromPassword(password string) string {
	h, err := bcrypt.GenerateFromPassword([]byte(password), 8)
	if err != nil {
		panic(err)
	}
	return string(h)
}
