package bodyhmac

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"regexp"
)

// headerRegex strictly matches an HMAC created via sha256 and base64-encoded.
var headerRegex = regexp.MustCompile(`^([A-Za-z0-9+/]{43}=)$`)

// ErrMalformedHeader is returned when the header is not a valid HMAC.
var ErrMalformedHeader = errors.New("malformed HMAC header")

// ErrMismatch is returned when the computed HMAC does not match the value in the header.
var ErrMismatch = errors.New("computed body HMAC does not match value in header")

// VerifyHeader verifies that the body HMAC matches the value in the header, using a shared key.
//
// header is the received header value to validate; must be the HMAC of the body, base64-encoded
// body is the POST request body
// key must be the shared key used in the call to CreateHeader.
func VerifyHeader(header string, body, key []byte) error {
	if !headerRegex.MatchString(header) {
		return ErrMalformedHeader
	}

	computedHMAC, err := createHMAC(body, key)
	if err != nil {
		return err
	}

	headerHMAC, err := base64.StdEncoding.Strict().DecodeString(header)
	if err != nil {
		return fmt.Errorf("unable to decode header HMAC: %w", err)
	}

	// hmac.Equal compares for equality without leaking timing information.
	if !hmac.Equal(computedHMAC, headerHMAC) {
		return ErrMismatch
	}

	return nil
}

// CreateHeader creates a base64-encoded HMAC of a POST body, using a shared key.
func CreateHeader(body, key []byte) (string, error) {
	newHMAC, err := createHMAC(body, key)
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.Strict().EncodeToString(newHMAC), nil
}

// createHMAC creates an HMAC from a value and a key.
func createHMAC(value, key []byte) ([]byte, error) {
	mac := hmac.New(sha256.New, key)
	_, err := mac.Write(value)
	if err != nil {
		return []byte{}, fmt.Errorf("error creating HMAC: %w", err)
	}
	return mac.Sum(nil), nil
}
