// this file adds additional functions on RepositoryCleanupService
// to handle deletion of Elasticsearch data for a repository.

package repository

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/pkg/errors"
)

// ElasticSearchData deletes all ElasticSearch data for the specified repository, it'll update the deleted repository table while it is running
// and return an error if it encounters a problem. If no errors are returned the deletion can be viewed as successful.
func (s *RepositoryCleanupService) ElasticSearchData(ctx context.Context, repositoryID ts.RepositoryEID) error {
	var err error
	startTime := time.Now()
	defer func() {
		appctx.Stats(ctx).DistributionMs("repo_cleanup.elastic_search_data", nil, time.Since(startTime))
		appctx.Logger(ctx).WithError(err).Info("ElasticSearchData request",
			kvp.Float64("gh.operation.duration", float64(time.Since(startTime))),
			repositoryID.AsKVP(),
		)
	}()

	// Set the timeout to deadline
	var timeoutMillis int64
	if !s.deadline.IsZero() {

		timeoutMillis = time.Until(s.deadline).Milliseconds()
		if timeoutMillis <= 0 {
			appctx.Logger(ctx).Info("Deadline exceeded - stopping execution")
			return ErrCleanupStopped
		}
	}

	esDocs, esErr := s.es.DeleteByRepo(ctx, repositoryID, int(timeoutMillis))
	// Timeout and migration errors are converted to the right type
	if errors.Is(esErr, elasticsearch.ErrESTimedOut) || errors.Is(esErr, elasticsearch.ErrMigrationOngoing) {
		esErr = ErrCleanupStopped
	}
	appctx.Logger(ctx).WithError(esErr).Info("Deleted ES docs.",
		repositoryID.AsKVP(),
		kvp.Int64("gh.turboscan.es_docs", esDocs))
	appctx.Stats(ctx).Counter("repo_cleanup.deleted", stats.Tags{"source": "es"}, esDocs)

	if s.dr != nil {
		// ElasticSearch might have deleted some docs before the failure, so we update the
		// DB before returning the error
		dbErr := s.dr.DeleteProgressES(ctx, repositoryID, uint64(esDocs))
		if dbErr != nil {
			// The ElasticSearch error is the most important to the user. Unless it
			// is an error that is expected in normal operation (e.g. a timeout), therefore
			// we prefer to return that to the user if it exists.
			if esErr != nil && !errors.Is(esErr, ErrCleanupStopped) {
				// The DB error should still be logged, so we know it happened.
				appctx.Logger(ctx).WithError(dbErr).Warn("Could not persist ES delete progress.",
					repositoryID.AsKVP())
				return esErr
			} else {
				// In other cases we just return the DB error
				return dbErr
			}
		}
	}

	return nil
}
