package jobs

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/pkg/errors"
)

// AlertIndexing is a job that indexes alerts into Elasticsearch and Insights.
// It works by featching the repository metadata, loading the specified alerts
// and then indexing them into Elasticsearch and Insights.
type AlertIndexing struct {
	Context      string // Just a string to help identify the context of the job for telemetry
	RepositoryID ts.RepositoryEID
	AnalysisID   ts.AnalysisID // Can be 0 if there is no analysis in context

	LogicalAlertIDs           []ts.LogicalAlertID
	LogicalAlertNumbers       []uint32
	AlertsToIncludeInInsights map[ts.LogicalAlertID]struct{}
	CanonicalIDsToUpdate      map[ts.LogicalAlertID]ts.PhysicalAlertID
}

var _ aqueduct.EnqueableJob = (*AlertIndexing)(nil)

func (p AlertIndexing) GetRepositoryID() *ts.RepositoryEID {
	return &p.RepositoryID
}

func (p AlertIndexing) Name() string {
	return "AlertIndexing"
}

func (p AlertIndexing) Queue() string {
	return "turboscan-alert-indexing"
}

func (p AlertIndexing) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.DefaultRetryBackoffFunc
}

func (p AlertIndexing) validate(s *aqueduct.TSServices) error {
	if p.RepositoryID == 0 {
		return errors.New("repository ID not set")
	}

	if s == nil || s.Indexer == nil {
		return errors.New("missing required services")
	}

	return nil
}

func (p AlertIndexing) Perform(ctx context.Context, s *aqueduct.TSServices) error {
	ctx = appctx.With(ctx,
		kvp.Uint64("gh.turboscan.analysis_id", uint64(p.AnalysisID)),
		kvp.Int("gh.turboscan.logical_alert_ids", len(p.LogicalAlertIDs)),
		kvp.Int("gh.turboscan.alerts_in_insights", len(p.AlertsToIncludeInInsights)),
		kvp.Int("gh.turboscan.canonical_ids_to_update", len(p.CanonicalIDsToUpdate)),
	)
	logger := appctx.Logger(ctx)
	statsClient := appctx.Stats(ctx).WithTags(stats.Tags{"context": p.Context})

	start := time.Now()

	err := p.validate(s)
	if err != nil {
		logger.WithError(err).Info(
			"Alert indexing job failed validation",
		)
		return nil
	}

	logger.Info("Fetching repository metadata")

	// Fetch repository
	repository, err := s.Indexer.FetchRepository(ctx, p.RepositoryID)
	if err != nil {
		statsClient.Counter("process_alert_updates.skip", stats.Tags{"reason": "no_metadata"}, 1)
		logger.WithError(err).Info(
			"Skipping alert indexing due to missing metadata",
		)
		return nil
	}

	logger.Info("Starting alert indexing")

	// Index alerts by ID
	if len(p.LogicalAlertIDs) > 0 {
		loader := s.Indexer.Alerts.NewLoader(repository)
		loader.SetIDs(p.LogicalAlertIDs)

		err = s.Indexer.IndexAlerts(ctx, loader, p.AlertsToIncludeInInsights)
		if err != nil {
			logger.WithError(err).Info(
				"Failed to index alerts",
			)
			statsClient.Counter("process_alert_updates.finished", stats.Tags{"failed": "true", "reason": "index_by_id_failed"}, 1)
			return nil
		}
	}

	// Index alerts by number
	if len(p.LogicalAlertNumbers) > 0 {
		loader := s.Indexer.Alerts.NewLoader(repository)
		loader.SetNumbers(p.LogicalAlertNumbers)

		err = s.Indexer.IndexAlerts(ctx, loader, p.AlertsToIncludeInInsights)
		if err != nil {
			logger.WithError(err).Info(
				"Failed to index alerts",
			)
			statsClient.Counter("process_alert_updates.finished", stats.Tags{"failed": "true", "reason": "index_by_number_failed"}, 1)
			return nil
		}
	}

	// Update canonical IDs
	if len(p.CanonicalIDsToUpdate) > 0 {
		err = s.Indexer.UpdateCanonicalIDs(ctx, p.CanonicalIDsToUpdate)
		if err != nil {
			logger.WithError(err).Info(
				"Failed to update canonical IDs",
			)
			statsClient.Counter("process_alert_updates.finished", stats.Tags{"failed": "true", "reason": "canonical_ids_failed"}, 1)
			return nil
		}
	}

	statsClient.Counter("process_alert_updates.finished", stats.Tags{"failed": "false"}, 1)
	statsClient.DistributionMs("process_alert_updates.duration", stats.Tags{}, time.Since(start))
	logger.Info("Finished alert indexing",
		kvp.Float64("gh.operation.duration", float64(time.Since(start))),
	)

	return nil
}
