package okta

import (
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func Test_createToken(t *testing.T) {
	// This test uses values from
	// https://github.com/github/okta-network-gateway/blob/2a0f2bb3e627aea1d9ccad2244cea997dc6b2353/spec/okta-network-gateway_spec.rb#L239
	// to make sure our tokens are the same as what we are checking

	key := []byte("kittenskittenskittenskittenskittenskittenskittenskittens")
	uri := "/foo"
	username := "kitteh"
	timestamp := "2018-04-01T12:00:00Z"
	want := "ff2b1da2772a5e6d55702f0e56e35145eccfa458e6db3213011c34ff42680edd"
	got := createToken(key, username, uri, timestamp)
	assert.Equal(t, want, hex.EncodeToString(got))
}

func TestValidateHMAC(t *testing.T) {
	secret := []byte("this is my secret key")
	uri := "/foo/bar?one=two"
	username := "joe"
	ts := time.Now().UTC().Format(time.RFC3339)
	token := hex.EncodeToString(createToken(secret, username, uri, ts))

	t.Run("nil request", func(t *testing.T) {
		err := ValidateHMAC(nil, secret, nil)
		assert.EqualError(t, err, "nil request")
	})

	t.Run("missing username", func(t *testing.T) {
		req := httptest.NewRequest("", uri, nil)
		err := ValidateHMAC(req, secret, nil)
		assert.EqualError(t, err, fmt.Sprintf("missing header %q", usernameHeader))
	})

	t.Run("missing token", func(t *testing.T) {
		req := httptest.NewRequest("", uri, nil)
		req.Header.Set(usernameHeader, username)
		err := ValidateHMAC(req, secret, nil)
		assert.EqualError(t, err, fmt.Sprintf("missing header %q", tokenHeader))
	})

	t.Run("non-hex token", func(t *testing.T) {
		req := httptest.NewRequest("", uri, nil)
		req.Header.Set(usernameHeader, username)
		req.Header.Set(tokenHeader, "thisisnothex")
		err := ValidateHMAC(req, secret, nil)
		assert.EqualError(t, err, "invalid hmac")
	})

	t.Run("missing timestamp", func(t *testing.T) {
		req := httptest.NewRequest("", uri, nil)
		req.Header.Set(usernameHeader, username)
		req.Header.Set(tokenHeader, token)
		err := ValidateHMAC(req, secret, nil)
		assert.EqualError(t, err, fmt.Sprintf("missing header %q", timestampHeader))
	})

	t.Run("invalid timestamp", func(t *testing.T) {
		req := httptest.NewRequest("", uri, nil)
		req.Header.Set(usernameHeader, username)
		req.Header.Set(tokenHeader, token)
		req.Header.Set(timestampHeader, "notatimestamp")
		err := ValidateHMAC(req, secret, nil)
		assert.EqualError(t, err, "invalid timestamp")
	})

	t.Run("invalid token", func(t *testing.T) {
		wrongToken := hex.EncodeToString(createToken([]byte("this is the wrong key"), username, uri, ts))
		req := httptest.NewRequest("", uri, nil)
		req.Header.Set(usernameHeader, username)
		req.Header.Set(tokenHeader, wrongToken)
		req.Header.Set(timestampHeader, ts)
		err := ValidateHMAC(req, secret, nil)
		assert.EqualError(t, err, "invalid hmac")
	})

	t.Run("valid token", func(t *testing.T) {
		req := httptest.NewRequest("", uri, nil)
		req.Header.Set(usernameHeader, username)
		req.Header.Set(tokenHeader, token)
		req.Header.Set(timestampHeader, ts)
		err := ValidateHMAC(req, secret, nil)
		assert.NoError(t, err)
	})
}

func TestMiddleware_ServeHTTP(t *testing.T) {
	secret := []byte("this is my secret key")
	uri := "/foo/bar?one=two"
	username := "joe"
	ts := time.Now().UTC().Format(time.RFC3339)
	token := createToken(secret, username, uri, ts)
	t.Run("no username header", func(t *testing.T) {
		done := make(chan struct{})
		next := http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
			got, ok := GetUsername(req.Context())
			assert.Empty(t, got)
			assert.False(t, ok)
			close(done)
		})
		mw := Middleware(secret, nil, next)
		req := httptest.NewRequest("", uri, nil)
		mw.ServeHTTP(nil, req)
		<-done
	})

	t.Run("invalid hmac", func(t *testing.T) {
		done := make(chan struct{})
		next := http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
			got, ok := GetUsername(req.Context())
			assert.Empty(t, got)
			assert.False(t, ok)
			close(done)
		})
		mw := Middleware(secret, nil, next)
		req := httptest.NewRequest("", uri, nil)
		req.Header.Set(usernameHeader, username)
		mw.ServeHTTP(nil, req)
		<-done
	})

	t.Run("valid", func(t *testing.T) {
		done := make(chan struct{})
		next := http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
			got, ok := GetUsername(req.Context())
			assert.Equal(t, username, got)
			assert.True(t, ok)
			close(done)
		})
		mw := Middleware(secret, nil, next)
		req := httptest.NewRequest("", uri, nil)
		req.Header.Set(usernameHeader, username)
		req.Header.Set(tokenHeader, hex.EncodeToString(token))
		req.Header.Set(timestampHeader, ts)
		mw.ServeHTTP(nil, req)
		<-done
	})
}

func Test_validateRecentTimestamp(t *testing.T) {
	ts := time.Now().UTC().Format(time.RFC3339)
	err := validateRecentTimestamp(ts, 10*time.Second, time.Second)
	assert.NoError(t, err)

	ts = time.Now().Add(2 * time.Second).UTC().Format(time.RFC3339)
	err = validateRecentTimestamp(ts, 10*time.Second, time.Second)
	assert.EqualError(t, err, "timestamp in the future")

	ts = time.Now().Add(-2 * time.Second).UTC().Format(time.RFC3339)
	err = validateRecentTimestamp(ts, 10*time.Second, time.Second)
	assert.NoError(t, err)

	ts = time.Now().Add(-10 * time.Second).UTC().Format(time.RFC3339)
	err = validateRecentTimestamp(ts, 10*time.Second, time.Second)
	assert.NoError(t, err)

	ts = time.Now().Add(-12 * time.Second).UTC().Format(time.RFC3339)
	err = validateRecentTimestamp(ts, 10*time.Second, time.Second)
	assert.EqualError(t, err, "timestamp too old")

	err = validateRecentTimestamp("12345", 10*time.Second, time.Second)
	assert.EqualError(t, err, "invalid timestamp")
}

func Test_hasUsernameHeader(t *testing.T) {
	// hasUsernameHeader doesn't work unless usernameHeader header is formatted as a canonical mime header
	assert.Equal(t, usernameHeader, textproto.CanonicalMIMEHeaderKey(usernameHeader))

	req := httptest.NewRequest("", "/", nil)
	assert.False(t, hasUsernameHeader(req))
	req.Header.Set(strings.ToLower(usernameHeader), "")
	assert.True(t, hasUsernameHeader(req))
}

func Test_roundTripper_RoundTrip(t *testing.T) {
	secret := []byte("this is my secret key")
	username := "joe"
	transport := transportFunc(func(req *http.Request) (*http.Response, error) {
		assert.True(t, hasUsernameHeader(req))
		err := ValidateHMAC(req, secret, nil)
		assert.Equal(t, username, req.Header.Get(usernameHeader))
		assert.NoError(t, err)
		return nil, nil
	})
	rt := RoundTripper(username, secret, transport)
	req := httptest.NewRequest("", "/", nil)
	got, err := rt.RoundTrip(req)
	assert.Nil(t, got)
	assert.Nil(t, err)

	if got != nil {
		defer got.Body.Close()
	}
}

type transportFunc func(req *http.Request) (*http.Response, error)

func (r transportFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return r(req)
}
