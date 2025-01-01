package processor

import (
	"context"
	"fmt"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

type SuggestedFixTelemetryHandler struct {
	jobs aqueduct.JobPerformer
}

func NewSuggestedFixTelemetryHandler(jobs aqueduct.JobPerformer) *SuggestedFixTelemetryHandler {
	return &SuggestedFixTelemetryHandler{jobs: jobs}
}

func (s *SuggestedFixTelemetryHandler) Handle(ctx context.Context, baselineAlerts ts.BaselineAlerts, analysis *ts.Analysis, fixedAlertNumbers []uint32) {
	ctx = appctx.With(ctx,
		kvp.Bool("NewSuggestedFixTelemetryHandler", true),
		analysis.RepositoryID.AsKVP(),
		analysis.ID.AsKVP(),
	)

	appctx.Logger(ctx).Info(fmt.Sprintf("found %d fixed alerts", len(fixedAlertNumbers)))

	if len(baselineAlerts) == 0 {
		appctx.Logger(ctx).Info("early return in SuggestedFixTelemetryHandler: no baseline alerts")
		return
	}
	baseAnalysis := baselineAlerts[0].Analysis

	// enqueue SuggestedFixesTelemetry for fixed alerts
	if len(fixedAlertNumbers) > 0 {
		tj := &jobs.SuggestedFixTelemetry{
			RepositoryID:          analysis.RepositoryID,
			AnalysisID:            analysis.ID,
			BaselineID:            baseAnalysis.ID,
			FixedPhysicalAlertIDs: []ts.PhysicalAlertID{}, // TODO: remove, not used
			FixedAlertNumbers:     fixedAlertNumbers,
			NewPhysicalAlertIDs:   []ts.PhysicalAlertID{}, // TODO: remove, not used
			Ref:                   analysis.Ref,
			CurrentCommitOid:      analysis.CommitOid,
			BaselineCommitOid:     baseAnalysis.CommitOid,
		}
		appctx.Logger(ctx).Info("enqueued SuggestedFixTelemetry job")

		now := time.Now()
		jobTime := now.Add(30 * time.Minute)
		_, err := s.jobs.PerformLaterAt(ctx, tj, jobTime)
		if err != nil {
			appctx.Logger(ctx).Error("Error when enqueue SuggestedFixesTelemetry job", kvp.Err(err))
			return
		}
	}
}
