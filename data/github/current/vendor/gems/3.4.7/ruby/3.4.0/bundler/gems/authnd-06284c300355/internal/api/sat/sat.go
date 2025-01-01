package sat

import (
	"crypto/hmac"
	"hash"
	"time"

	"github.com/pkg/errors"
)

type LookupType uint
type SatVersion uint

const (
	// Unknown represents an unknown or other SAT version (it is the 'zero value' for SatVersion)
	VersionUnknown SatVersion = 0

	// We don't support v1 or v2 yet.

	Version3 SatVersion = 3
)

const (
	LookupByUserID LookupType = iota
	LookupBySessionID
)

// ErrorUnsupportedTokenVersion is returned if the token format is not recognized as a supported version.
var ErrorUnsupportedTokenVersion = errors.New("unsupported token version")

// ErrorInvalidToken is returned if the token format is recognized as a supported version but is malformed.
var ErrorInvalidToken = errors.New("token format invalid")

type TokenUserInfo struct {
	UserID      int64
	UserLogin   string
	TokenSecret string
	IsSuspended bool
}

// A UserLookup takes an ID value and the lookup kind (LookupByUserID or LookupBySessionID)
// and returns a TokenUserInfo that can be used to validate tokens.
type UserLookup func(id int64, lookup LookupType) (TokenUserInfo, error)

type SignedAuthToken struct {
	Version   SatVersion
	UserID    int64
	UserLogin string
	SessionID int64
	Expires   time.Time
	Scope     string
	Data      map[string]interface{}
}

// VerifyToken parses the provided token, validates the signature (using the secret provided by the user lookup function) and returns the data contained in the token.
// It does **not** check expiry (though the expiry date is included in the returned value).
func VerifyToken(sat, scope string, userLookup UserLookup) (SignedAuthToken, error) {
	var err error
	var token SignedAuthToken

	// We check each format in priority order.
	// First we check their regex and if it doesn't match move on.
	// Then we attempt to validate the token with that version.
	// It's possible for multiple version regexes to match a token, so even when we match a regex, we fallback to other versions if it fails to validate.

	if v3Regex.MatchString(sat) {
		token, err = verifyV3Token(sat, scope, userLookup)
		if err == nil {
			return token, nil
		}
	}

	if v3SessionRegex.MatchString(sat) {
		token, err = verifyV3SessionToken(sat, scope, userLookup)
		if err == nil {
			return token, nil
		}
	}

	if err != nil {
		return SignedAuthToken{}, err
	}

	// No token validators matched
	return SignedAuthToken{}, errors.WithStack(ErrorUnsupportedTokenVersion)
}

func generateDigest(hash func() hash.Hash, secret, payload []byte) []byte {
	hmacer := hmac.New(hash, secret)
	hmacer.Write(payload)
	return hmacer.Sum(nil)
}
