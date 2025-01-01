package tests

import (
	"net/http"
	"net/url"
	"testing"

	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/tests/utils"
	"github.com/github/go-auth/hmac"
	"github.com/stretchr/testify/assert"
)

func MakeRequest(t *testing.T, method, path string, queryParams url.Values) *http.Response {
	cfg := utils.GetDevConfig[config.HttpConfig]()
	hmacVal := hmac.NewRequestHMAC(cfg.HMACPrimary)
	return MakeRawHttpRequest(t, method, path, hmacVal.String(), queryParams)
}

func MakeRawHttpRequest(t *testing.T, method, path string, hmac string, queryParams url.Values) *http.Response {
	url, err := url.JoinPath("http://aum.local:32474", path)
	assert.NoError(t, err)

	req, err := http.NewRequest(method, url, nil)
	req.Header.Add("Content-Type", "application/json")
	assert.NoError(t, err)

	req.URL.RawQuery = queryParams.Encode()

	if hmac != "" {
		req.Header.Add("Request-HMAC", hmac)
	}

	resp, err := http.DefaultClient.Do(req)
	assert.NoError(t, err)

	return resp
}
