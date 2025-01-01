package deploy

import (
	context "context"
	json "encoding/json"
	"time"

	"github.com/pkg/errors"

	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchcache"
	ghactions "github.com/github/launch/proto/monolith/core/v1"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
)

const (
	repoCacheExpires = 1 * time.Hour
)

type Repository struct {
	ID            int64
	Name          string
	GlobalRelayID string
	OwnerLogin    string
	Visibility    ghactions.RepositoryVisibility
	FromCache     bool
}

func (s *service) FindRepositoriesByName(ctx context.Context, nwos []string, fetchFromCache bool, getPrivateReposFromCache bool) (repos []*Repository, repositoriesNotFoundErrorMessage string, err error) {
	var repositories []*Repository
	var unfoundNwos []string
	// Include tenant ID to ensure the uniqueness of repo cache keys,
	// especially in multi-tenant environments (i.e. Proxima).
	tenantID, err := ghtenant.TenantIDFromContext(ctx, s.IsMultiTenant)
	if err != nil {
		return nil, "", err
	}

	// Never fetch from cache in case of GHES
	if !s.IsEnterprise && fetchFromCache {
		for _, nwo := range nwos {
			repo, cacheFound := getRepoFromCache(ctx, s.cfg.Obs, s.TwirpCache, nwo, tenantID)
			// We need to fetch live data of private repos in case private actions are not allowed.
			// Because in that case we will anyway make a twirp call later to check if this private repo is made internal/public. So doing it here itself.
			if cacheFound && (getPrivateReposFromCache || repo.Visibility != ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE) {
				repositories = append(repositories, makeRepoObject(repo, true))
			} else {
				unfoundNwos = append(unfoundNwos, nwo)
			}
		}
	} else {
		unfoundNwos = nwos
	}

	// In the multitenant (i.e. Proxima) environment, NWOs included in this
	// request pertain to one and only one tenant. The presence of the
	// tenant ID, which is passed in the 'X-GitHub-Tenant' header, is
	// guaranteed by the middleware defined in the SetupGitHubTenantMiddleware
	// function at:
	// https://github.com/github/launch/blob/b540c1784f0638ec88039f65c6746fe750989c7a/pkg/launchserver/mw.go#L79
	if len(unfoundNwos) != 0 {
		repoInfos, err := s.cfg.GithubTwirpClient.FindRepositoriesByName(ctx, unfoundNwos)
		if err != nil {
			return nil, "", err
		}

		twirpRepos := repoInfos.Repositories
		repositoriesNotFoundErrorMessage = repoInfos.RepositoriesNotFoundErrorMessage
		for _, repo := range twirpRepos {
			repositories = append(repositories, makeRepoObject(repo, false))

			// Do not cache in case of GHES as we never fetch data from cache
			if s.IsEnterprise {
				continue
			}

			// Cache repo for future use
			jsonRepo, err := json.Marshal(repo)
			if err != nil {
				s.cfg.Obs.Report(ctx, errors.Wrap(err, "marshaling repo to json for Set"))
			} else {
				repoNwo := types.RepositoryFullName{Owner: repo.OwnerLogin, Name: repo.Name}
				cache := s.TwirpCache.RepositoryCacheFor(tenantID, repoNwo.String())
				cerr := cache.Set(ctx, jsonRepo, repoCacheExpires)
				if cerr != nil {
					// log but don't fail
					s.cfg.Obs.Report(ctx, errors.Wrap(cerr, "failed to write in cache"))
				}
			}
		}
	}

	return repositories, repositoriesNotFoundErrorMessage, nil
}

// Returns a repo from cache if found else returns nil, false
func getRepoFromCache(ctx context.Context, obs *observability.Observability, twirpCache launchcache.GitHubTwirpCache, nwo string, tenant int64) (*ghactions.Repository, bool) {
	var repo ghactions.Repository
	cacheFound := false
	cache := twirpCache.RepositoryCacheFor(tenant, nwo)
	jsonRepo, ok, err := cache.Get(ctx)
	if err != nil {
		obs.Report(ctx, errors.Wrap(err, "failed to look up cache"))
	} else if ok {
		if err := json.Unmarshal(jsonRepo, &repo); err != nil {
			obs.Report(ctx, errors.Wrap(err, "unmarshaling repos from json for Get"))
		} else {
			cacheFound = true
		}
	}

	return &repo, cacheFound
}

// Update repo visibility in cache
func (s *service) UpdateRepoVisibilityCache(ctx context.Context, newVisibility ghactions.RepositoryVisibility, cachedActionRepo *Repository) {
	repo := &ghactions.Repository{
		OwnerLogin:    cachedActionRepo.OwnerLogin,
		Name:          cachedActionRepo.Name,
		Visibility:    newVisibility,
		Id:            cachedActionRepo.ID,
		GlobalRelayId: cachedActionRepo.GlobalRelayID,
	}
	jsonRepo, err := json.Marshal(repo)
	if err != nil {
		s.cfg.Obs.Report(ctx, errors.Wrap(err, "marshaling repo to json for Set"))
		return
	}

	tenantID, err := ghtenant.TenantIDFromContext(ctx, s.IsMultiTenant)
	if err != nil {
		s.cfg.Obs.Report(ctx, errors.Wrap(err, "getting tenant id for Set"))
		return
	}

	repoNwo := types.RepositoryFullName{Owner: repo.OwnerLogin, Name: repo.Name}
	cache := s.TwirpCache.RepositoryCacheFor(tenantID, repoNwo.String())
	cerr := cache.Set(ctx, jsonRepo, repoCacheExpires)
	if cerr != nil {
		// log but don't fail
		s.cfg.Obs.Report(ctx, errors.Wrap(cerr, "failed to write to cache inside UpdateRepoVisibilityCache"))
	}
}

// Make repository object
func makeRepoObject(repo *ghactions.Repository, cacheUsed bool) *Repository {
	return &Repository{
		ID:            repo.GetId(),
		GlobalRelayID: repo.GetGlobalRelayId(),
		Name:          repo.GetName(),
		OwnerLogin:    repo.GetOwnerLogin(),
		Visibility:    repo.GetVisibility(),
		FromCache:     cacheUsed,
	}
}
