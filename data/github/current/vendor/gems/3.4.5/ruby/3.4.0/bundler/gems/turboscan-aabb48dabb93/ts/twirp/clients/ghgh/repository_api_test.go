package ghgh_test

import (
	"context"
	"net/http"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/go-twirp/v2/client/auth"
	"github.com/github/turbocassette/recorder"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	repositories "github.com/github/turboscan/ts/monolith_twirp/repositories/v1"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
	"github.com/stretchr/testify/require"
)

func TestGetRepositories(t *testing.T) {
	cfg, err := config.Load()
	require.NoError(t, err)
	ctx := context.Background()

	r, err := recorder.New("./testdata/repositories.yml")
	require.NoError(t, err)

	hmac, err := auth.NewRequestHMACSigner(cfg.GitHubTwirpHMACKey, &http.Client{Transport: r})
	require.NoError(t, err)

	repositories := ghgh.NewRepositoryAPI(repositories.NewRepositoriesAPIJSONClient(cfg.GitHubTwirpAddr, hmac), log.NewNullLogger(), stats.NullStatter)

	// :WARNING:
	// This test is not checking that we are sending the correct arguments,
	// as the recorder is not doing request matching.
	// :WARNING:

	repos, err := repositories.GetRepositories(ctx, []ts.RepositoryEID{ts.RepositoryEID(2)})
	require.NoError(t, err)
	require.Len(t, repos, 1)

	require.NoError(t, r.Stop())
}
