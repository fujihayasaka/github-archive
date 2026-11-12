package featureflags

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/github/feature-management-client-go/vexi/v2"
	"github.com/github/feature-management-client-go/vexi/v2/extensions"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

// CachingClient is a feature flag client that caches results in the request context.
type CachingClient struct {
	client Client
	obsv   observability.Exporters
}

// NewCachingClient creates a new caching feature flag client.
func NewCachingClient(client Client, obsv observability.Exporters) *CachingClient {
	return &CachingClient{
		client: client,
		obsv:   obsv,
	}
}

type contextCacheKey int

var cacheKey contextCacheKey

// Middleware returns HTTP middleware that adds caching capabilities.
func (c *CachingClient) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		ctx = context.WithValue(ctx, cacheKey, make(map[string]bool))
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// IsEnabled checks if a feature flag is enabled with caching.
func (c *CachingClient) IsEnabled(ctx context.Context, featureFlagName string, actors ...vexi.Actor) bool {
	key := c.cacheKey(featureFlagName, actors...)

	var cache map[string]bool

	if c := ctx.Value(cacheKey); c != nil {
		if m, ok := c.(map[string]bool); ok {
			cache = m
		}
	}

	if cache != nil {
		if v, ok := cache[key]; ok {
			return v
		}
	} else {
		cache = make(map[string]bool)
	}

	isEnabled := c.client.IsEnabled(ctx, featureFlagName, actors...)
	cache[key] = isEnabled

	return isEnabled
}

// IsEnabledForUser checks if a feature flag is enabled for a user with caching.
func (c *CachingClient) IsEnabledForUser(ctx context.Context, featureFlagName string, userID int64) bool {
	return c.IsEnabled(ctx, featureFlagName, extensions.NewUser(strconv.FormatInt(userID, 10)))
}

// IsEnabledForRepo checks if a feature flag is enabled for a repository with caching.
func (c *CachingClient) IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool {
	return c.IsEnabled(ctx, featureFlagName, extensions.NewRepository(strconv.FormatInt(repoID, 10)))
}

// IsEnabledForUserOrRepo checks if a feature flag is enabled for a user or repository with caching.
func (c *CachingClient) IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool {
	return c.IsEnabled(ctx, featureFlagName,
		extensions.NewUser(strconv.FormatInt(userID, 10)),
		extensions.NewRepository(strconv.FormatInt(repoID, 10)))
}

// IsEnabledForOrganization checks if a feature flag is enabled for a specific organization with caching.
func (c *CachingClient) IsEnabledForOrganization(ctx context.Context, featureFlagName string, orgID int64) bool {
	return c.IsEnabled(ctx, featureFlagName,
		extensions.NewOrganization(strconv.FormatInt(orgID, 10)))
}

// IsEnabledForOwner checks if a feature flag is enabled for a repository owner with caching.
func (c *CachingClient) IsEnabledForOwner(ctx context.Context, featureFlagName string, ownerID int64) bool {
	return c.IsEnabled(ctx, featureFlagName,
		extensions.NewUser(strconv.FormatInt(ownerID, 10)),
		extensions.NewOrganization(strconv.FormatInt(ownerID, 10)))
}

// IsEnabledForUserOrRepoOrOwner checks if a feature flag is enabled for a user, repository, or owner with caching.
func (c *CachingClient) IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, userID, repoID, repoOwnerID int64) bool {
	return c.IsEnabled(ctx, featureFlagName,
		extensions.NewUser(strconv.FormatInt(userID, 10)),
		extensions.NewRepository(strconv.FormatInt(repoID, 10)),
		extensions.NewUser(strconv.FormatInt(repoOwnerID, 10)), // Owner as a user
		extensions.NewOrganization(strconv.FormatInt(repoOwnerID, 10)))
}

// IsEnabledForGitHubApp checks if a feature flag is enabled for a GitHub App with caching.
func (c *CachingClient) IsEnabledForGitHubApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return c.IsEnabled(ctx, featureFlagName, extensions.NewGitHubApp(strconv.FormatInt(appID, 10)))
}

// IsEnabledForOAuthApp checks if a feature flag is enabled for an OAuth App with caching.
func (c *CachingClient) IsEnabledForOAuthApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return c.IsEnabled(ctx, featureFlagName, extensions.NewOAuthApplication(strconv.FormatInt(appID, 10)))
}

// IsEnabledMiddleware checks if the user has the feature flag enabled.
// If there is no user, or the user does not have the feature flag enabled,
// it returns a 404.
func (c *CachingClient) IsEnabledMiddleware(feature string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			ctx := r.Context()
			user, hasUser := requestctx.User(ctx)
			if !hasUser {
				c.obsv.Logger.Info("no user in context - returning 404")
				http.NotFound(w, r)
				return
			}

			enabled := c.IsEnabledForUser(ctx, feature, int64(user.ID))
			if !enabled {
				c.obsv.Logger.Info(fmt.Sprintf("feature flag '%s' not enabled - returning 404", feature))
				http.NotFound(w, r)
				return
			}

			next.ServeHTTP(w, r)
		}

		return http.HandlerFunc(fn)
	}
}

// cacheKey generates a cache key for feature flag lookups.
func (c *CachingClient) cacheKey(featureFlagName string, actors ...vexi.Actor) string {
	sb := strings.Builder{}
	_, _ = sb.WriteString(featureFlagName)

	for _, actor := range actors {
		_, _ = sb.WriteString(":")
		_, _ = sb.WriteString(actor.VexiID())
	}

	return sb.String()
}
