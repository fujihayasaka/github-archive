// Package indexer is responsible for indexing alerts into Elasticsearch and Insights.
package indexer

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
	"github.com/pkg/errors"
)

// Service is responsible for indexing alerts into Elasticsearch and Insights.
type Service struct {
	Alerts          *alert.Service
	Repositories    *repository.Service
	RepoAPI         ghgh.RepositoryAPI
	ElasticSearch   *elasticsearch.Service
	InsightsHandler ts.InsightsHydroAlertEventHandler
}

// NewService creates a indexing service with the given parameters
func NewService(alerts *alert.Service, repositories *repository.Service, repoAPI ghgh.RepositoryAPI, es *elasticsearch.Service, insightsHandler ts.InsightsHydroAlertEventHandler) *Service {
	return &Service{
		Alerts:          alerts,
		Repositories:    repositories,
		RepoAPI:         repoAPI,
		ElasticSearch:   es,
		InsightsHandler: insightsHandler,
	}
}

func (s *Service) FetchRepository(ctx context.Context, repositoryID ts.RepositoryEID) (*ts.Repository, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer s.duration(ctx, "fetch-repository")()

	// Fetch repository object
	repository, err := s.Repositories.Find(ctx, repositoryID)
	if err != nil {
		return nil, err
	}

	// Check that we have a repository object with metadata
	if repository == nil {
		// try to fetch the metadata from Twirp
		repos, err := s.RepoAPI.GetRepositories(ctx, []ts.RepositoryEID{repositoryID})
		if err != nil {
			return nil, err
		}
		if len(repos) == 0 {
			return nil, errors.Errorf("repository %d not found", repositoryID)
		}
		err = s.Repositories.Update(ctx, repos[0])
		if err != nil {
			return nil, errors.Wrap(err, "failed to update repository metadata")
		}

		repository = repos[0]
	}
	return repository, nil
}

func (s *Service) IndexAlerts(ctx context.Context, loader *alert.Loader, alertsToIncludeInInsights map[ts.LogicalAlertID]struct{}) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer s.duration(ctx, "index-alerts")()

	return loader.BatchedLoad(ctx, func(alerts []*ts.LogicalAlert) error {
		docs, err := ts.SearchDocumentsFromAlerts(loader.Repo(), alerts)
		if err != nil {
			return err
		}

		// Update Elasticsearch index
		err = s.ElasticSearch.IndexDocuments(ctx, ts.Index_OrgLevel, docs)
		if err != nil {
			return err
		}
		// Emit events to insights
		err = s.InsightsHandler.EmitInsightsEvents(ctx, docs, alertsToIncludeInInsights)
		if err != nil {
			return err
		}
		return nil
	})
}

func (s *Service) UpdateCanonicalIDs(ctx context.Context, alertIDmap map[ts.LogicalAlertID]ts.PhysicalAlertID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer s.duration(ctx, "update-canonical-ids")()

	return s.ElasticSearch.UpdateCanonicalIDs(ctx, alertIDmap, 1000)
}

func (s *Service) duration(ctx context.Context, method string) func() {
	start := time.Now()
	return func() {
		if !appctx.IsShuttingDown(ctx) {
			appctx.Stats(ctx).DistributionMs("indexer.request", stats.Tags{"method": method}, time.Since(start))
		}
	}
}
