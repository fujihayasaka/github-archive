package featureflags

import (
	"context"
	"testing"

	"github.com/github/feature-management-client-go/vexi/v2"
	fake_adapter "github.com/github/feature-management-client-go/vexi/v2/adapter/fake"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

func newTestClient(t *testing.T) (*FeatureFlagClient, *fake_adapter.Adapter) {
	t.Helper()
	obsv := observability.NewNoopExporters()
	testAdapter := fake_adapter.NewFakeAdapter(false)
	vexiClient, err := vexi.NewVexiClient(context.Background(),
		testAdapter,
		"test-service",
		vexi.WithLogger(obsv.Logger.Named("vexi")),
		vexi.WithStatsClient(obsv.Statter),
	)
	require.NoError(t, err)

	ffc := &FeatureFlagClient{
		client: vexiClient,
		obsv:   obsv,
	}
	ffc.ready.Store(true)
	return ffc, testAdapter
}

type ttActors struct {
	repoID  int64
	ownerID int64
	userID  int64
}

func (t ttActors) GetRepositoryID() int64 { return t.repoID }
func (t ttActors) GetOwnerID() int64      { return t.ownerID }
func (t ttActors) GetActorID() int64      { return t.userID }

func TestIsEnabledForUserOrRepoOrOwner(t *testing.T) {
	testCases := []struct {
		name           string
		flags          map[string]map[string]bool
		actors         ttActors
		expectedResult bool
	}{
		{
			name:           "nothing enabled",
			flags:          map[string]map[string]bool{},
			actors:         ttActors{repoID: 123, ownerID: 456, userID: 789},
			expectedResult: false,
		},
		{
			name: "repo enabled",
			flags: map[string]map[string]bool{
				"Repository:123": {
					CopilotSWEAgentIntegrationCodeScanningAlerts: true,
				},
			},
			actors:         ttActors{repoID: 123, ownerID: 456, userID: 789},
			expectedResult: true,
		},
		{
			name: "repo owner (user) enabled",
			flags: map[string]map[string]bool{
				"User:456": {
					CopilotSWEAgentIntegrationCodeScanningAlerts: true,
				},
			},
			actors:         ttActors{repoID: 123, ownerID: 456, userID: 789},
			expectedResult: true,
		},
		{
			name: "repo organization enabled",
			flags: map[string]map[string]bool{
				"Organization:456": {
					CopilotSWEAgentIntegrationCodeScanningAlerts: true,
				},
			},
			actors:         ttActors{repoID: 123, ownerID: 456, userID: 789},
			expectedResult: true,
		},
		{
			name: "user enabled",
			flags: map[string]map[string]bool{
				"User:789": {
					CopilotSWEAgentIntegrationCodeScanningAlerts: true,
				},
			},
			actors:         ttActors{repoID: 123, ownerID: 456, userID: 789},
			expectedResult: true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			ffClient, adapter := newTestClient(t)

			for actor, flags := range tc.flags {
				for flag, enabled := range flags {
					if enabled {
						adapter.AddActors(flag, []string{actor})
					} else {
						adapter.RemoveActors(flag, []string{actor})
					}
				}
			}

			ctx := context.Background()
			result := ffClient.IsEnabledForUserOrRepoOrOwner(ctx, CopilotSWEAgentIntegrationCodeScanningAlerts, &tc.actors)
			require.Equal(t, tc.expectedResult, result)
		})
	}
}

func TestIsEnabledForApp(t *testing.T) {
	testCases := []struct {
		name                string
		flags               map[string]map[string]bool
		appID               int64
		oauthAppID          int64
		expectedAppResult   bool
		expectedOauthResult bool
	}{
		{
			name:                "nothing enabled",
			flags:               map[string]map[string]bool{},
			appID:               123,
			oauthAppID:          456,
			expectedAppResult:   false,
			expectedOauthResult: false,
		},
		{
			name: "GitHub App enabled",
			flags: map[string]map[string]bool{
				"Integration:123": {
					CopilotSWEAgentIntegrationCodeScanningAlerts: true,
				},
			},
			appID:               123,
			oauthAppID:          456,
			expectedAppResult:   true,
			expectedOauthResult: false,
		},
		{
			name: "GitHub App enabled",
			flags: map[string]map[string]bool{
				"OauthApplication:456": {
					CopilotSWEAgentIntegrationCodeScanningAlerts: true,
				},
			},
			appID:               123,
			oauthAppID:          456,
			expectedAppResult:   false,
			expectedOauthResult: true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			ffClient, adapter := newTestClient(t)

			for actor, flags := range tc.flags {
				for flag, enabled := range flags {
					if enabled {
						adapter.AddActors(flag, []string{actor})
					} else {
						adapter.RemoveActors(flag, []string{actor})
					}
				}
			}

			ctx := context.Background()
			result := ffClient.IsEnabledForGitHubApp(ctx, CopilotSWEAgentIntegrationCodeScanningAlerts, tc.appID)
			require.Equal(t, tc.expectedAppResult, result)
			result = ffClient.IsEnabledForOAuthApp(ctx, CopilotSWEAgentIntegrationCodeScanningAlerts, tc.oauthAppID)
			require.Equal(t, tc.expectedOauthResult, result)
		})
	}
}
