package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDiagnosticHandler_DefaultTags(t *testing.T) {
	logger := log.NewNullLogger()
	statter := &stats.NullClient{}

	req, err := http.NewRequest("GET", "/foo", nil)
	require.NoError(t, err)
	req.Header.Set("User-Agent", "authnd-test-agent")
	req.Header.Set("Catalog-Service", "test-service")

	rw := httptest.NewRecorder()
	next := func(w http.ResponseWriter, r *http.Request) {
		tags := twstats.DefaultTags(r.Context())
		assert.Equal(t, "test-service", tags["catalog_service"])
		assert.Equal(t, "authnd-test-agent", tags["user_agent"])
		w.WriteHeader(http.StatusOK)
	}
	DiagnosticHandler(logger, statter)(
		http.HandlerFunc(next),
	).ServeHTTP(rw, req)

	assert.Equal(t, http.StatusOK, rw.Code)
}
