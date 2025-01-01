// This file adds functionality for triggering an update to various services after
// the main processing has finished.
// This currently includes: ElasticSearch and Insights.

package processor

import (
	"bytes"
	"context"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/o11y"
	"github.com/pkg/errors"
)

// postProcess triggers the update to ElasticSearch and Insights.
// It does so by collecting the alerts that needs to be updated, and what kind of update is needed.
// The actual update is done asynchronously by a job.
func (p *Processor) postProcess(ctx context.Context, analysis *ts.Analysis, repository *ts.Repository, changedLogicalAlertIds map[ts.LogicalAlertID]struct{}) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer p.duration(ctx, "post-process")()

	if repository == nil {
		// the repository data is gathered early in the processing, so it should always be available here
		// but the logging should help us to ensure that is the case.
		appctx.Stats(ctx).Counter("pp.ingest.update.skip", stats.Tags{"reason": "no_metadata"}, 1)
		appctx.Logger(ctx).Info(
			"Skipping post process index update due to missing metadata",
			analysis.RepositoryID.AsKVP(),
			kvp.Uint64("gh.turboscan.analysis_id", uint64(analysis.ID)),
		)
		return nil
	}

	if !bytes.Equal(repository.DefaultRef, analysis.Ref) {
		// analysis not on main branch, replace changedLogicalAlertIds with an empty map
		changedLogicalAlertIds = make(map[ts.LogicalAlertID]struct{})
	}

	// We expect code scanning to be enabled because we just received an analysis,
	// if it isnt then that is odd and we log it
	if !repository.CodeScanningEnabled {
		appctx.Logger(ctx).Info(
			"Received analysis for disabled repository",
			analysis.RepositoryID.AsKVP(),
			kvp.Uint64("gh.turboscan.analysis_id", uint64(analysis.ID)),
			kvp.Time("gh.repo.created_at", repository.CreatedAt.Time),
			kvp.Time("gh.repo.updated_at", repository.UpdatedAt.Time),
			kvp.Time("gh.turboscan.repository_source_updated_at", repository.SourceUpdatedAt.Time),
		)
	}
	onDefaultBranch := bytes.Equal(repository.DefaultRef, analysis.Ref)

	// There are two types of updates that we need to do:
	// Full updates: These update all information about an alert.
	// Canonical ID updates: These update the canonical ID of an alert.
	indexFull := []ts.LogicalAlertID{}
	indexCanonicalIDs := map[ts.LogicalAlertID]ts.PhysicalAlertID{}

	// Alerts that were present in the analysis are open need to be indexed, as their data might have changed.
	for _, a := range analysis.PresentAlerts() {
		indexFull = append(indexFull, a.LogicalAlertID)
	}

	// The update behaviour for fixed alerts depends on whether they were fixed in this particular analysis.
	// If they were fixed now, we need to load them with a full index to determine whether they are fixed across all configurations.
	// For all the other fixed alerts, we just need to update the canonical ID since the rest of the information should be the same.
	if onDefaultBranch {
		for _, p := range analysis.FixedAlerts() {
			if p.LastSeenAnalysisID != nil && analysis.BaselineID != nil &&
				*p.LastSeenAnalysisID == *analysis.BaselineID {
				indexFull = append(indexFull, p.LogicalAlertID)
			} else {
				indexCanonicalIDs[p.LogicalAlertID] = p.ID
			}
		}
	}

	appctx.Logger(ctx).Info("Alerts to index",
		analysis.RepositoryID.AsKVP(),
		kvp.Uint64("gh.turboscan.analysis_id", uint64(analysis.ID)),
		kvp.Int("gh.turboscan.indexed_full", len(indexFull)),
		kvp.Int("gh.turboscan.indexed_canonical_id", len(indexCanonicalIDs)),
	)

	if len(indexFull) == 0 && len(indexCanonicalIDs) == 0 {
		appctx.Stats(ctx).Counter("pp.ingest.update.skip", stats.Tags{"reason": "no_alerts"}, 1)
		return nil
	}

	indexJob := &jobs.AlertIndexing{
		Context:      "post-analysis-processing",
		RepositoryID: analysis.RepositoryID,
		AnalysisID:   analysis.ID,

		LogicalAlertIDs:           indexFull,
		AlertsToIncludeInInsights: changedLogicalAlertIds,
		CanonicalIDsToUpdate:      indexCanonicalIDs,
	}

	// Trigger the job to perform the actual update.
	_, err := p.jobs.PerformLater(ctx, indexJob)
	if err != nil {
		return errors.Wrap(err, "failed to enqueue async indexing job")
	}

	return nil
}
