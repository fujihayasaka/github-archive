package ghapi_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/ghapi"
	"github.com/stretchr/testify/require"
)

func TestGetReposAudits(t *testing.T) {
	expectedReposResult := ghapi.RepoAuditsResponse{
		Results: []ghapi.RepoAudit{
			{RepositoryID: ts.RepositoryEID(1), Result: "exists"},
			{RepositoryID: ts.RepositoryEID(2), Result: "not_found"}},
	}

	mockServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hmac := r.Header.Get("Request-HMAC")
		require.NotEmpty(t, hmac)
		// TODO: Make /internal part of the path
		require.Equal(t, "/repositories/audits", r.URL.Path)

		err := json.NewEncoder(w).Encode(&expectedReposResult)
		require.NoError(t, err)

		w.WriteHeader(http.StatusOK)
	}))
	defer mockServer.Close()

	cfg := &config.Config{
		GitHubInternalApiAddr: mockServer.URL,
	}
	client, err := ghapi.New(cfg, log.NewNullLogger(), stats.NullStatter)
	require.NoError(t, err)

	reposRequest := ghapi.RepoAuditsRequest{
		RepositoryIDs: []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(2)},
	}
	respData, err := client.GetReposAudits(context.Background(), reposRequest)

	require.NoError(t, err)
	require.Equal(t, expectedReposResult.Results, respData.Results)
}
