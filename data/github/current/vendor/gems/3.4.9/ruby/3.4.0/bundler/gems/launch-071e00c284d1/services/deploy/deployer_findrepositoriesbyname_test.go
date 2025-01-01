package deploy

import (
	context "context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/cache/cachemem"
	"github.com/github/launch/pkg/launchcache"
	ghactions "github.com/github/launch/proto/monolith/core/v1"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/workerpool"
)

func TestDeployer_FindRepositoriesByName(t *testing.T) {
	ghTwirpCache := launchcache.NewNamespacedCache(cachemem.NewExpiringCache(1<<20), observability.NewTestObservability()).GitHubTwirp()
	log := logger.TestLogger()
	statter := statter.NullStatter()
	deployer := &service{
		cfg: config{
			Log:     log,
			Stats:   statter,
			Obs:     observability.New(log, statter),
			Workers: workerpool.NewSimple(log, statter),
		},
		TwirpCache: ghTwirpCache,
	}

	type testCase struct {
		name                     string
		nwos                     []string
		twirpNwos                []string
		mockRes                  *ghtwirp.RepositoriesInfo
		want                     []*Repository
		errorMsg                 string
		useCache                 bool
		getPrivateReposFromCache bool
		returnedErr              error
		isEnterprise             bool
		isMultiTenant            bool
	}

	tests := []testCase{
		{
			name:      "returns the expected repositories with cache miss",
			nwos:      []string{"org3/repo1", "org3/repo2", "org4/repo1"},
			twirpNwos: []string{"org3/repo1", "org3/repo2", "org4/repo1"},
			mockRes: &ghtwirp.RepositoriesInfo{
				Repositories: []*ghactions.Repository{
					{
						Id:            46,
						Name:          "repo1",
						GlobalRelayId: "MFQ6VXNlcjI=",
						OwnerLogin:    "org3",
						Visibility:    1,
					},
					{
						Id:            47,
						Name:          "repo2",
						GlobalRelayId: "MGQ6VXNkcjI=",
						OwnerLogin:    "org3",
						Visibility:    3,
					},
					{
						Id:            48,
						Name:          "repo1",
						GlobalRelayId: "MGQ6VXNkcjI=",
						OwnerLogin:    "org4",
						Visibility:    2,
					},
				},
				RepositoriesNotFoundErrorMessage: "",
			},
			want: []*Repository{
				{
					ID:            46,
					Name:          "repo1",
					GlobalRelayID: "MFQ6VXNlcjI=",
					OwnerLogin:    "org3",
					Visibility:    1,
				},
				{
					ID:            47,
					Name:          "repo2",
					GlobalRelayID: "MGQ6VXNkcjI=",
					OwnerLogin:    "org3",
					Visibility:    3,
				},
				{
					ID:            48,
					Name:          "repo1",
					GlobalRelayID: "MGQ6VXNkcjI=",
					OwnerLogin:    "org4",
					Visibility:    2,
				},
			},
			errorMsg:                 "",
			useCache:                 true,
			getPrivateReposFromCache: false,
		},
		{
			name: "returns all repositories using cache",
			nwos: []string{"org3/repo1", "org3/repo2"},
			want: []*Repository{
				{
					ID:            46,
					Name:          "repo1",
					GlobalRelayID: "MFQ6VXNlcjI=",
					OwnerLogin:    "org3",
					Visibility:    1,
					FromCache:     true,
				},
				{
					ID:            47,
					Name:          "repo2",
					GlobalRelayID: "MGQ6VXNkcjI=",
					OwnerLogin:    "org3",
					Visibility:    3,
					FromCache:     true,
				},
			},
			errorMsg:                 "",
			useCache:                 true,
			getPrivateReposFromCache: false,
		},
		{
			name: "returns all repositories without using cache for GHES",
			nwos: []string{"org3/repo1", "org3/repo2"},
			mockRes: &ghtwirp.RepositoriesInfo{
				Repositories: []*ghactions.Repository{
					{
						Id:            46,
						Name:          "repo1",
						GlobalRelayId: "MFQ6VXNlcjI=",
						OwnerLogin:    "org3",
						Visibility:    1,
					},
					{
						Id:            47,
						Name:          "repo2",
						GlobalRelayId: "MGQ6VXNkcjI=",
						OwnerLogin:    "org3",
						Visibility:    3,
					},
				},
				RepositoriesNotFoundErrorMessage: "",
			}, want: []*Repository{
				{
					ID:            46,
					Name:          "repo1",
					GlobalRelayID: "MFQ6VXNlcjI=",
					OwnerLogin:    "org3",
					Visibility:    1,
					FromCache:     true,
				},
				{
					ID:            47,
					Name:          "repo2",
					GlobalRelayID: "MGQ6VXNkcjI=",
					OwnerLogin:    "org3",
					Visibility:    3,
					FromCache:     true,
				},
			},
			errorMsg:                 "",
			useCache:                 true,
			getPrivateReposFromCache: false,
			isEnterprise:             true,
		},
		{
			name:      "returns the half repositories using cache",
			nwos:      []string{"org3/repo1", "org3/repo3"},
			twirpNwos: []string{"org3/repo3"},
			mockRes: &ghtwirp.RepositoriesInfo{
				Repositories: []*ghactions.Repository{
					{
						Id:            45,
						Name:          "repo3",
						GlobalRelayId: "MDQ6VXNlcjI=",
						OwnerLogin:    "org2",
						Visibility:    3,
					},
				},
				RepositoriesNotFoundErrorMessage: "",
			},
			want: []*Repository{
				{
					ID:            46,
					Name:          "repo1",
					GlobalRelayID: "MFQ6VXNlcjI=",
					OwnerLogin:    "org3",
					Visibility:    1,
					FromCache:     true,
				},
				{
					ID:            45,
					Name:          "repo3",
					GlobalRelayID: "MDQ6VXNlcjI=",
					OwnerLogin:    "org2",
					Visibility:    3,
				},
			},
			errorMsg:                 "",
			useCache:                 true,
			getPrivateReposFromCache: false,
		},
		{
			name:      "returns the private repositories from the twirp call even if the repo is present in cache when getPrivateReposFromCache is false",
			nwos:      []string{"org3/repo1", "org4/repo1"},
			twirpNwos: []string{"org4/repo1"},
			mockRes: &ghtwirp.RepositoriesInfo{
				Repositories: []*ghactions.Repository{
					{
						Id:            48,
						Name:          "repo1",
						GlobalRelayId: "MGQ6VXNkcjI=",
						OwnerLogin:    "org4",
						Visibility:    2,
					},
				},
				RepositoriesNotFoundErrorMessage: "",
			},
			want: []*Repository{
				{
					ID:            46,
					Name:          "repo1",
					GlobalRelayID: "MFQ6VXNlcjI=",
					OwnerLogin:    "org3",
					Visibility:    1,
					FromCache:     true,
				},
				{
					ID:            48,
					Name:          "repo1",
					GlobalRelayID: "MGQ6VXNkcjI=",
					OwnerLogin:    "org4",
					Visibility:    2,
				},
			},
			errorMsg:                 "",
			useCache:                 true,
			getPrivateReposFromCache: false,
		},
		{
			name: "returns the private repositories using cache only when getPrivateReposFromCache is true",
			nwos: []string{"org3/repo1", "org4/repo1"},
			want: []*Repository{
				{
					ID:            46,
					Name:          "repo1",
					GlobalRelayID: "MFQ6VXNlcjI=",
					OwnerLogin:    "org3",
					Visibility:    1,
					FromCache:     true,
				},
				{
					ID:            48,
					Name:          "repo1",
					GlobalRelayID: "MGQ6VXNkcjI=",
					OwnerLogin:    "org4",
					Visibility:    2,
					FromCache:     true,
				},
			},
			errorMsg:                 "",
			useCache:                 true,
			getPrivateReposFromCache: true,
		},
		{
			name:      "returns error msg in case repositories not found",
			nwos:      []string{"org1/repo1", "org2/repo2"},
			twirpNwos: []string{"org1/repo1", "org2/repo2"},
			useCache:  false,
			mockRes: &ghtwirp.RepositoriesInfo{
				Repositories:                     nil,
				RepositoriesNotFoundErrorMessage: "Repositories not found: org1/repo1 and org2/repo2.",
			},
			want:                     []*Repository(nil),
			errorMsg:                 "Repositories not found: org1/repo1 and org2/repo2.",
			getPrivateReposFromCache: false,
		},
		{
			name: "returns nil when no nwos are provided",
			nwos: []string{},
			mockRes: &ghtwirp.RepositoriesInfo{
				Repositories:                     nil,
				RepositoriesNotFoundErrorMessage: "",
			},
			want:                     []*Repository(nil),
			errorMsg:                 "",
			returnedErr:              nil,
			useCache:                 false,
			getPrivateReposFromCache: false,
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}

	// multitenant test cases should work the same as the
	// existing ones, so we just make a copy
	multiTenantTests := make([]testCase, len(tests))
	copy(multiTenantTests, tests)
	for _, mtt := range multiTenantTests {
		mtt.isMultiTenant = true
		tests = append(tests, mtt)
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.twirpNwos != nil {
				mockTwirpClient.On("FindRepositoriesByName", mock.Anything, mock.Anything).Return(tt.mockRes, tt.returnedErr).Once()
			}

			deployer.cfg.GithubTwirpClient = mockTwirpClient
			deployer.IsMultiTenant = tt.isMultiTenant

			ctx := context.TODO()
			var err error
			if tt.isMultiTenant {
				ctx, err = ghtenant.ContextWithTenantID(ctx, 42, tt.isMultiTenant)
				require.NoError(t, err)
			}
			got, repositoriesNotFoundErrorMessage, err := deployer.FindRepositoriesByName(ctx, tt.nwos, tt.useCache, tt.getPrivateReposFromCache)

			if tt.returnedErr != nil {
				assert.EqualError(t, err, tt.returnedErr.Error())
			} else {
				require.NoError(t, err)
			}

			assert.Equal(t, tt.want, got)
			assert.Equal(t, tt.errorMsg, repositoriesNotFoundErrorMessage)
		})
	}
}

func TestDeployer_UpdateRepoVisibilityCache(t *testing.T) {
	ghTwirpCache := launchcache.NewNamespacedCache(cachemem.NewExpiringCache(1<<20), observability.NewTestObservability()).GitHubTwirp()
	log := logger.TestLogger()
	statter := statter.NullStatter()
	deployer := &service{
		cfg: config{
			Log:     log,
			Stats:   statter,
			Obs:     observability.New(log, statter),
			Workers: workerpool.NewSimple(log, statter),
		},
		TwirpCache: ghTwirpCache,
	}

	type testCase struct {
		name                     string
		nwos                     []string
		twirpNwos                []string
		mockRes                  *ghtwirp.RepositoriesInfo
		want                     []*Repository
		errorMsg                 string
		useCache                 bool
		getPrivateReposFromCache bool
		returnedErr              error
		latestVisibility         ghactions.RepositoryVisibility
		wantAfterUpdate          []*Repository
		isMultiTenant            bool
	}

	tests := []testCase{
		{
			name:      "update the visibility of cached repository",
			nwos:      []string{"org3/repo1"},
			twirpNwos: []string{"org3/repo1"},
			mockRes: &ghtwirp.RepositoriesInfo{
				Repositories: []*ghactions.Repository{
					{
						Id:            46,
						Name:          "repo1",
						GlobalRelayId: "MFQ6VXNlcjI=",
						OwnerLogin:    "org3",
						Visibility:    1,
					},
				},
				RepositoriesNotFoundErrorMessage: "",
			},
			want: []*Repository{
				{
					ID:            46,
					Name:          "repo1",
					GlobalRelayID: "MFQ6VXNlcjI=",
					OwnerLogin:    "org3",
					Visibility:    1,
				},
			},
			errorMsg:                 "",
			useCache:                 true,
			getPrivateReposFromCache: true,
			latestVisibility:         2,
			wantAfterUpdate: []*Repository{
				{
					ID:            46,
					Name:          "repo1",
					GlobalRelayID: "MFQ6VXNlcjI=",
					OwnerLogin:    "org3",
					Visibility:    2,
					FromCache:     true,
				},
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}

	// multitenant test cases should work the same as the
	// existing ones, so we just make a copy
	multiTenantTests := make([]testCase, len(tests))
	copy(multiTenantTests, tests)
	for _, mtt := range multiTenantTests {
		mtt.isMultiTenant = true
		tests = append(tests, mtt)
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.twirpNwos != nil {
				mockTwirpClient.On("FindRepositoriesByName", mock.Anything, mock.Anything).Return(tt.mockRes, tt.returnedErr).Once()
			}

			deployer.cfg.GithubTwirpClient = mockTwirpClient
			deployer.IsMultiTenant = tt.isMultiTenant

			ctx := context.TODO()
			var err error
			if tt.isMultiTenant {
				ctx, err = ghtenant.ContextWithTenantID(ctx, 42, tt.isMultiTenant)
				require.NoError(t, err)
			}

			got, repositoriesNotFoundErrorMessage, err := deployer.FindRepositoriesByName(ctx, tt.nwos, tt.useCache, tt.getPrivateReposFromCache)
			deployer.UpdateRepoVisibilityCache(ctx, tt.latestVisibility, got[0])
			updatedCache, repositoriesNotFoundErrorMessage, err := deployer.FindRepositoriesByName(ctx, tt.nwos, tt.useCache, tt.getPrivateReposFromCache)

			if tt.returnedErr != nil {
				assert.EqualError(t, err, tt.returnedErr.Error())
			} else {
				require.NoError(t, err)
			}

			assert.Equal(t, tt.want, got)
			assert.Equal(t, tt.wantAfterUpdate, updatedCache)
			assert.Equal(t, tt.errorMsg, repositoriesNotFoundErrorMessage)
		})
	}
}
