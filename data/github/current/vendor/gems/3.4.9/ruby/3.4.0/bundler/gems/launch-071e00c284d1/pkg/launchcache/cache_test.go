package launchcache

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/types"
)

func runCacheTestSuite(t *testing.T, makeCache func(*testing.T) Cache) {
	ctx := context.Background()
	tests := []struct {
		name  string
		check func(*testing.T, Cache)
	}{
		{
			name: "azp",
			check: checkAzureProvider(func(t *testing.T, c AZPCache) {
				req := "hello"
				cl := "world"
				res := "howru"
				cc := c.BearerTokenCacheFor(req, cl, res)

				var (
					wantb   []byte
					wantexp time.Time
					wantok  bool
				)
				gotb, gotexp, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.WithinDuration(t, wantexp, gotexp, time.Second)
				require.Equal(t, wantb, gotb)

				wantb = []byte("hmm bbq")
				wantexp = time.Now().Add(10 * time.Second)
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotexp, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.WithinDuration(t, wantexp, gotexp, time.Second)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "s2s",
			check: checkS2SProvider(func(t *testing.T, c S2SCache) {
				v := "hello"
				s := "world"
				cc := c.KeyVaultCacheFor(v, s)

				var (
					wantb  []byte
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = []byte("hmm bbq")
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "github: site scoped token using request body with owner id",
			check: checkGitHub(func(t *testing.T, c GitHubCache) {
				ownerID := int64(42)
				appID := int64(15368)
				body := []byte(`{"so_much":"json"}`)
				cc := c.SiteScopedTokenCacheFor(appID, ownerID, body)

				var (
					wantb  []byte
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = []byte("hmm bbq")
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "github-twirp: repo can use actions",
			check: checkGitHubTwirp(func(t *testing.T, c GitHubTwirpCache) {
				r := types.GlobalID("derp")
				cc := c.RepoCanUseActionsCacheFor(r)

				var (
					wantb  []byte
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = []byte("hmm bbq")
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "github-twirp: feature flag",
			check: checkGitHubTwirp(func(t *testing.T, c GitHubTwirpCache) {
				gid := types.GlobalID("derp")
				ff := "high-throughput-potatorator"
				cc := c.FeatureFlagCacheFor(gid, ff)

				var (
					wantb  []byte
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = []byte("hmm bbq")
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "github-twirp: repo-or-owners feature flag",
			check: checkGitHubTwirp(func(t *testing.T, c GitHubTwirpCache) {
				gid := types.GlobalID("derp")
				ff := "high-throughput-potatorator"
				cc := c.RepoOrOwnersFeatureFlagCacheFor(gid, ff)

				var (
					wantb  []byte
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = []byte("hmm bbq")
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "github-twirp: feature flag actor",
			check: checkGitHubTwirp(func(t *testing.T, c GitHubTwirpCache) {
				actor := "Repository:3"
				ff := "high-throughput-potatorator"
				cc := c.FeatureFlagActorCacheFor(actor, ff)

				var (
					wantb  []byte
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = []byte("hmm bbq")
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "github-twirp: trust tier",
			check: checkGitHubTwirp(func(t *testing.T, c GitHubTwirpCache) {
				gid := types.GlobalID("derp")
				cc := c.TrustTierCacheFor(gid)

				var (
					wantb  int64
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = 1
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "github-twirp: repository cache",
			check: checkGitHubTwirp(func(t *testing.T, c GitHubTwirpCache) {
				tenantID := int64(42)
				repo := "github/derp"
				cc := c.RepositoryCacheFor(tenantID, repo)

				var (
					wantb  []byte
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = []byte("hello world")
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "github-twirp: repo account details",
			check: checkGitHubTwirp(func(t *testing.T, c GitHubTwirpCache) {
				gid := types.GlobalID("repo-global-id")
				cc := c.RepoAccountDetailsCacheFor(gid)

				var (
					wantb  []byte
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = []byte("hello world")
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "launch-deps: aqueduct queue depth cache",
			check: checkLaunchDependency(func(t *testing.T, c LaunchDependencyCache) {
				queueName := "job_queue"
				cc := c.AqueductQueueDepthCacheFor(queueName)

				var (
					wantb  int64
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = 42
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "healing-job: skip workflow execution id",
			check: checkHealingJob(func(t *testing.T, c HealingJobCache) {
				wfid := int64(42)
				cc := c.SkipWorkflowExecutionIDFor(wfid)

				var (
					wantb  string
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = "not allowed for arbitrary reasons"
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "github-twirp: global id",
			check: checkGitHubTwirp(func(t *testing.T, c GitHubTwirpCache) {
				legacyGID := "legacy-id"
				cc := c.GlobalIDCacheFor(legacyGID)

				var (
					wantb  types.GlobalID
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = types.GlobalID("arbitrary-value")
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
		{
			name: "transitions: transition cache",
			check: checkTransitions(func(t *testing.T, c TransitionsCache) {
				transitionName := "test-transition"
				cc := c.CacheFor(transitionName)

				var (
					wantb  int64
					wantok bool
				)
				gotb, gotok, err := cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)

				wantb = 12345679
				wantok = true
				err = cc.Set(ctx, wantb, 10*time.Second)
				require.NoError(t, err)

				gotb, gotok, err = cc.Get(ctx)
				require.NoError(t, err)
				require.Equal(t, wantok, gotok)
				require.Equal(t, wantb, gotb)
			}),
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cache := makeCache(t)
			tt.check(t, cache)
		})
	}
}

func checkAzureProvider(fn func(*testing.T, AZPCache)) func(*testing.T, Cache) {
	return func(t *testing.T, c Cache) { fn(t, c.AzureProvider()) }
}
func checkS2SProvider(fn func(*testing.T, S2SCache)) func(*testing.T, Cache) {
	return func(t *testing.T, c Cache) { fn(t, c.S2SProvider()) }
}
func checkGitHub(fn func(*testing.T, GitHubCache)) func(*testing.T, Cache) {
	return func(t *testing.T, c Cache) { fn(t, c.GitHub()) }
}
func checkGitHubTwirp(fn func(*testing.T, GitHubTwirpCache)) func(*testing.T, Cache) {
	return func(t *testing.T, c Cache) { fn(t, c.GitHubTwirp()) }
}
func checkLaunchDependency(fn func(*testing.T, LaunchDependencyCache)) func(*testing.T, Cache) {
	return func(t *testing.T, c Cache) { fn(t, c.LaunchDependency()) }
}
func checkHealingJob(fn func(*testing.T, HealingJobCache)) func(*testing.T, Cache) {
	return func(t *testing.T, c Cache) { fn(t, c.HealingJob()) }
}
func checkTransitions(fn func(*testing.T, TransitionsCache)) func(*testing.T, Cache) {
	return func(t *testing.T, c Cache) { fn(t, c.Transitions()) }
}
