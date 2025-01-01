package mobiledeviceauth

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"math/big"
	"strconv"
	"time"

	"github.com/github/authnd/internal/common"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
)

// GenerateChallengeNumber generates the challenge number that will be sent to the user.
// returns number 10-99 inclusive or an error
func GenerateChallengeNumber() (uint64, error) {
	randomNumber, err := rand.Int(rand.Reader, big.NewInt(90)) // returns 0, 1, ..., 88, or 89
	if err != nil {
		return 0, errors.WithStack(err)
	}
	randomTwoDigitNumber := randomNumber.Uint64() + 10 // returns 10, 11, ..., 98, or 99
	return randomTwoDigitNumber, nil
}

// GeneratePayload generates a random payload that is sent to the user to be signed
// to verify they are the owner of the device.
// The total length of the payload is 40 bytes.
// The format of the payload is: <unix timestamp><random bytes>
func GeneratePayload(t time.Time) ([]byte, error) {
	// encode the time as unix time
	encodedUnixTime := make([]byte, 8)
	binary.BigEndian.PutUint64(encodedUnixTime, uint64(t.Unix()))

	// generate random bytes
	randomBytes, err := generateRandomBytes(32)
	if err != nil {
		return nil, err
	}

	return append(encodedUnixTime, randomBytes...), nil
}

// CreateExpectedApproveMessageHash creates the expected message hash (using a sha256 digest) to use when verifying a signature
// provided by a mobile device for approving a mobile auth request.
func CreateExpectedApproveMessageHash(version uint64, payload []byte, challengeNumber int64) []byte {
	buf := bytes.Buffer{}
	buf.WriteString(strconv.FormatUint(version, 10))
	buf.WriteString("|")
	buf.Write(payload)
	buf.WriteString("|")
	buf.WriteString(strconv.FormatInt(challengeNumber, 10))
	messageHash := sha256.Sum256(buf.Bytes())
	return messageHash[:]
}

// CreateExpectedApproveMessageWithoutChallengeHash creates the expected message hash (using a sha256 digest) to use when verifying a signature
// provided by a mobile device for approving a mobile auth request when the challenge number is not required.
func CreateExpectedApproveMessageWithoutChallengeHash(version uint64, payload []byte) []byte {
	buf := bytes.Buffer{}
	buf.WriteString(strconv.FormatUint(version, 10))
	buf.WriteString("|")
	buf.Write(payload)
	messageHash := sha256.Sum256(buf.Bytes())
	return messageHash[:]
}

// GetRequestTypeValue takes in a string and returns the corresponding enum value
// If the requestType is provided but is not supported, we throw an error
// If no value is provided, we default the requestTypeValue to 0 (2fa_login)
func GetRequestTypeValue(requestType string) (int, error) {
	switch requestType {
	case "", common.MobileRequestTypeTwoFactorLoginName:
		return common.MobileRequestTypeTwoFactorLogin, nil
	case common.MobileRequestTypeDeviceVerificationName:
		return common.MobileRequestTypeDeviceVerification, nil
	case common.MobileRequestTypeTwoFactorPasswordResetName:
		return common.MobileRequestTypeTwoFactorPasswordReset, nil
	case common.MobileRequestTypeTwoFactorSudoChallengeName:
		return common.MobileRequestTypeTwoFactorSudoChallenge, nil
	default:
		return -1, twirp.InvalidArgumentError("Type", fmt.Sprintf("Invalid request type %s", requestType))
	}
}

// GetRequestLifetime takes in the requestType enum value and returns the corresponding lifespan
func GetRequestLifetime(requestType int) time.Duration {
	switch requestType {
	case common.MobileRequestTypeDeviceVerification:
		return time.Minute * 2
	default:
		return time.Minute
	}
}

// GetRequestTypeValue takes in a int and returns the corresponding string value
func GetRequestTypeName(requestTypeValue int) string {
	var requestName string
	switch requestTypeValue {
	case common.MobileRequestTypeTwoFactorLogin:
		requestName = common.MobileRequestTypeTwoFactorLoginName
	case common.MobileRequestTypeDeviceVerification:
		requestName = common.MobileRequestTypeDeviceVerificationName
	case common.MobileRequestTypeTwoFactorPasswordReset:
		requestName = common.MobileRequestTypeTwoFactorPasswordResetName
	case common.MobileRequestTypeTwoFactorSudoChallenge:
		requestName = common.MobileRequestTypeTwoFactorSudoChallengeName
	}
	return requestName
}

// generateRandomBytes returns securely generated random bytes.
// It will return an error if the system's secure random
// number generator fails to function correctly, in which
// case the caller should not continue.
func generateRandomBytes(n int) ([]byte, error) {
	b := make([]byte, n)
	_, err := rand.Read(b)
	// Note that err == nil only if we read len(b) bytes.
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return b, nil
}
