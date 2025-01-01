package repositories

import (
	"context"
	"sync"
	"time"

	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/internal/projections/repository_names"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/internal/utils"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	twirpRepositories "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/codes"
	"golang.org/x/sync/errgroup"
)

type repositoryService struct {
	RepositoryService
	telem *telemetry.Telemetry
}

func successTags() stats.Tags { return stats.Tags{telemetry.StatusKey: telemetry.SuccessStatus} }
func failTags() stats.Tags    { return stats.Tags{telemetry.StatusKey: telemetry.FailedStatus} }

type RepositoryService interface {
	// Returns a map of ID to name
	GetRepositoryNames(ctx context.Context, scope *proto.Scope, repoIds []int64) (map[int64]string, error)
}

var service *repositoryService = nil

// FindRepositories twirp call has a limit of 100 repositories per call.
// https://github.com/github/github/blob/7e07993e7490535752545f12562c3bbac1b2e60d/app/api/internal/twirp/repositories/v1/repositories_api_handler.rb#L16
const findRepositoriesMaxBatchSize = 100

func SetRepositoryService(telem *telemetry.Telemetry, cfg config.HttpConfig) error {
	err := SetRepositoriesClient(cfg)

	if err != nil {
		return err
	}

	service = &repositoryService{telem: telem}
	return nil
}

func GetRepositoryService() RepositoryService {
	return service
}

func (r *repositoryService) GetRepositoryNames(ctx context.Context, scope *proto.Scope, ids []int64) (map[int64]string, error) {
	ctx, span := telemetry.Trace(ctx, "repositoryService.GetRepositoryNames")
	defer span.End()
	logger := r.telem.Logger.WithContext(ctx)

	distinctIds := utils.RemoveDuplicates(ids)

	if scope.ScopeType == proto.ScopeType_SCOPE_TYPE_REPO {
		// if this is repo level then we don't need to resolve any repos because repo names are not included in any output

		// return empty map
		return make(map[int64]string), nil
	}

	if len(distinctIds) <= findRepositoriesMaxBatchSize {
		// with this few repos, just resolve them all through the service
		return findRepositoriesByIdApi(ctx, r.telem, distinctIds)
	}

	kustoRepos, err := getAllRepositoriesKusto(ctx, r.telem, scope)
	if err != nil {
		r.telem.Logger.WithError(err)
		return nil, err
	}

	reposNotInKusto := make([]int64, 0, 0)
	result := make(map[int64]string)

	for _, id := range distinctIds {
		name, ok := kustoRepos[id]
		if ok {
			result[id] = name
		} else {
			reposNotInKusto = append(reposNotInKusto, id)
		}
	}

	if len(reposNotInKusto) > 0 {
		apiRepos, err := findRepositoriesByIdApi(ctx, r.telem, reposNotInKusto)
		if err != nil {
			logger.WithError(err)
			return nil, err
		}

		// Combine the results from kusto and the api
		for _, id := range reposNotInKusto {
			name, ok := apiRepos[id]
			if ok {
				result[id] = name
			} else {
				// Warn if we can't find the repo in Kusto or the API
				if scope.GetScopeType() == proto.ScopeType_SCOPE_TYPE_ENTERPRISE {
					logger.Warn("Failed to find repo with enterprise id and repo id", kvp.Int64p(telemetry.OTelKeyEnterpriseId, scope.EnterpriseId), kvp.Int64(telemetry.OTelKeyRepoId, id))
				} else {
					logger.Warn("Failed to find repo with owner id and repo id", kvp.Int64p(telemetry.OTelKeyOwnerId, scope.OwnerId), kvp.Int64(telemetry.OTelKeyRepoId, id))
				}
				r.telem.Stats.Counter(telemetry.ReposFindByIdMissingCount_StatsKey, nil, 1)

			}
		}
	}

	return result, nil
}

func findRepositoriesByIdApi(ctx context.Context, telem *telemetry.Telemetry, distinctIds []int64) (map[int64]string, error) {
	// Fetch repos for provided ids from twirp API and return map of id -> name

	ctx, span := telemetry.Trace(ctx, "repositoryService.findRepositoriesById")
	defer span.End()
	logger := telem.Logger.WithContext(ctx)

	// map of key to value
	result := make(map[int64]string)
	resultMapMutex := sync.RWMutex{}

	// Get slices of 100 keys
	batches := utils.ChunkSlice(distinctIds, findRepositoriesMaxBatchSize)

	// start up to 5 goroutines
	// each goroutine will make a call to the twirp client with 100 repos
	group, groupCtx := errgroup.WithContext(ctx)
	group.SetLimit(5)

	logger.Info("repositoryService.findRepositoriesById starting to resolve repos:", kvp.Int(telemetry.OTelKeyLength, len(distinctIds)))

	start := time.Now()

	for _, batch := range batches {
		group.Go(func() error {
			span.AddEvent("repositoryService.findRepositoriesById batch")
			// call twirp client with 100 repos
			resp, err := repositoryClient.FindRepositories(groupCtx, &twirpRepositories.FindRepositoriesRequest{
				Ids: batch,
			})

			if err != nil {
				telem.Stats.Counter(telemetry.ReposFindByIdCount_StatsKey, failTags(), 1)
				span.SetStatus(codes.Error, err.Error())

				twError, ok := err.(twirp.Error)
				if ok {
					logger.Error("repositoryService.findRepositoriesById error", kvp.Any(telemetry.OTelKeyMeta, twError.MetaMap()), kvp.String(telemetry.OTelKeyTwirpError, twError.Error()))
				} else {
					logger.WithError(err).Error("Failed repositoryClient.FindRepositories")
				}

				return err
			}
			telem.Stats.Counter(telemetry.ReposFindByIdCount_StatsKey, successTags(), 1)

			repos := resp.GetRepositories()

			batchDuration := time.Since(start)
			logger.Info("repositoryService.findRepositoriesById single batch duration", kvp.Duration(telemetry.OTelKeyDuration, batchDuration))

			for _, repo := range repos {
				if repo == nil {
					telem.Stats.Counter(telemetry.ReposFindNil_StatsKey, nil, 1)
					continue
				}
				resultMapMutex.Lock()
				result[repo.GetId()] = repo.GetName()
				resultMapMutex.Unlock()
			}
			return nil
		})
	}

	if err := group.Wait(); err != nil {
		span.SetStatus(codes.Error, err.Error())
		return nil, err
	}

	duration := time.Since(start)
	logger.Info("repositoryService.findRepositoriesById total duration", kvp.Duration(telemetry.OTelKeyDuration, duration))
	telem.Stats.DistributionMs(telemetry.ReposFindByIdDuration_StatsKey, nil, duration)

	return result, nil
}

// Fetch all repos from kusto and return map of id -> name. For repo scope only returns 1 result
func getAllRepositoriesKusto(ctx context.Context, telem *telemetry.Telemetry, scope *proto.Scope) (map[int64]string, error) {

	ctx, span := telemetry.Trace(ctx, "repositoryService.getAllRepositoriesKusto")
	defer span.End()
	logger := telem.Logger.WithContext(ctx)
	start := time.Now()
	kusto_result, err := repository_names.QueryRepositoryNames(ctx, scope)
	if err != nil {
		return nil, err
	}

	logger.Info("repositoryService.getAllRepositoriesKusto received repos from kusto:", kvp.Int(telemetry.OTelKeyLength, len(kusto_result.Items)))

	result := make(map[int64]string)

	for _, repo := range kusto_result.Items {
		result[repo.Id] = repo.Name
	}

	duration := time.Since(start)
	logger.Info("repositoryService.getAllRepositoriesKusto total duration", kvp.Duration(telemetry.OTelKeyDuration, duration))
	telem.Stats.DistributionMs(telemetry.ReposGetAllDuration_StatsKey, nil, duration)

	return result, nil
}
