package githubtwirp

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"
)

var ErrRepoNotFound = errors.New("repo not found")

const (
	// repoCacheKeyPrefix is the prefix for repository cache keys.
	repoCacheKeyPrefix = "githubtwirp:repo:"

	// repoCacheTTL is how long cached repository data is valid.
	// Repository metadata (IDs) rarely change, so we use a 1 hour TTL.
	repoCacheTTL = 60 * time.Minute
)

// repoCacheKey generates a cache key for a repository by tenant, owner, and name.
// Includes tenant ID to prevent cross-tenant cache collisions since the same owner/name
// can refer to different repositories in different tenants.
func repoCacheKey(ctx context.Context, owner, name string) string {
	tenantID := requestctx.TenantID(ctx)
	if tenantID == "" {
		tenantID = "no-tenant"
	}
	return fmt.Sprintf("%s%s:%s/%s", repoCacheKeyPrefix, tenantID, strings.ToLower(owner), strings.ToLower(name))
}

func (gh *Client) GetRepoById(ctx context.Context, id int64) (*repositoriesTwirp.RepositoryListItem, error) {
	ctx, span := gh.obsv.Tracer.Start(ctx, "githubtwirp.Client.GetRepoById")
	defer span.End()

	req := &repositoriesTwirp.FindRepositoriesRequest{
		Ids: []int64{id},
	}
	resp, err := gh.RepositoriesAPI().FindRepositories(ctx, req)
	if err != nil {
		var twirpErr twirp.Error
		if ok := errors.As(err, &twirpErr); ok && twirpErr.Code() == twirp.NotFound {
			return nil, ErrRepoNotFound
		}
		return nil, err
	}

	repos := resp.GetRepositories()
	if len(repos) == 0 {
		return nil, ErrRepoNotFound
	}
	tr := repos[0]

	return tr, nil
}

func (gh *Client) GetRepoByName(ctx context.Context, owner, name string) (*repositoriesTwirp.RepositoryListItem, error) {
	ctx, span := gh.obsv.Tracer.Start(ctx, "githubtwirp.Client.GetRepoByName")
	defer span.End()

	key := repoCacheKey(ctx, owner, name)

	if gh.cacheStore != nil {
		if cachedValue, ok := gh.cacheStore.Get(key); ok && cachedValue != "" {
			var repoItem repositoriesTwirp.RepositoryListItem
			err := proto.Unmarshal([]byte(cachedValue), &repoItem)
			if err == nil {
				return &repoItem, nil
			}
			// Log and continue to fetch from API if unmarshal fails
			gh.obsv.LogAndReportError(ctx, err, "GetRepoByName: failed to unmarshal cached repository")
		}
	}

	// Cache miss or invalid - fetch from upstream
	nwo := fmt.Sprintf("%s/%s", owner, name)
	req := &repositoriesTwirp.FindRepositoriesByNameRequest{
		Nwos: []string{nwo},
	}
	fetchCtx, endFetchSpan := gh.startFetchSubspanIfEnabled(ctx, "githubtwirp.Client.GetRepoByName.fetch")
	resp, err := gh.RepositoriesAPI().FindRepositoriesByName(fetchCtx, req)
	endFetchSpan()
	if err != nil {
		var twirpErr twirp.Error
		if ok := errors.As(err, &twirpErr); ok && twirpErr.Code() == twirp.NotFound {
			return nil, ErrRepoNotFound
		}
		return nil, err
	}

	repos := resp.GetRepositories()
	if len(repos) == 0 {
		return nil, ErrRepoNotFound
	}

	result := repos[0]

	if gh.cacheStore != nil {
		marshaled, err := proto.Marshal(result)
		if err != nil {
			gh.obsv.LogAndReportError(ctx, err, "GetRepoByName: failed to marshal repository for caching")
		} else {
			gh.cacheStore.Set(key, string(marshaled), repoCacheTTL)
		}
	}

	return result, nil
}
