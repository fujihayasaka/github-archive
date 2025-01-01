package jobs

import (
	"context"
	"fmt"

	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/codediff"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

type SuggestedFixTelemetry struct {
	RepositoryID ts.RepositoryEID
	AnalysisID   ts.AnalysisID
	BaselineID   ts.AnalysisID

	FixedPhysicalAlertIDs []ts.PhysicalAlertID
	FixedAlertNumbers     []uint32
	NewPhysicalAlertIDs   []ts.PhysicalAlertID

	Ref               ts.Ref
	CurrentCommitOid  ts.Sha
	BaselineCommitOid ts.Sha
}

var _ aqueduct.EnqueableJob = (*SuggestedFixTelemetry)(nil)

func (j SuggestedFixTelemetry) Perform(ctx context.Context, s *aqueduct.TSServices) error {

	if s == nil || s.SuggestedFixes == nil {
		return errors.New("missing required services")
	}

	// We don't have autofix in GHES
	if s.IsEnterpriseEnv {
		return nil
	}

	ctx = appctx.With(ctx,
		j.RepositoryID.AsKVP(),
		j.AnalysisID.AsKVP(),
		kvp.Uint64("gh.turboscan.baseline_analysis_id", uint64(j.BaselineID)),
		kvp.String("gh.turboscan.current_sha", string(j.CurrentCommitOid)),
		kvp.String("gh.turboscan.baseline_sha", string(j.BaselineCommitOid)),
		kvp.Any("fixed_alerts_numbers", j.FixedAlertNumbers),
	)

	refs := [][]byte{[]byte(j.Ref)}
	sfas, err := s.SuggestedFixes.DbService.GetSuggestedFixAlerts(ctx, j.RepositoryID, j.FixedAlertNumbers, refs)
	if err != nil {
		appctx.Logger(ctx).Error("SuggestedFixesTelemetry",
			kvp.Err(errors.Wrap(err, "Cannot find suggested fix for the alert.")),
		)
		return err
	}

	appctx.Logger(ctx).Info("SuggestedFixesTelemetry",
		kvp.String("message", "Started telemetry computation."),
		kvp.Any("sfas", sfas),
	)

	// Posible cases for not finding the SFA of a given alert:
	// - the alert never got an autofix (this jobs runs for every posible fixed alerts, even for third party tools and public repos where autofix is not supported)
	// - race condition, this job run before gh/gh could request the generation of an autofix in the CreateCodeScanningAnnotations job
	// The race condition is quite improbable, so we assume that if there was no SFA, is the first case, and it is correct
	switch {
	case len(sfas) == 0:
		appctx.Logger(ctx).Info("SuggestedFixesTelemetry", kvp.String("message", "No suggested fixes found for the alerts."))
		appctx.Stats(ctx).Counter("suggested_fix_telemetry.sfas_len", stats.Tags{"result": "zero"}, 1)
		return nil
	case len(sfas) != len(j.FixedAlertNumbers):
		// Missmatchs are possible:
		// main branch has alert 1
		// pr open, introduced alert 2
		// autofix is generated for alert 2
		// push to the PR, alert 1 and 2 are fixed
		// only one SFA is found (alert 2)
		appctx.Logger(ctx).Info("SuggestedFixesTelemetry",
			kvp.String("message", "Mismatch between the number of alerts and the number of suggested fixes."),
			kvp.Int("alerts", len(j.FixedAlertNumbers)),
			kvp.Int("sfas", len(sfas)),
			kvp.Int("mismatch", len(j.FixedAlertNumbers)-len(sfas)),
		)
		appctx.Stats(ctx).Counter("suggested_fix_telemetry.sfas_len", stats.Tags{"result": "mismatch"}, 1)
	default:
		appctx.Stats(ctx).Counter("suggested_fix_telemetry.sfas_len", stats.Tags{"result": "same"}, 1)
	}

	appctx.Stats(ctx).Counter("suggested_fix_telemetry.fixes_to_process", nil, int64(len(sfas)))

	baseDownload := s.SuggestedFixes.DownloadFunc(j.RepositoryID, j.BaselineCommitOid)
	headDownload := s.SuggestedFixes.DownloadFunc(j.RepositoryID, j.CurrentCommitOid)

	for index, sfa := range sfas {
		var fs []*tshydro.AutofixFixedAlertEvent_SuggestionFileStats
		if sfa.SuggestedFix == nil {
			appctx.Stats(ctx).Counter("suggested_fix_telemetry.nil_suggested_Fix", stats.Tags{"state": sfa.State.String()}, 1)
			continue
		}
		var totalAdded, totalAddedChanges int32
		for _, f := range sfa.SuggestedFix.Files {
			baseFile, err := baseDownload(ctx, f.FilePath)
			if err != nil {
				appctx.Logger(ctx).Error("SuggestedFixesTelemetry",
					kvp.Err(errors.Wrap(err, "Cannot download base file.")),
					kvp.String("file_path", f.FilePath),
					kvp.String("sha", string(j.BaselineCommitOid)),
				)
				appctx.Stats(ctx).Counter("suggested_fix_telemetry.not_processed", stats.Tags{"error": "base_file_download"}, int64(len(sfas)-index))
				return err
			}
			headFile, err := headDownload(ctx, f.FilePath)
			if err != nil {
				appctx.Logger(ctx).Error("SuggestedFixesTelemetry",
					kvp.Err(errors.Wrap(err, "Cannot download head file.")),
					kvp.String("file_path", f.FilePath),
					kvp.String("sha", string(j.CurrentCommitOid)),
				)
				appctx.Stats(ctx).Counter("suggested_fix_telemetry.not_processed", stats.Tags{"error": "head_file_download"}, int64(len(sfas)-index))
				return err
			}

			h := codediff.DiffFromFiles(f.FilePath, codediff.FileContent(baseFile), codediff.FileContent(headFile))
			suggestion := codediff.DiffFromContent(codediff.DiffContent(f.DiffContent))
			stats := codediff.CompareDiffs(suggestion, h)

			fs = append(fs, &tshydro.AutofixFixedAlertEvent_SuggestionFileStats{
				Filepath:            f.FilePath,
				TotalAdded:          int32(stats.TotalAdded),
				TotalAddedChanges:   int32(stats.TotalAddedChanges),
				TotalRemoved:        int32(stats.TotalRemoved),
				TotalRemovedChanges: int32(stats.TotalRemovedChanges),
				PercentChanged:      stats.PercentChanged(),
			})
			totalAdded += int32(stats.TotalAdded)
			totalAddedChanges += int32(stats.TotalAddedChanges)
			appctx.Logger(ctx).Info("SuggestedFixesTelemetry",
				kvp.String("message", "Computed diff comparison."),
				kvp.String("file_path", f.FilePath),
				kvp.Int("total_added", stats.TotalAdded),
				kvp.Int("total_added_changes", stats.TotalAddedChanges),
				kvp.Int("total_removed", stats.TotalRemoved),
				kvp.Int("total_removed_changes", stats.TotalRemovedChanges),
				kvp.Float32("percent_changed", stats.PercentChanged()),
			)
		}

		err = s.SuggestedFixes.FixedAlertPublisher.AutofixFixedAlertEvent(ctx, &tshydro.AutofixFixedAlertEvent{
			RepositoryId:        uint64(j.RepositoryID),
			AnalysisId:          uint64(j.AnalysisID),
			BaselineAnalysisId:  uint64(j.BaselineID),
			SuggestedFixAlertId: uint64(sfa.ID),
			FileStats:           fs,
		})
		if err != nil {
			appctx.Logger(ctx).Error("SuggestedFixesTelemetry", kvp.Err(err))
			appctx.Stats(ctx).Counter("suggested_fix_telemetry.not_processed", stats.Tags{"error": "emit_event"}, int64(len(sfas)-index))
			return err
		}

		suggestionUsage, err := s.SuggestedFixes.UpdateSuggestionUsage(ctx, &sfa, totalAdded, totalAddedChanges)
		if err != nil {
			appctx.Logger(ctx).Error("SuggestedFixesTelemetry", kvp.Err(err))
			appctx.Stats(ctx).Counter("suggested_fix_telemetry.not_processed", stats.Tags{"error": "update_sfa"}, int64(len(sfas)-index))
			return err
		}

		payload := map[string]string{
			"repository_id": fmt.Sprintf("%d", j.RepositoryID),
		}
		s.SuggestedFixes.SyncUpdate(ctx, "suggested-fix-telemetry", payload, j.RepositoryID, 0, sfa.LogicalAlertNumber)

		appctx.Stats(ctx).Counter("suggested_fix_telemetry.processed", nil, 1)
		appctx.Logger(ctx).Info("SuggestedFixesTelemetry",
			kvp.String("message", "Updated suggestion usage."),
			sfa.ID.AsKVP(),
			kvp.Float64("suggestion_usage", suggestionUsage),
		)
	}

	return nil
}

func (j SuggestedFixTelemetry) GetRepositoryID() *ts.RepositoryEID {
	return &j.RepositoryID
}

func (j SuggestedFixTelemetry) Name() string {
	return "SuggestedFixesTelemetry"
}

func (j SuggestedFixTelemetry) Queue() string {
	return "turboscan-suggested-fixes-telemetry"
}

func (j SuggestedFixTelemetry) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.DefaultRetryBackoffFunc
}
