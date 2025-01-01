// Package analysis handles interactions with analyses and alerts.
package analysis

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/go-stats"

	"github.com/github/turboscan/ts/mysql"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/github/turboscan/ts/transforms"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"

	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

// Service handles interactions with Alerts.
type Service struct {
	db *gorm.DB
}

// NewService creates an alert service with the given parameters
func NewService(db *gorm.DB) *Service {
	as := &Service{
		db: db,
	}
	return as
}

// CreateAnalysis saves the analysis without any alerts.
func (s *Service) CreateAnalysis(ctx context.Context, analysis *ts.Analysis, alternateToolIDs ...ts.ToolID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	baseline, mostRecent, err := getBaselineAnalysis(ctx, db, analysis, alternateToolIDs...)
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error(
			"error finding baseline analysis",
			analysis.RepositoryID.AsKVP(),
			analysis.Tool.CanonicalName.AsKVP(),
			kvp.String("gh.git.ref", string(analysis.Ref)),
			analysis.Category.AsKVP(),
		)

		return errors.Wrap(err, "error finding baseline for analysis")
	}

	baselineExists := baseline != nil
	if analysis.IsOutdated {
		// Avoid updating a configuration as outdated if the baseline (previous configuration) is missing or already marked as outdated - these are unexpected usecases.
		if !baselineExists || baseline.IsOutdated {
			appctx.Logger(ctx).Info("attempted to mark an analyis as outdated with no baseline or outdated baseline",
				analysis.RepositoryID.AsKVP(),
				analysis.Tool.CanonicalName.AsKVP(),
				kvp.String("gh.git.ref", string(analysis.Ref)),
				analysis.Category.AsKVP())
			// If failed analyses exist we want to delete them.
			nFailed, err := softDeleteFailedAnalyses(ctx, db, analysis, baseline)
			if err != nil {
				appctx.Logger(ctx).WithError(err).Error(
					"error removing previously failed analyses",
					analysis.RepositoryID.AsKVP(),
					analysis.Tool.CanonicalName.AsKVP(),
					kvp.String("gh.git.ref", string(analysis.Ref)),
					analysis.Category.AsKVP(),
				)
				return errors.Wrap(err, "error removing previously failed analyses")
			}

			appctx.Stats(ctx).Counter("analyses.remove_failed_analyses", stats.Tags{}, int64(nFailed))

			// in all cases where there is no baseline analysis or the baseline is outdated already, we should fail the delivery.
			if baselineExists && baseline.IsOutdated {
				return ts.NewUnrecoverableDeliveryError(analysis.RepositoryID, analysis.SarifID, "Cannot create an analysis that's outdated with an already outdated baseline")
			} else {
				return ts.NewUnrecoverableDeliveryError(analysis.RepositoryID, analysis.SarifID, "Cannot create an outdated analysis with no baseline analysis")
			}
		}
	}

	if baselineExists {
		analysis.BaselineID = &baseline.ID
	}

	err = db.Omit("Tool").Create(&analysis).Error
	if err != nil {
		return err
	}

	// Set whether this should become the most recent analysis. We do it AFTER
	// saving the entry in the DB to preserve the invariant that we have
	// at most one mostRecent per configuration.
	analysis.MostRecent = mostRecent
	return nil
}

// CommitAnalysis marks the analysis as complete, and optionally as the most recent analysis.
func (s *Service) CommitAnalysis(ctx context.Context, a *ts.Analysis) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	a.MostRecent = !a.Failed && a.MostRecent
	a.AnalysisComplete = true

	baselineID := a.BaselineID
	mostRecent := a.MostRecent

	now := gorm.NowFunc()

	// Save everything except the most recent column
	// we will update that atomically below
	if err := db.Omit("MostRecent").Save(a).Error; err != nil {
		return errors.Wrapf(err, "failed to save analysis (%d)", a.ID)
	}

	if mostRecent {
		targets := []ts.AnalysisID{a.ID}
		if baselineID != nil {
			targets = append(targets, *baselineID)
		}

		// attempt to set most_recent
		// if the baseline has changed since we started the idx_analyses_most_recent unique key will
		// ensure that this update fails
		err := db.Exec(`UPDATE ts_analyses SET most_recent=(id = ?), updated_at=? WHERE id IN (?)`, a.ID, now, targets).Error
		if err != nil {
			if baselineID == nil {
				return errors.Wrapf(err, "could not update most_recent analysis from <no baseline> to %d", a.ID)
			}
			return errors.Wrapf(err, "could not update most_recent analysis from %d to %d", *baselineID, a.ID)
		}
	}

	appctx.Logger(ctx).Info("Successfully committed analysis",
		kvp.Uint64("gh.turboscan.new_analysis", uint64(a.ID)), kvp.Bool("gh.turboscan.most_recent", mostRecent))
	return nil
}

func getBaselineAnalysis(ctx context.Context, db *gorm.DB, analysis *ts.Analysis, alternateToolIDs ...ts.ToolID) (*ts.Analysis, bool, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db = otelgorm.SetSpanToGorm(ctx, db)

	opt := &ts.FindOptions{
		Preloads: []string{"Tool", "ToolVersion"},
	}

	filter := ts.AnalysisFilter{
		RepositoryID:     analysis.RepositoryID,
		Refs:             [][]byte{analysis.Ref},
		ToolIDs:          transforms.Unique(append(alternateToolIDs, analysis.ToolID)),
		AnalysisCategory: &analysis.Category,
		State:            ts.AnalysisStateFilterMostRecent,
		IncludeOutdated:  true,
	}

	tips, err := mysql.FindWithAnalysisFilter(ctx, filter, db, opt)
	if err != nil {
		return nil, false, err
	}

	// We can only accept at most one active tip for the specified conditions
	if len(tips) > 1 {
		return nil, false, errors.Errorf("found multiple active tips for analysis %v", analysis.ID)
	}
	// Single baseline
	if len(tips) == 1 {
		baseline := tips[0]
		// This checks that the analysis is not older than the baseline rather
		// than that it is _newer_. This means that processing the same delivery
		// again will unnecessarily update the most recent analysis. Some tests
		// depend on this behaviour, so we need to be careful about changing it.
		mostRecent := baseline.BuildStartedAt == nil || analysis.BuildStartedAt == nil || !analysis.BuildStartedAt.Before(baseline.BuildStartedAt.Time)
		return &baseline, mostRecent, nil
	}

	return nil, true, nil
}

// softDeleteFailedAnalyses deletes any failed analyses since the last successful one (if it exists), and returns the number of failed analyses
func softDeleteFailedAnalyses(ctx context.Context, db *gorm.DB, analysis *ts.Analysis, baseline *ts.Analysis, alternateToolIDs ...ts.ToolID) (int, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db = otelgorm.SetSpanToGorm(ctx, db)

	// we only need to remove failed analyses created after the baseline, if there is one.
	var createdAfter *time.Time
	if baseline != nil {
		createdAfter = &baseline.CreatedAt.Time
	}

	filter := ts.AnalysisFilter{
		RepositoryID:     analysis.RepositoryID,
		Refs:             [][]byte{analysis.Ref},
		ToolIDs:          transforms.Unique(append(alternateToolIDs, analysis.ToolID)),
		AnalysisCategory: &analysis.Category,
		State:            ts.AnalysisStateFilterAll,
		IncludeDeleted:   false,
		IncludeOutdated:  false,
		CreatedAfter:     createdAfter,
	}

	var failedAnalyses []*ts.Analysis
	err := mysql.ApplyAnalysisFilter(filter, db.Table("ts_analyses")).
		Where("ts_analyses.failed = 1 AND NOT ts_analyses.most_recent").
		Find(&failedAnalyses).Error

	// Sharded mode errors with no rows
	if errors.Is(err, sql.ErrNoRows) {
		return 0, nil
	}

	for i := 0; i < len(failedAnalyses); i++ {
		a := failedAnalyses[i]
		a.MarkAsDeleted()

		err := db.Save(a).Error
		if err != nil {
			return i, err
		}
	}

	return len(failedAnalyses), err
}
