package ong

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"time"
)

const (
	timestampHeader = "X-ONG-Hmac-Timestamp"
	tokenHeader     = "X-ONG-Hmac-Token"
	usernameHeader  = "X-Okta-Username"
)

// ValidateHMACSignature examines the http request for the signature sent by
// okta network gateway and tests if it matches the expected value
func ValidateHMACSignature(req *http.Request, key string) (string, bool) {
	username := req.Header.Get(usernameHeader)
	timestamp := req.Header.Get(timestampHeader)
	message := fmt.Sprintf("%s|%s|%v",
		username,
		req.URL.EscapedPath(),
		timestamp,
	)

	// if the timestamp is too old, return false
	if !validTimestamp(timestamp, time.Second*10) {
		return "", false
	}

	expectedHex := []byte(req.Header.Get(tokenHeader))
	expectedBytes := make([]byte, hex.DecodedLen(len(expectedHex)))
	_, err := hex.Decode(expectedBytes, expectedHex)
	if err != nil {
		return "", false
	}

	return username, ValidMAC([]byte(message), expectedBytes, []byte(key))
}

// ValidMAC reports whether messageMAC is a valid HMAC tag for message.
// from https://golang.org/pkg/crypto/hmac/
func ValidMAC(message, expectedMAC, key []byte) bool {
	mac := hmac.New(sha256.New, key)
	mac.Write(message)
	messageMAC := mac.Sum(nil)
	return hmac.Equal(messageMAC, expectedMAC)
}

// validTimestamp accepts a timestamp string in RFC3339 format
// and returns true if the timestamp is within the maxAge
func validTimestamp(timestamp string, maxAge time.Duration) bool {
	t, err := time.Parse(time.RFC3339, timestamp)
	if err != nil {
		return false
	}

	return time.Since(t) <= maxAge
}
