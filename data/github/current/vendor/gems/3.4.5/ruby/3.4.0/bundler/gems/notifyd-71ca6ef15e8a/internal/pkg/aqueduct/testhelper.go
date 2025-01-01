package aqueduct

import (
	"encoding/json"
	"fmt"
	"net/http"
	u "net/url"
	"testing"

	"github.com/github/go-config"
	"github.com/stretchr/testify/assert"
)

// Reset sends a reset request aqueduct-lite to clean up any existing job.
//
// NOTE: It uses `assert` instead of `require` because it is meant to be used in integration tests.
// Integration tests in some cases spawn goroutines and `require` does not work when called from a
// goroutine different than the main one.
func Reset(t *testing.T) {
	t.Helper()

	cfg := ClientConfig{}
	err := config.Load(&cfg)
	//nolint:testifylint // This is OK, we call this from a goroutine
	assert.NoError(t, err)
	mw := getMagicWord(t, cfg)
	reset(t, cfg, mw)
}

func reset(t *testing.T, cfg ClientConfig, magicWord string) {
	resp := request(t, cfg.URL, u.Values{"magic_word": {magicWord}})
	defer resp.Body.Close()
	t.Logf("reset aqueduct-lite: %s", resp.Status)
}

func getMagicWord(t *testing.T, cfg ClientConfig) string {
	resp := request(t, cfg.URL, u.Values{})
	defer resp.Body.Close()

	var body map[string]string
	err := json.NewDecoder(resp.Body).Decode(&body)
	assert.NoError(t, err)

	return body["magic_word"]
}

func request(t *testing.T, url string, data u.Values) *http.Response {
	//nolint:noctx // We're OK with this for a test helper
	resp, err := http.PostForm(fmt.Sprintf("%s/admin/reset", url), data)
	assert.NoError(t, err)

	return resp
}
