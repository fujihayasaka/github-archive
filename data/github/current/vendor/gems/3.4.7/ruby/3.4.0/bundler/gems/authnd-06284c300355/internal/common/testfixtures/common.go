package testfixtures

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/github/authnd/internal/api/sat"
	"github.com/github/authnd/internal/common/models"
	"github.com/stretchr/testify/require"
)

var (
	OneHundredHoursAgo      = time.Now().Add(-100 * time.Hour).UTC()
	TwentyThreeHoursFromNow = time.Now().Add(23 * time.Hour).UTC()
	SixDaysFromNow          = time.Now().Add(6 * 24 * time.Hour).UTC()
	Y2K                     = time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)
	Y2KPlus                 = time.Date(2000, 1, 11, 10, 1, 2, 0, time.UTC)
	FiveYearsAgo            = time.Now().Add(-5 * 365 * 24 * time.Hour).UTC()

	OneHundredHoursAgoNullMysqlDateTime  = models.NullMysqlDateTimeFromTime(OneHundredHoursAgo)
	TwentyThreeHoursFromNowMysqlDateTime = models.NullMysqlDateTimeFromTime(TwentyThreeHoursFromNow)
	SixDaysFromNowMysqlDateTime          = models.NullMysqlDateTimeFromTime(SixDaysFromNow)
	Y2KMysqlDateTime                     = models.NullMysqlDateTimeFromTime(Y2K)
	Y2KPlusMysqlDateTime                 = models.NullMysqlDateTimeFromTime(Y2KPlus)
)

var (
	MonalisaValidSATExpiresAt        = time.Date(2021, 1, 1, 8, 0, 0, 0, time.UTC)
	MonalisaValidSAT2ExpiresAt       = time.Now().Add(14 * 24 * time.Hour).Truncate(time.Second).UTC() // in 2 weeks
	MonalisaValidSessionSATExpiresAt = time.Now().Add(14 * 24 * time.Hour).Truncate(time.Second).UTC() // in 2 week

	MonalisaValidSAT      = NewTestSignedAuthToken(MonalisaUser, nil, "test", MonalisaValidSATExpiresAt, map[string]interface{}{"key1": "val1", "key2": 42})
	MonalisaValidSAT2     = NewTestSignedAuthToken(MonalisaUser, nil, "test", MonalisaValidSAT2ExpiresAt, map[string]interface{}{"key1": "val1", "key2": 42})
	MonalisaExpiredSAT    = NewTestSignedAuthToken(MonalisaUser, nil, "expired", FiveYearsAgo, map[string]interface{}{"app_id": 123, "page": "/foo/bar"})
	MonalisaMismatchedSAT = NewTestSignedAuthToken(MonalisaUser, nil, "MyScope", time.Now().Add(-1*time.Minute).UTC(), map[string]interface{}{"app_id": 123, "page": "/foo/bar"}, OverrideTokenSecret("7f6a07a3feec42d36a04c48d9f0cec64b6515e84"))
	TrollSuspendedSAT     = NewTestSignedAuthToken(TrollUser, nil, "MyScope", MonalisaValidSAT2ExpiresAt, map[string]interface{}{"app_id": 123, "page": "/foo/bar"})
	UnknownUserSAT        = NewTestSignedAuthToken(UnknownUser, nil, "MyScope", MonalisaValidSAT2ExpiresAt, map[string]interface{}{"app_id": 123, "page": "/foo/bar"})

	MonalisaValidSessionSAT                  = NewTestSignedAuthToken(MonalisaUser, MonalisaValidUserSession, "test", MonalisaValidSessionSATExpiresAt, map[string]interface{}{"key1": "session-val1", "key2": 43})
	MonalisaExpiredSessionValidSAT           = NewTestSignedAuthToken(MonalisaUser, MonalisaExpiredUserSession, "MyScope", MonalisaValidSessionSATExpiresAt, map[string]interface{}{"key1": "session-val1", "key2": 43})
	MonalisaHardExpiredSessionValidSAT       = NewTestSignedAuthToken(MonalisaUser, MonalisaHardExpiredUserSession, "MyScope", MonalisaValidSessionSATExpiresAt, map[string]interface{}{"key1": "session-val1", "key2": 43})
	MonalisaRevokedSessionValidSAT           = NewTestSignedAuthToken(MonalisaUser, MonalisaRevokedUserSession, "MyScope", MonalisaValidSessionSATExpiresAt, map[string]interface{}{"key1": "session-val1", "key2": 43})
	MonalisaUnknownSessionValidSAT           = NewTestSignedAuthToken(MonalisaUser, MonalisaUnknownUserSession, "MyScope", MonalisaValidSessionSATExpiresAt, map[string]interface{}{"key1": "session-val1", "key2": 43})
	MonalisaExpiredAndRevokedSessionValidSAT = NewTestSignedAuthToken(MonalisaUser, MonalisaExpiredAndRevokedUserSession, "MyScope", MonalisaValidSessionSATExpiresAt, map[string]interface{}{"key1": "session-val1", "key2": 43})
	ImpersonatedSessionValidSAT              = NewTestSignedAuthToken(RandomUser, ImpersonatedUserSession, "MyScope", MonalisaValidSessionSATExpiresAt, map[string]interface{}{"app_ids": 2, "page": "/foo/bar"})

	// NOTE(chriskirkland): we have to keep this hard-coded because authnd cannot generate this SAT, but Dotcom can
	// GitHub::Authentication::SignedAuthToken.generate(user: mona, scope: "test", expires: 84.years.from_now, data: ["i", 123])
	// token_secret = '567f2e98993f8d05bf6c1c3a374d16766a0d0fa9'
	// approximate expiration: Mon, 20 Apr 2105 17:26:41.115338000 UTC +00:00
	MonalisaValidSATWithArrayData = "AAAAAAUJKR2Y2BQJ6PVKR2P6RNNOREVBNF5Q"
)

const (
	// fake replicator values
	FakePrimaryKey                = 111
	FakePartition                 = 1234
	FakeReplicationDBName         = "github_test"
	FakeReplicationTopicName      = "some-topic-name"
	FakeReplicationEncryptedBytes = "some-bytes"
	FakeBinlogPosition            = "mysql-bin.000009:6569065"
	FakeReplicationEncryptionIV   = "jyv8/oz/aCx4sSL3rIvpmw=="
	FakeGTID                      = "some_server:1234"
)

type satCreateArgs struct {
	tokenSecret string
}

type SignedAuthTokenOverride func(*satCreateArgs)

func OverrideTokenSecret(tokenSecret string) SignedAuthTokenOverride {
	return func(args *satCreateArgs) {
		args.tokenSecret = tokenSecret
	}
}

func NewTestSignedAuthToken(user *models.User, session *models.UserSession, scope string, expiresAt time.Time, data map[string]interface{}, overrides ...SignedAuthTokenOverride) string {
	if user == nil {
		panic("user cannot be nil")
	}
	if !user.TokenSecret.Valid {
		panic("user.TokenSecret must be valid")
	}
	args := satCreateArgs{
		tokenSecret: user.TokenSecret.String,
	}
	for _, o := range overrides {
		o(&args)
	}

	if session != nil {
		token, err := sat.GenerateV3SessionToken(session.ID, scope, args.tokenSecret, expiresAt, data)
		if err != nil {
			panic(fmt.Sprintf("unexpected error: %v", err))
		}
		return token
	}

	token, err := sat.GenerateV3Token(user.ID, scope, args.tokenSecret, expiresAt, data)
	if err != nil {
		panic(fmt.Sprintf("unexpected error: %v", err))
	}
	return token
}

func MustCreatePayloadBytes(t *testing.T, data interface{}) []byte {
	payload := map[string]interface{}{
		"data": data,
	}
	bytes, err := json.Marshal(payload)
	require.NoError(t, err)
	return bytes
}

func hashToken(token string) []byte {
	hash := sha256.New()
	hash.Write([]byte(token)) //nolint: errcheck
	return hash.Sum(nil)
}

func IsProximaMode() bool {
	return os.Getenv("PROXIMA_MODE") == "1"
}
