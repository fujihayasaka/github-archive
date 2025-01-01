package sat

import (
	"fmt"
	"math"
	"strings"
	"testing"
	"time"

	v0 "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

const (
	monalisaUserID           int64  = 2
	monalisaSessionID        int64  = 1
	monalisaTokenSecret      string = "382a889fa24953bc9aa44e17bcfd70a024f07ec1"
	suspendedUserID          int64  = 12
	suspendedUserSessionID   int64  = 23459
	suspendedUserTokenSecret string = "17c0cdba82dd9b484a619ce622d5aa35fcf5dc82"
	testScope                string = "test"
	monaLogin                string = "mona"
	suspendedLogin           string = "suspended"

	// Test SATs generated in the rails console on github/github, with the following script:
	//
	//   user = that 'monalisa'
	//   puts "Secret: #{user.token_secret}" # see the token secret above
	//   expiry = Time.new(2021, 1, 1, 8, 0, 0, "UTC").utc
	//   data = { key1: "val1", key2: 42 } # if generating the "with data" variant
	//   scope = "test"
	//   GitHub::Authentication::SignedAuthToken::generate(user: user, scope: scope, data: data, expires: expiry)
	//
	monalisaV3SatNoData   string = "AAAAAAUXXQUR64JZK5VDHU2753LIA"
	monalisaV3SatWithData string = "AAAAAAUWPWHTC6HFUZGYXLK753LIBAVENNSXSMNEOZQWYMNENNSXSMRK"
	// data = ["i", 123]
	monalisaV3SatWithArrayData string = "AAAAAAWLEO4JNPSBSRGPTJC753LIBEVBNF5Q"

	// Test SATs generated in the rails console on github/github, with the following script:
	//
	//   user = that 'monalisa'
	//   puts "Secret: #{user.token_secret}" # see the token secret above
	//   session = user.sessions[0] # make sure 'session' is not nil!
	//   expiry = Time.new(2021, 1, 1, 8, 0, 0, "UTC").utc
	//   data = { key1: "val1", key2: 42 } # if generating the "with data" variant
	//   scope = "test"
	//   GitHub::Authentication::SignedAuthToken::generate(session: session, scope: scope, data: data, expiry: expiry)
	//
	monalisaV3SessionSatNoData   string = "GHSAT0AAAAAAAAAAAACOXRGV7FUQ6D2FE6YX7O22AA"
	monalisaV3SessionSatWithData string = "GHSAT0AAAAAAAAAAAADZ7IKOV7WQJGASHR6X7O22AIFJDLMV4TDJDWMFWDDJDLMV4TEKQ"

	// Test SATs generated in the rails console on github/github, with the following script:
	//
	//   user = yon('sus')  # new account created on github.localhost
	//   puts "Secret: #{user.token_secret}" # see the token secret above
	//   expiry = Time.new(2021, 1, 1, 8, 0, 0, "UTC").utc
	//   data = { key1: "val1", key2: 42 } # if generating the "with data" variant
	//   scope = "test"
	//   GitHub::Authentication::SignedAuthToken::generate(user: user, scope: scope, data: data, expires: expiry)
	//
	suspendedV3Sat string = "AAAAADCW5NKVAPRMOX6HPLS753LIBAVENNSXSMNEOZQWYMNENNSXSMRK"
	// Test SATs generated in the rails console on github/github, with the following script:
	//
	//   user = yon('sus')  # new account created on github.localhost
	//   session = user.sessions[0]
	//   puts "Secret: #{user.token_secret}" # see the token secret above
	//   expiry = Time.new(2021, 1, 1, 8, 0, 0, "UTC").utc
	//   data = { key1: "val1", key2: 42 } # if generating the "with data" variant
	//   scope = "test"
	//   GitHub::Authentication::SignedAuthToken::generate(session: session, scope: scope, data: data, expires: expiry)
	//
	suspendedV3SessionSat string = "GHSAT0AAAAAAAAABN2GF5TMHA5GMM3WVO7QX7O22AIFJDLMV4TDJDWMFWDDJDLMV4TEKQ"
)

var (
	testExpiry time.Time              = time.Date(2021, time.January, 1, 8, 0, 0, 0, time.UTC)
	testData   map[string]interface{} = map[string]interface{}{
		"key1": "val1",
		"key2": 42,
	}
)

func lookupTestSecret(id int64, lookup LookupType) (TokenUserInfo, error) {
	if lookup == LookupByUserID {
		switch id {
		case monalisaUserID:
			return TokenUserInfo{id, monaLogin, monalisaTokenSecret, false}, nil
		case suspendedUserID:
			return TokenUserInfo{id, suspendedLogin, suspendedUserTokenSecret, true}, nil
		default:
			return TokenUserInfo{}, errors.Errorf("unknown user ID '%d'", id)
		}
	} else if lookup == LookupBySessionID {
		switch id {
		case monalisaSessionID:
			return TokenUserInfo{monalisaUserID, monaLogin, monalisaTokenSecret, false}, nil
		case suspendedUserSessionID:
			return TokenUserInfo{suspendedUserID, suspendedLogin, suspendedUserTokenSecret, true}, nil
		default:
			return TokenUserInfo{}, errors.Errorf("unknown session ID '%d'", id)
		}
	}
	return TokenUserInfo{}, errors.Errorf("unknown lookup type '%d'", lookup)
}

func TestV3TokenVerifyNoData(t *testing.T) {
	token, err := VerifyToken(monalisaV3SatNoData, testScope, lookupTestSecret)
	require.NoError(t, err)

	require.Equal(t, Version3, token.Version)
	require.Equal(t, monalisaUserID, token.UserID)
	require.Equal(t, monaLogin, token.UserLogin)
	require.Equal(t, int64(0), token.SessionID)
	require.Equal(t, testExpiry, token.Expires)
	require.Equal(t, testScope, token.Scope)
	require.Empty(t, token.Data)
}

func TestV3TokenGenerateNoData(t *testing.T) {
	tok, err := GenerateV3Token(monalisaUserID, testScope, monalisaTokenSecret, testExpiry, nil)
	require.NoError(t, err)
	require.Equal(t, monalisaV3SatNoData, tok)
}

func TestV3TokenVerifyLowerCaseNoData(t *testing.T) {
	sat := strings.ToLower(monalisaV3SatNoData)
	token, err := VerifyToken(sat, testScope, lookupTestSecret)
	require.NoError(t, err)

	require.Equal(t, Version3, token.Version)
	require.Equal(t, monalisaUserID, token.UserID)
	require.Equal(t, monaLogin, token.UserLogin)
	require.Equal(t, int64(0), token.SessionID)
	require.Equal(t, testExpiry, token.Expires)
	require.Equal(t, testScope, token.Scope)
	require.Empty(t, token.Data)
}

func TestV3TokenVerifyWithData(t *testing.T) {
	token, err := VerifyToken(monalisaV3SatWithData, testScope, lookupTestSecret)
	require.NoError(t, err)

	require.Equal(t, Version3, token.Version)
	require.Equal(t, monalisaUserID, token.UserID)
	require.Equal(t, monaLogin, token.UserLogin)
	require.Equal(t, int64(0), token.SessionID)
	require.Equal(t, testExpiry, token.Expires)
	require.Equal(t, testScope, token.Scope)
	require.Equal(t, 2, len(token.Data))
	require.Equal(t, "val1", token.Data["key1"])
	require.Equal(t, int8(42), token.Data["key2"])
}

func TestV3TokenGenerateWithData(t *testing.T) {
	tok, err := GenerateV3Token(monalisaUserID, testScope, monalisaTokenSecret, testExpiry, testData)
	require.NoError(t, err)
	require.Equal(t, monalisaV3SatWithData, tok)
}

func TestV3TokenVerifyWithArrayData(t *testing.T) {
	_, err := VerifyToken(monalisaV3SatWithArrayData, testScope, lookupTestSecret)
	expectedErr := &models.AuthenticationFailure{Code: v0.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
	require.Error(t, err)
	require.EqualError(t, err, expectedErr.Error())
}

func TestV3SessionTokenVerifyLowerCaseNoData(t *testing.T) {
	sat := strings.ToLower(monalisaV3SessionSatNoData)
	token, err := VerifyToken(sat, testScope, lookupTestSecret)
	require.NoError(t, err)

	require.Equal(t, Version3, token.Version)
	require.Equal(t, monalisaUserID, token.UserID)
	require.Equal(t, monaLogin, token.UserLogin)
	require.Equal(t, monalisaSessionID, token.SessionID)
	require.Equal(t, testExpiry, token.Expires)
	require.Equal(t, testScope, token.Scope)
	require.Empty(t, token.Data)
}

func TestV3SessionTokenVerifyNoData(t *testing.T) {
	token, err := VerifyToken(monalisaV3SessionSatNoData, testScope, lookupTestSecret)
	require.NoError(t, err)

	require.Equal(t, Version3, token.Version)
	require.Equal(t, monalisaUserID, token.UserID)
	require.Equal(t, monaLogin, token.UserLogin)
	require.Equal(t, monalisaSessionID, token.SessionID)
	require.Equal(t, testExpiry, token.Expires)
	require.Equal(t, testScope, token.Scope)
	require.Empty(t, token.Data)
}

func TestV3SessionTokenGenerateNoData(t *testing.T) {
	sat, err := GenerateV3SessionToken(monalisaSessionID, testScope, monalisaTokenSecret, testExpiry, nil)
	require.NoError(t, err)
	require.Equal(t, monalisaV3SessionSatNoData, sat)
}

func TestV3SessionTokenVerifyWithData(t *testing.T) {
	token, err := VerifyToken(monalisaV3SessionSatWithData, testScope, lookupTestSecret)
	require.NoError(t, err)

	require.Equal(t, Version3, token.Version)
	require.Equal(t, monalisaUserID, token.UserID)
	require.Equal(t, monaLogin, token.UserLogin)
	require.Equal(t, monalisaSessionID, token.SessionID)
	require.Equal(t, testExpiry, token.Expires)
	require.Equal(t, testScope, token.Scope)
	require.Equal(t, 2, len(token.Data))
	require.Equal(t, "val1", token.Data["key1"])
	require.Equal(t, int8(42), token.Data["key2"])
}

func TestV3SessionTokenGenerateWithData(t *testing.T) {
	sat, err := GenerateV3SessionToken(monalisaSessionID, testScope, monalisaTokenSecret, testExpiry, testData)
	require.NoError(t, err)
	require.Equal(t, monalisaV3SessionSatWithData, sat)
}

func TestInvalidTokens(t *testing.T) {
	suspendedUserError := &models.AuthenticationFailure{Code: v0.AuthenticateResponse_RESULT_FAILED_SUSPENDED}

	runInvalidTokenTest(t, "not a valid token", "scope", ErrorUnsupportedTokenVersion)
	runInvalidTokenTest(t, fmt.Sprintf("surrounding %s data", monalisaV3SatNoData), testScope, ErrorUnsupportedTokenVersion)
	runInvalidTokenTest(t, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "scope", "unknown user ID '0'")
	runInvalidTokenTest(t, "AAAAAAUXXQUR64JZK5VDHU2753HIA", "scope", ErrorInvalidToken)
	runInvalidTokenTest(t, monalisaV3SatNoData, "wrong-scope", ErrorInvalidToken)
	runInvalidTokenTest(t, suspendedV3Sat, testScope, suspendedUserError)
	// scope mismatch is checked before user suspension
	runInvalidTokenTest(t, suspendedV3Sat, "wrong-scope", ErrorInvalidToken)
	runInvalidTokenTest(t, fmt.Sprintf("surrounding %s data", monalisaV3SessionSatNoData), testScope, ErrorUnsupportedTokenVersion)
	runInvalidTokenTest(t, "GHSAT0AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "scope", "unknown session ID '0'")
	runInvalidTokenTest(t, "GHSAT0AAAAAAAAAAAADZ7IKOV7WQJGASHR6X7O22AIFJDLMV4TDJDWMFWDDJDLMV4THIJ", "scope", ErrorInvalidToken)
	runInvalidTokenTest(t, monalisaV3SessionSatNoData, "wrong-scope", ErrorInvalidToken)
	runInvalidTokenTest(t, suspendedV3SessionSat, testScope, suspendedUserError)
	// scope mismatch is checked before user suspension
	runInvalidTokenTest(t, suspendedV3SessionSat, "wrong-scope", ErrorInvalidToken)
}

func TestInvalidGenerations(t *testing.T) {
	future := time.Unix(int64(math.MaxUint32)+1, 0)
	_, err := GenerateV3Token(0, "", "", future, nil)
	require.ErrorIs(t, err, ExpiresTooLate)
	_, err = GenerateV3SessionToken(0, "", "", future, nil)
	require.ErrorIs(t, err, ExpiresTooLate)
	_, err = GenerateV3Token(0, "", "", time.Now().Add(time.Hour), map[string]interface{}{"timekey": future})
	require.ErrorIs(t, err, NoTimesAllowed)
}

func runInvalidTokenTest(t *testing.T, sat, scope string, expectedErrorMessageOrObject interface{}) {
	token, err := VerifyToken(sat, scope, lookupTestSecret)
	require.Equal(t, VersionUnknown, token.Version)

	switch expected := expectedErrorMessageOrObject.(type) {
	case error:
		require.ErrorIs(t, err, expected)
	case string:
		require.Error(t, err)
		require.Equal(t, expected, err.Error())
	}
}
