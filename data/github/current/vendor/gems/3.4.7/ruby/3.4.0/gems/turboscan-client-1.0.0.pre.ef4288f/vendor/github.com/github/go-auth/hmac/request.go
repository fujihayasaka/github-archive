// Package hmac provides a way to generate and validate HMACs for GitHub's internal authorization scheme.
package hmac

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// RequestHeader is the name of the HTTP header used to transmit GitHub HMAC signatures.
const RequestHeader = "Request-HMAC"

// OutOfRangeError is returned when the timestamp of a Request HMAC is outside the allowed range.
type OutOfRangeError struct {
	error
}

// ErrBadKey is returned when the key used to validate an HMAC is blank.
var ErrBadKey = errors.New("the key may not be blank")

// ValidationError is returned when the HMAC is cannot be validated with the given key.
type ValidationError struct {
	error
}

// FormatError is returned when the hmac cannot be parsed.
type FormatError struct {
	error
}

// Unwrap returns the underlying error.
func (e FormatError) Unwrap() error {
	return e.error
}

// Clock skew allowed for Request-HMAC timestamp (both before and after). This is called REQUEST_HMAC_INTERVAL in dotcom.
//
// See: https://github.com/github/github/blob/5bd3daadf1fa639882b7fa362b33719feb168fa3/app/api/internal.rb#L10
const allowedSkew = 10 * time.Minute

// RequestHMAC is an internal GitHub convention for service-to-service
// authentication. The value that is used to compute the HMAC is the current
// timestamp, as determined by the sender. It is passed between services with
// the `Request-HMAC` header.
//
// See: https://github.com/github/github/blob/5bd3daadf1fa639882b7fa362b33719feb168fa3/app/api/internal.rb#L100-L141
type RequestHMAC struct {
	timestamp time.Time
	mac       []byte
}

// NewRequestHMAC creates a new Request HMAC for the current time and secret. It will be valid for approximately the next allowedSkew.
func NewRequestHMAC(secret string) *RequestHMAC {
	return New(time.Now(), secret)
}

// New creates a new Request HMAC for the given time and secret.
func New(now time.Time, secret string) *RequestHMAC {
	return &RequestHMAC{timestamp: now, mac: computeHMAC(now, secret)}
}

// ParseRequestHMAC parses a Request HMAC as represented by the `Request-HMAC` header.
// Will return a FormatError if the value cannot be parsed.
// The format is:
//
// <unix timestamp>.<hex encoded bytes>
//
// Parsing the value does not validate it.
func ParseRequestHMAC(value string) (*RequestHMAC, error) {
	components := strings.Split(value, ".")
	if len(components) != 2 {
		return nil, FormatError{fmt.Errorf("HMAC %q not in correct format", truncateString(value))}
	}

	ts, err := strconv.ParseInt(components[0], 10, 64)
	if err != nil {
		return nil, FormatError{fmt.Errorf("%s could not be parsed as timestamp: %w", truncateString(components[0]), err)}
	}

	hexmac := components[1]
	if hexmac == "" {
		return nil, FormatError{fmt.Errorf("HMAC '%s' not in correct format", truncateString(value))}
	}

	mac, err := hex.DecodeString(hexmac)
	if err != nil {
		return nil, FormatError{fmt.Errorf("%s could not be decoded as hex", truncateString(hexmac))}
	}

	return &RequestHMAC{timestamp: time.Unix(ts, 0), mac: mac}, nil
}

func truncateString(s string) string {
	if len(s) > 4 {
		return s[:4] + "..."
	}
	return s
}

// computeHMAC returns a message authentication code as bytes for the given timestamp and key.
func computeHMAC(ts time.Time, key string) []byte {
	mac := hmac.New(sha256.New, []byte(key))

	// There are two places where parameters leak to the heap, strconv.AppendInt
	// and mac.Sum. We can reuse the buffer providing it is large enough for
	// the largest signed integer -- 20 bytes -- and the size of a sha256 -- 32 bytes.
	buf := make([]byte, 0, mac.Size())
	buf = strconv.AppendInt(buf, ts.Unix(), 10)

	//nolint:revive // This never returns an error according to the documentation.
	mac.Write(buf)
	return mac.Sum(buf[:0])
}

// String returns the format for transmission to another service,
// for example as the value of the `Request-HMAC` header.
func (r *RequestHMAC) String() string {
	return fmt.Sprintf("%d.%s", r.timestamp.Unix(), hex.EncodeToString(r.mac))
}

// Validate the Request HMAC with the given key. The HMAC's timestamp must fall within the package's
// default allowedSkew (10 minutes) from time.Now, in addition to the secret matching.
func (r *RequestHMAC) Validate(key string) error {
	return r.ValidateAt(key, time.Now(), allowedSkew)
}

// ValidateAt validates the Request HMAC with the given key. The HMAC's
// timestamp must fall within maxSkew from the given timestamp.
func (r *RequestHMAC) ValidateAt(key string, now time.Time, maxSkew time.Duration) error {
	if err := validateTime(r.timestamp, now, maxSkew); err != nil {
		return err
	}

	if key == "" {
		return ErrBadKey
	}

	expected := computeHMAC(r.timestamp, key)
	if !hmac.Equal(r.mac, expected) {
		return ValidationError{fmt.Errorf("HMAC %q is invalid", r.String())}
	}

	return nil
}

// validateTime returns an OutOfRangeError if the provided timestamp is not within +/- the allowedSkew of the `current` time.
//
// Current time is parameterized to aid testing.
func validateTime(ts, current time.Time, skew time.Duration) error {
	if ts.After(current.Add(skew)) || ts.Before(current.Add(-skew)) {
		return OutOfRangeError{fmt.Errorf("HMAC Timestamp %d is outside the allowed range", ts.Unix())}
	}

	return nil
}
