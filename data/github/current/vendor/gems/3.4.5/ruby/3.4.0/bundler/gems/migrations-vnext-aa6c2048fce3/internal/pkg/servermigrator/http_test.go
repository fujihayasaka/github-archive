package servermigrator

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_webhookHandler(t *testing.T) {
	tests := map[string]struct {
		getsHeaders         map[string]string
		getsRequestBody     string
		wantsResponseSubstr string
		wantsStatusCode     int
	}{
		"should return an error if the webhook is missing the GitHub delivery header": {
			wantsResponseSubstr: "missing GitHub delivery header",
			wantsStatusCode:     http.StatusBadRequest,
		},
		"should return an error if the webhook cannot be validated": {
			getsHeaders:         map[string]string{"Content-type": "application/json", "X-GitHub-Delivery": "123", "X-Hub-Signature-256": "test"},
			getsRequestBody:     "{}",
			wantsResponseSubstr: "could not validate webhook payload",
			wantsStatusCode:     http.StatusBadRequest,
		},
		"should return an error if the webhook cannot be parsed": {
			getsHeaders:         map[string]string{"Content-type": "application/json", "X-GitHub-Delivery": "123", "X-Github-Event": "does-not-exist"},
			getsRequestBody:     `{}`,
			wantsResponseSubstr: "could not parse webhook",
			wantsStatusCode:     http.StatusBadRequest,
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			rw := httptest.NewRecorder()
			s := &ServerMigrator{
				logger: log.NewNullLogger(),
			}

			req, err := http.NewRequest(http.MethodPost, "/api/v1/webhooks", strings.NewReader(test.getsRequestBody))
			require.NoError(t, err)
			for k, v := range test.getsHeaders {
				req.Header.Set(k, v)
			}

			s.webhookHandler(rw, req)

			res := rw.Result()
			assert.Equal(t, test.wantsStatusCode, res.StatusCode)

			buf, err := io.ReadAll(res.Body)
			require.NoError(t, err)
			assert.Contains(t, string(buf), test.wantsResponseSubstr)
		})
	}
}
