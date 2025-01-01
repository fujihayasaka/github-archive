package sat

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"math"
	"regexp"
	"strings"
	"time"

	v0 "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/pkg/errors"
	"github.com/vmihailenco/msgpack/v5"
)

// From https://github.com/github/github/blob/0c9e9e12a46b3195ca1ad24977c11b6de6fd6592/lib/github/authentication/signed_auth_token/version3.rb#L16
var v3Regex = regexp.MustCompile(`\A(?i)[ABCDEFGHIJKLMNOPQRSTUVWXYZ234567]{29,}\z`)

// From https://github.com/github/github/blob/0c9e9e12a46b3195ca1ad24977c11b6de6fd6592/lib/github/authentication/signed_auth_token/session.rb#L22
var v3SessionRegex = regexp.MustCompile(`\A(?i)GHSAT0[ABCDEFGHIJKLMNOPQRSTUVWXYZ234567]{36,}\z`)

var base32Encoding = base32.StdEncoding.WithPadding(base32.NoPadding)

// From https://github.com/github/github/blob/b9203183ad305b887d58abadd5e0107dbc4b7c7e/lib/github/authentication/signed_auth_token/session.rb#L17
var versionIdentifier = "GHSAT0"

// As per the Ruby SAT implementation, these tokens are explicitly not Y2106 compatible
var maxTime = time.Unix(int64(math.MaxInt32), 0)
var ExpiresTooLate = errors.New("Provided expiry time is too far in the future")
var NoTimesAllowed = errors.New("Payloads may not contain time values; use integral seconds instead")

// Generate an SSAT (version 3) for the provided user, scope, and secret.
func GenerateV3Token(userID int64, scope, userSecret string, expires time.Time, data map[string]interface{}) (string, error) {
	scopedSecret := fmt.Sprintf("%s | %s", userSecret, scope)
	return generateV3Token(userID, 0, scope, scopedSecret, expires, data, "")
}

// Generate an SSAT (version 3) for the provided session, scope, and secret.
func GenerateV3SessionToken(sessionID int64, scope, userSecret string, expires time.Time, data map[string]interface{}) (string, error) {
	scopedSecret := fmt.Sprintf("%s | %d | %s", userSecret, sessionID, scope)
	return generateV3Token(0, sessionID, scope, scopedSecret, expires, data, versionIdentifier)
}

// Generate an SSAT (version 3) for the provided user, scope, and secret.
func generateV3Token(userID, sessionID int64, scope, scopedSecret string, expires time.Time, data map[string]interface{}, prefix string) (string, error) {
	// Ensure Y2106-incompatibility
	// From https://github.com/github/github/blob/b9203183ad305b887d58abadd5e0107dbc4b7c7e/lib/github/authentication/signed_auth_token/version3.rb#L32
	if expires.After(maxTime) {
		return "", ExpiresTooLate
	}

	var packedData []byte
	var err error
	if data != nil {
		err = validatePayload(data)
		if err != nil {
			return "", err
		}

		var buf bytes.Buffer
		// The Ruby implementation does not specify this axiom, but it is required
		// in languages like Go with undefined iteration order over mapping types.
		var enc *msgpack.Encoder = msgpack.NewEncoder(&buf).SetSortMapKeys(true)
		err := enc.Encode(data)
		if err != nil {
			return "", err
		}
		packedData = buf.Bytes()
	}
	// Payload:
	//   expiry, as Unix epoch time, in big-endian uint32
	//   user-provided data, compressed with MsgPack, as binary string
	// From https://github.com/github/github/blob/b9203183ad305b887d58abadd5e0107dbc4b7c7e/lib/github/authentication/signed_auth_token/version3.rb#L5
	var payload bytes.Buffer
	err = binary.Write(&payload, binary.BigEndian, uint32(expires.Unix()))
	if err != nil {
		return "", err
	}
	err = binary.Write(&payload, binary.BigEndian, packedData)
	if err != nil {
		return "", err
	}

	// Secret and scope are joined together
	// from https://github.com/github/github/blob/b9203183ad305b887d58abadd5e0107dbc4b7c7e/lib/github/authentication/signed_auth_token/version3.rb#L100
	hmac := generateDigest(sha256.New, []byte(scopedSecret), payload.Bytes())
	// Secret contents:
	//   ID, as uint32 for user ID or uint64 for sessionID
	//   first ten bytes of HMAC generated from scoped secret
	//   payload (see above)
	// from https://github.com/github/github/blob/b9203183ad305b887d58abadd5e0107dbc4b7c7e/lib/github/authentication/signed_auth_token/version3.rb#L39
	var packed bytes.Buffer
	if userID != 0 {
		err = binary.Write(&packed, binary.BigEndian, uint32(userID))
	} else if sessionID != 0 {
		err = binary.Write(&packed, binary.BigEndian, uint64(sessionID))
	} else {
		err = errors.New("neither user ID nor sessionID provided")
	}
	if err != nil {
		return "", err
	}

	err = binary.Write(&packed, binary.BigEndian, hmac[0:10])
	if err != nil {
		return "", err
	}
	err = binary.Write(&packed, binary.BigEndian, payload.Bytes())
	if err != nil {
		return "", err
	}

	return prefix + base32Encoding.EncodeToString(packed.Bytes()), nil
}

func validatePayload(data map[string]interface{}) error {
	for _, val := range data {
		_, ok := val.(time.Time)
		if ok {
			return NoTimesAllowed
		}
	}
	return nil
}

func verifyV3Token(sat, scope string, userLookup UserLookup) (SignedAuthToken, error) {
	// v3 SATs are case-insensitive, but need to be upper-cased before being decoded
	sat = strings.ToUpper(sat)

	// Decode the token to binary
	tokenBytes, err := base32Encoding.DecodeString(sat)
	if err != nil {
		return SignedAuthToken{}, errors.WithStack(ErrorInvalidToken)
	}

	// Token format is:
	// big endian uint32 | 10 byte binary hmac | N byte payload
	// where N is the rest of the payload.
	// Source: https://github.com/github/github/blob/0c9e9e12a46b3195ca1ad24977c11b6de6fd6592/lib/github/authentication/signed_auth_token/version3.rb#L7

	if len(tokenBytes) <= 14 {
		return SignedAuthToken{}, errors.WithStack(ErrorInvalidToken)
	}
	id := int64(binary.BigEndian.Uint32(tokenBytes[0:4]))
	digest := tokenBytes[4:14]
	payload := tokenBytes[14:]

	// Look up the secret
	userInfo, err := userLookup(id, LookupByUserID)
	if err != nil {
		return SignedAuthToken{}, err
	}

	// Create a scoped secret
	secret := fmt.Sprintf("%s | %s", userInfo.TokenSecret, scope)
	if !validateV3Digest(secret, payload, digest) {
		// there is a mismatch in either the token_secret or scope. the monolith returns 'bad_scope' here, but we cannot rule
		// out a race condition on the token_secret held by the user or sessions due to replication lag. so we need return a
		// more generic error.
		// https://github.com/github/github/blob/0c9e9e12a46b3195ca1ad24977c11b6de6fd6592/lib/github/authentication/signed_auth_token/session.rb#L80-L82
		return SignedAuthToken{}, errors.WithStack(ErrorInvalidToken)
	}

	// check whether the user is suspended after verifying the scope to match the behavior in dotcom
	// https://github.com/github/github/blob/c7fa1308c474282285322199243c749384ab28e1/lib/github/authentication/signed_auth_token/version3.rb#L59-L68
	if userInfo.IsSuspended {
		return SignedAuthToken{}, &models.AuthenticationFailure{Code: v0.AuthenticateResponse_RESULT_FAILED_SUSPENDED}
	}

	expiry, data, err := parseV3Payload(payload)
	if err != nil {
		return SignedAuthToken{}, err
	}

	return SignedAuthToken{
		Version:   Version3,
		UserID:    id,
		UserLogin: userInfo.UserLogin,
		Expires:   expiry,
		Scope:     scope,
		Data:      data,
	}, nil
}

func verifyV3SessionToken(sat, scope string, userLookup UserLookup) (SignedAuthToken, error) {
	// v3 SATs are case-insensitive, but need to be upper-cased before being decoded
	sat = strings.ToUpper(sat[6:])

	// Decode the token to binary
	tokenBytes, err := base32Encoding.DecodeString(sat)
	if err != nil {
		return SignedAuthToken{}, errors.WithStack(ErrorInvalidToken)
	}

	// Token format is:
	// big endian uint64 | 10 byte binary hmac | N byte payload
	// where N is the rest of the payload.
	// https://github.com/github/github/blob/0c9e9e12a46b3195ca1ad24977c11b6de6fd6592/lib/github/authentication/signed_auth_token/session.rb#L7
	if len(tokenBytes) <= 18 {
		return SignedAuthToken{}, errors.WithStack(ErrorInvalidToken)
	}
	id := int64(binary.BigEndian.Uint64(tokenBytes[0:8]))
	digest := tokenBytes[8:18]
	payload := tokenBytes[18:]

	// Look up the secret
	userInfo, err := userLookup(id, LookupBySessionID)
	if err != nil {
		return SignedAuthToken{}, err
	}

	// Create a scoped secret
	secret := fmt.Sprintf("%s | %d | %s", userInfo.TokenSecret, id, scope)
	if !validateV3Digest(secret, payload, digest) {
		// there is a mismatch in either the token_secret or scope. the monolith returns 'bad_scope' here, but we cannot rule
		// out a race condition on the token_secret held by the user or sessions due to replication lag. so we need return a
		// more generic error.
		// https://github.com/github/github/blob/0c9e9e12a46b3195ca1ad24977c11b6de6fd6592/lib/github/authentication/signed_auth_token/session.rb#L80-L82
		return SignedAuthToken{}, errors.WithStack(ErrorInvalidToken)
	}

	// check whether the user is suspended after verifying the scope to match the behavior in dotcom
	// https://github.com/github/github/blob/c7fa1308c474282285322199243c749384ab28e1/lib/github/authentication/signed_auth_token/version3.rb#L59-L68
	if userInfo.IsSuspended {
		return SignedAuthToken{}, &models.AuthenticationFailure{Code: v0.AuthenticateResponse_RESULT_FAILED_SUSPENDED}
	}

	expiry, data, err := parseV3Payload(payload)
	if err != nil {
		return SignedAuthToken{}, err
	}

	return SignedAuthToken{
		Version:   Version3,
		UserID:    userInfo.UserID,
		UserLogin: userInfo.UserLogin,
		SessionID: id,
		Expires:   expiry,
		Scope:     scope,
		Data:      data,
	}, nil
}

func parseV3Payload(payload []byte) (time.Time, map[string]interface{}, error) {
	// Payload format is:
	// big endian uint32 | N byte payload
	// where N is the rest of the payload.
	// Source: https://github.com/github/github/blob/0c9e9e12a46b3195ca1ad24977c11b6de6fd6592/lib/github/authentication/signed_auth_token/version3.rb#L4
	expiry := time.Unix(int64(binary.BigEndian.Uint32(payload[0:4])), 0).UTC()

	data, err := unpackMsgpack(payload[4:])
	if err != nil {
		return time.Time{}, nil, err
	}
	return expiry, data, nil
}

func unpackMsgpack(payload []byte) (map[string]interface{}, error) {
	// The data value is a MessagePack map.
	if len(payload) > 0 {
		var data interface{}
		if err := msgpack.Unmarshal(payload, &data); err != nil {
			return map[string]interface{}{}, errors.New("token data invalid")
		}

		if v, ok := data.(map[string]interface{}); ok {
			return v, nil
		}

		// we are aware that "data" can be an array
		// for now, we are specifically returning "not supported" so that the experiment in dotcom can ignore
		// https://github.com/github/authnd/issues/887
		if _, ok := data.([]interface{}); ok {
			return nil, &models.AuthenticationFailure{Code: v0.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
		}

		return map[string]interface{}{}, errors.New("token data invalid")
	}

	// Just return an empty map.
	return map[string]interface{}{}, nil
}

func validateV3Digest(secret string, payload, expectedDigest []byte) bool {
	// Generate the expected digest.
	// We only use the first 10 bytes of the digest.
	// Source: https://github.com/github/github/blob/0c9e9e12a46b3195ca1ad24977c11b6de6fd6592/lib/github/authentication/signed_auth_token/session.rb#L128
	actualDigest := generateDigest(sha256.New, []byte(secret), payload)
	actualDigest = actualDigest[0:10]
	return hmac.Equal(actualDigest, expectedDigest)
}
