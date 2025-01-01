package jobs

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/codediff"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/pkg/errors"
)

var LOGGER_PREFIX = "ProcessAutofixUsageStats"
var STAT_PREFIX = "process_autofix_usage_stats"

type ProcessAutofixUsageStats struct {
	RepositoryID    ts.RepositoryEID
	Refs            [][]byte
	BeforeCommitOid ts.Sha
	AfterCommitOid  ts.Sha
}

var _ aqueduct.EnqueableJob = (*ProcessAutofixUsageStats)(nil)

func (p ProcessAutofixUsageStats) Perform(ctx context.Context, s *aqueduct.TSServices) error {
	if s == nil || s.SuggestedFixes == nil {
		return errors.New("missing required services")
	}

	// We don't have autofix in GHES,
	// todo: we shouldn't enqueue job in GHES, lets fix it there as well
	if s.IsEnterpriseEnv {
		return nil
	}

	ctx = appctx.With(ctx,
		p.RepositoryID.AsKVP(),
		kvp.String("gh.turboscan.after_commit_oid", string(p.AfterCommitOid)),
		kvp.String("gh.turboscan.before_commit_oid", string(p.BeforeCommitOid)),
		kvp.Any("gh.turboscan.refs", p.Refs),
	)

	sfas, err := s.SuggestedFixes.GetAllSuggestedFixAlertsByRefs(ctx, p.RepositoryID, p.Refs)
	if err != nil {
		appctx.Logger(ctx).Error(LOGGER_PREFIX,
			kvp.Err(errors.Wrap(err, "Failed to load suggested fix alerts")),
		)
		return err
	}

	appctx.Logger(ctx).Info(LOGGER_PREFIX,
		kvp.String("message", "Started telemetry computation."),
		kvp.Any("sfas", sfas),
	)

	appctx.Stats(ctx).Counter(STAT_PREFIX+".sfas_to_process", nil, int64(len(sfas)))

	beforeCommitDownload := s.SuggestedFixes.DownloadFunc(p.RepositoryID, p.BeforeCommitOid)
	afterCommitDownload := s.SuggestedFixes.DownloadFunc(p.RepositoryID, p.AfterCommitOid)

	for index, sfa := range sfas {
		// todo: use AutofixUsageEvent_SuggestionFileStats when ready, see https://github.com/github/code-scanning/issues/17844
		var fs []*tshydro.AutofixUsageEvent_SuggestionFileStats
		if sfa.SuggestedFix == nil {
			appctx.Stats(ctx).Counter(STAT_PREFIX+".nil_suggested_Fix", stats.Tags{"state": sfa.State.String()}, 1)
			continue
		}

		var totalAdded, totalAddedChanges int32
		for _, f := range sfa.SuggestedFix.Files {
			beforeCommitFile, err := beforeCommitDownload(ctx, f.FilePath)
			if err != nil {
				appctx.Logger(ctx).Error(LOGGER_PREFIX,
					kvp.Err(errors.Wrap(err, "Cannot download file using before_commit_oid.")),
					kvp.String("file_path", f.FilePath),
					kvp.String("before_commit_oid", string(p.BeforeCommitOid)),
				)
				appctx.Stats(ctx).Counter(STAT_PREFIX+".not_processed", stats.Tags{"error": "before_commit_file_download"}, int64(len(sfas)-index))
				return err
			}
			afterCommitFile, err := afterCommitDownload(ctx, f.FilePath)
			if err != nil {
				appctx.Logger(ctx).Error("SuggestedFixesTelemetry",
					kvp.Err(errors.Wrap(err, "Cannot download head file.")),
					kvp.String("file_path", f.FilePath),
					kvp.String("sha", string(p.AfterCommitOid)),
				)
				appctx.Stats(ctx).Counter(STAT_PREFIX+".not_processed", stats.Tags{"error": "after_commit_file_download"}, int64(len(sfas)-index))
				return err
			}

			h := codediff.DiffFromFiles(f.FilePath, codediff.FileContent(beforeCommitFile), codediff.FileContent(afterCommitFile))
			suggestion := codediff.DiffFromContent(codediff.DiffContent(f.DiffContent))
			stats := codediff.CompareDiffs(suggestion, h)

			// todo: how do you know if file changes were never applied between the commits, i.e. the changes are totally unrelated, is that a valid case here? because we are loading all SFAs for given ref regardless of the commits

			fs = append(fs, &tshydro.AutofixUsageEvent_SuggestionFileStats{
				Filepath:            f.FilePath,
				TotalAdded:          int32(stats.TotalAdded),
				TotalAddedChanges:   int32(stats.TotalAddedChanges),
				TotalRemoved:        int32(stats.TotalRemoved),
				TotalRemovedChanges: int32(stats.TotalRemovedChanges),
				PercentChanged:      stats.PercentChanged(),
			})
			totalAdded += int32(stats.TotalAdded)
			totalAddedChanges += int32(stats.TotalAddedChanges)
			appctx.Logger(ctx).Info(LOGGER_PREFIX,
				kvp.String("message", "Computed diff comparison."),
				kvp.String("file_path", f.FilePath),
				kvp.Int("total_added", stats.TotalAdded),
				kvp.Int("total_added_changes", stats.TotalAddedChanges),
				kvp.Int("total_removed", stats.TotalRemoved),
				kvp.Int("total_removed_changes", stats.TotalRemovedChanges),
				kvp.Float32("percent_changed", stats.PercentChanged()),
			)
		}

		err = s.SuggestedFixes.AutofixUsagePublisher.AutofixUsageEvent(ctx, &tshydro.AutofixUsageEvent{
			RepositoryId:    uint64(p.RepositoryID),
			Source:          tshydro.AutofixUsageEvent_AUTOFIX_USAGE_CODE_SCANNING,
			BeforeCommitOid: string(p.BeforeCommitOid),
			AfterCommitOid:  string(p.AfterCommitOid),
			AutofixId:       uint64(sfa.ID),
			FileStats:       fs,
		})
		if err != nil {
			appctx.Logger(ctx).Error(LOGGER_PREFIX, kvp.Err(err))
			appctx.Stats(ctx).Counter(STAT_PREFIX+".not_processed", stats.Tags{"error": "emit_event"}, int64(len(sfas)-index))
			return err
		}

		// we shouldn't update the suggestionUsage and syncUpdate from here yet
	}

	return nil
}

func (p ProcessAutofixUsageStats) GetRepositoryID() *ts.RepositoryEID {
	return &p.RepositoryID
}

func (p ProcessAutofixUsageStats) Name() string {
	return "ProcessAutofixUsageStats"
}

func (p ProcessAutofixUsageStats) Queue() string {
	return "turboscan-process-autofix-usage-stats"
}

func (p ProcessAutofixUsageStats) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.DefaultRetryBackoffFunc
}
