package hmac

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Clock skew allowed for Request-HMAC timestamp (both before and after). This is called REQUEST_HMAC_INTERVAL in dotcom.
//
// See: https://github.com/github/github/blob/5bd3daadf1fa639882b7fa362b33719feb168fa3/app/api/internal.rb#L10
const allowedSkew = 10 * time.Minute

// A Request HMAC is an internal GitHub convention for service-to-service
// authentication. The value that is used to compute the HMAC is the current
// timestamp, as determined by the sender. It is passed between services with
// the `Request-HMAC` header.
//
// See: https://github.com/github/github/blob/5bd3daadf1fa639882b7fa362b33719feb168fa3/app/api/internal.rb#L100-L141
type RequestHMAC struct {
	timestamp time.Time
	mac       []byte
}

// Create a new Request HMAC for the current time and secret. It will be valid for approximately the next allowedSkew.
func NewRequestHMAC(secret string) *RequestHMAC {
	return newRequestHMACWithTimestamp(time.Now(), secret)
}

// Create a new Request HMAC for the given time and secret. Useful for testing.
func newRequestHMACWithTimestamp(ts time.Time, secret string) *RequestHMAC {
	return &RequestHMAC{timestamp: ts, mac: computeHMAC(ts, secret)}
}

// ParseRequstHMAC parses a Request HMAC as represented by the `Request-HMAC` header.
//
// The format is:
//
// <unix timestamp>.<hex encoded bytes>
//
// Parsing the value does not validate it.
func ParseRequestHMAC(value string) (*RequestHMAC, error) {
	components := strings.Split(value, ".")
	if len(components) != 2 {
		return nil, fmt.Errorf("HMAC %q not in correct format", value)
	}

	ts, err := strconv.ParseInt(components[0], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("%s could not be parsed as timestamp: %w", components[0], err)
	}

	hexmac := components[1]
	if hexmac == "" {
		return nil, fmt.Errorf("HMAC '%s' not in correct format", value)
	}

	mac, err := hex.DecodeString(hexmac)
	if err != nil {
		return nil, fmt.Errorf("%s could not be decoded as hex", hexmac)
	}

	return &RequestHMAC{timestamp: time.Unix(ts, 0), mac: mac}, nil
}

// computeHMAC returns a message authentication code as bytes for the given timestamp and key.
func computeHMAC(ts time.Time, key string) []byte {
	mac := hmac.New(sha256.New, []byte(key))

	// There are two places where parameters leak to the heap, strconv.AppendInt
	// and mac.Sum. We can reuse the buffer providing it is large enough for the
	// the largest signed integer -- 20 bytes -- and the size of a sha256 -- 32 bytes.
	buf := make([]byte, 0, mac.Size())
	buf = strconv.AppendInt(buf, ts.Unix(), 10)

	// This never returns an error according to the documentation
	mac.Write(buf) // nolint: errcheck
	return mac.Sum(buf[:0])
}

// Represent the Request HMAC as a string for transmission to another service,
// for example as the value of the `Request-HMAC` header.
func (r *RequestHMAC) String() string {
	return fmt.Sprintf("%d.%s", r.timestamp.Unix(), hex.EncodeToString(r.mac))
}

// Validate the Request HMAC with the given key. The HMAC's timestamp must fall
// within the allowedSkew in addition to the secret matching.
func (r *RequestHMAC) Validate(key string) error {
	if err := validateTime(r.timestamp, time.Now()); err != nil {
		return err
	}

	if key == "" {
		return fmt.Errorf("the key may not be blank")
	}

	expected := computeHMAC(r.timestamp, key)
	if !hmac.Equal(r.mac, expected) {
		return fmt.Errorf("HMAC %q is invalid", r.String())
	}

	return nil
}

// validateTime returns an error if the provided timestamp is not within +/- the allowedSkew of the `current` time.
//
// Current time is parameterized to aid testing.
func validateTime(ts, current time.Time) error {
	if ts.After(current.Add(allowedSkew)) || ts.Before(current.Add(-allowedSkew)) {
		return fmt.Errorf("HMAC Timestamp %d is outside the allowed range", ts.Unix())
	}

	return nil
}
