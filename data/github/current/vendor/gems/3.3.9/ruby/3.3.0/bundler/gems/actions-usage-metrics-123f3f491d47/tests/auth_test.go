package tests

import (
	"io"
	"net/http"
	"testing"

	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/tests/utils"
	"github.com/github/go-auth/hmac"
	"github.com/stretchr/testify/assert"
)

// Tests /health is unauthenticated.
func TestHealthUnauthenticated(t *testing.T) {
	resp := MakeRawHttpRequest(t, http.MethodGet, "/health", "", nil)
	body, err := io.ReadAll(resp.Body)
	assert.NoError(t, err)
	assert.Equal(t, http.StatusOK, resp.StatusCode)
	assert.Equal(t, "OK\n", string(body))
}

// Tests routes are authenticated by default.
func TestAuthenticationFailure(t *testing.T) {
	for _, tt := range []struct {
		name, secret string
		expectedCode int
		expectedBody string
	}{
		{"empty", "", http.StatusBadRequest, "request hmac is missing\n"},
		{"invalid", "foo", http.StatusBadRequest, "HMAC \"foo\" not in correct format\n"},
		{"wrong", hmac.NewRequestHMAC("foo").String(), http.StatusUnauthorized, "invalid hmac token\n"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			resp := MakeRawHttpRequest(t, http.MethodGet, "/whatever", tt.secret, nil)
			body, err := io.ReadAll(resp.Body)
			assert.NoError(t, err)
			assert.Equal(t, tt.expectedCode, resp.StatusCode)
			assert.Equal(t, tt.expectedBody, string(body))
		})
	}
}

// Tests the primary and seconary keys provide access.
func TestAuthenticationSuccess(t *testing.T) {
	cfg := utils.GetDevConfig[config.HttpConfig]()
	for _, tt := range []struct{ name, secret string }{
		{"primary", cfg.HMACPrimary},
		{"secondary", cfg.HMACSecondary},
	} {
		t.Run(tt.name, func(t *testing.T) {
			hmacVal := hmac.NewRequestHMAC(tt.secret)

			resp := MakeRawHttpRequest(t, http.MethodGet, "/whatever", hmacVal.String(), nil)
			assert.Equal(t, http.StatusNotFound, resp.StatusCode)
		})
	}
}
