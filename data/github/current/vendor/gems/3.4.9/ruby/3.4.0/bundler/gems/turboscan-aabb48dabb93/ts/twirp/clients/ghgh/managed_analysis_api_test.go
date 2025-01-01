package ghgh_test

import (
	"context"
	"net/http"
	"testing"

	"github.com/github/go-twirp/v2/client/auth"
	"github.com/github/turbocassette/recorder"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	ma_api "github.com/github/turboscan/ts/monolith_twirp/managed_analyses/v1"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
	"github.com/stretchr/testify/require"
)

func apiWithCassette(t *testing.T, cassette string) ghgh.ManagedAnalysesAPI {
	t.Helper()

	cfg, err := config.Load()
	require.NoError(t, err)

	hmacSecret := cfg.GitHubTwirpHMACKey

	r, err := recorder.New(cassette)
	require.NoError(t, err)
	hmac, err := auth.NewRequestHMACSigner(hmacSecret, &http.Client{Transport: r})
	require.NoError(t, err)

	return ghgh.NewManagedAnalysesAPI(ma_api.NewManagedAnalysesAPIJSONClient(cfg.GitHubTwirpAddr, hmac), nil, nil)
}

func TestAreRequiredServicesEnabled_RepoNotFoundConverstion(t *testing.T) {
	// If the TWIRP API returns a Not Found error for the repository, we convert it
	// into a ts.ErrRepoNotFound error.
	// This happens when the repository has been potentially deleted from gh/gh.
	api := apiWithCassette(t, "./testdata/are_required_services_enabled_404.yml")
	_, _, _, err := api.AreRequiredServicesEnabled(context.Background(), ts.RepositoryEID(1))
	require.ErrorIs(t, err, ts.ErrRepoNotFound)
}

func TestAreRequiredServicesEnabled_Disabled(t *testing.T) {
	api := apiWithCassette(t, "./testdata/are_required_services_enabled_disabled.yml")
	enabled, _, _, err := api.AreRequiredServicesEnabled(context.Background(), ts.RepositoryEID(1))
	require.NoError(t, err)
	require.False(t, enabled)
}
