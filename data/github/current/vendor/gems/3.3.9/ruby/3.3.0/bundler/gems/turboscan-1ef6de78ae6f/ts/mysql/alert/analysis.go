package alert

import (
	"context"
	"database/sql"
	"strings"

	"github.com/github/go-stats"

	"golang.org/x/exp/slices"

	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/mysql"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"

	"github.com/google/go-cmp/cmp"
	"golang.org/x/exp/maps"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/transforms"
)

// FindAnalyses returns the (potentially empty) set of Analyses that satisfy the
// filter.
func (s *Service) FindAnalyses(ctx context.Context, filter ts.AnalysisFilter, opt *ts.FindOptions) ([]ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	return mysql.FindWithAnalysisFilter(ctx, filter, db, opt)
}

func selectWithout[T any](db *gorm.DB, omit ...string) string {
	var t T
	fields := db.NewScope(t).GetStructFields()
	columns := transforms.FilterMap(fields, func(v *gorm.StructField) (string, bool) {
		return v.DBName, v.IsNormal && !v.IsIgnored && !slices.Contains(omit, v.DBName)
	})
	return strings.Join(columns, ", ")
}

func (s *Service) FindFilesExtracted(ctx context.Context, repoID ts.RepositoryEID, analysisIDs []ts.AnalysisID) ([]*ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	return gormext.FindInBatchesOf[*ts.Analysis](ctx, 10, analysisIDs, func(start, end int) *gorm.DB {
		filter := ts.AnalysisFilter{
			RepositoryID:    repoID,
			AnalysisIDs:     analysisIDs[start:end],
			IncludeOutdated: true,
		}

		return mysql.ApplyAnalysisFilter(filter, db).Preload("AnalysisExtractedFiles", func(inner *gorm.DB) *gorm.DB {
			if flipper.HasOmitFilesNotExtracted(ctx, repoID) {
				// the promising-looking inner.Omit method only works with Create or Update operations
				return inner.Select(selectWithout[ts.AnalysisExtractedFiles](db, "files_not_extracted"))
			}
			return inner
		})
	})
}

func (s *Service) AnalysisRulesCounts(ctx context.Context, repoID ts.RepositoryEID, analysisRules []*ts.AnalysisRule) ([]*ts.LatestAnalysisAnalysisRule, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	if len(analysisRules) == 0 {
		return nil, nil
	}

	ruleIDs := transforms.MapUnique(analysisRules, func(ar *ts.AnalysisRule) ts.RuleID { return ar.RuleID })

	// rules is a global table and cannot be joined in the query below
	rules, err := gormext.FindInBatchesOf[*ts.Rule](ctx, 500, ruleIDs, func(start, end int) *gorm.DB {
		return db.Table("ts_rules").
			Where("id IN (?)", ruleIDs[start:end]).
			Select("id, sarif_identifier")
	})
	if err != nil {
		return nil, errors.Wrap(err, "failed to load rules")
	}

	ruleIdentifiers := map[ts.RuleID]string{}
	for _, rule := range rules {
		ruleIdentifiers[rule.ID] = rule.SarifIdentifier
	}

	analysisRulesByID := transforms.IndexBy(analysisRules, func(ar *ts.AnalysisRule) uint64 { return ar.ID })

	out, err := gormext.FindInBatchesOf[*ts.LatestAnalysisAnalysisRule](ctx, 250, analysisRules, func(start, end int) *gorm.DB {
		ids := transforms.Map(analysisRules[start:end], func(a *ts.AnalysisRule) uint64 { return a.ID })

		appctx.Logger(ctx).
			WithFields(
				repoID.AsKVP(),
				kvp.Uint64s("gh.turboscan.analysis_ids", transforms.MapUnique(analysisRules[start:end], func(a *ts.AnalysisRule) uint64 { return uint64(a.AnalysisID) })),
				kvp.Uint64s("gh.turboscan.rule_ids", transforms.MapUnique(analysisRules[start:end], func(a *ts.AnalysisRule) uint64 { return uint64(a.RuleID) })),
				kvp.Uint64s("gh.turboscan.analysis_rule_ids", ids),
			).
			Info("attempting to fetch counts")

		return db.Table("ts_analysis_rules").
			Where("ts_analysis_rules.repository_id = ? AND ts_analysis_rules.id IN (?)", repoID, ids).
			Joins(`LEFT OUTER JOIN ts_physical_alerts
			ON  ts_physical_alerts.repository_id = ts_analysis_rules.repository_id
			AND ts_physical_alerts.analysis_id = ts_analysis_rules.analysis_id
			AND ts_physical_alerts.rule_id = ts_analysis_rules.rule_id
			AND NOT ts_physical_alerts.is_fixed
		`).
			Group("ts_analysis_rules.id").
			Select(`
			ts_analysis_rules.id AS 'id',
			COUNT(ts_physical_alerts.id) AS 'results'
		`)
	})
	if err != nil {
		return nil, errors.Wrap(err, "failed to load alert counts")
	}

	for _, row := range out {
		ar := analysisRulesByID[row.ID]
		row.AnalysisRule = ar
		row.SarifIdentifier = ruleIdentifiers[ar.RuleID]
	}

	return out, nil
}

type deliveryRow struct {
	DeliveryID  ts.DeliveryID
	AnalysisKey ts.AnalysisKey
	Environment ts.AnalysisEnv
}

func addDeliveryMessages(ctx context.Context, db *gorm.DB, repoID ts.RepositoryEID, ref []byte, analyses []*ts.LatestAnalysis) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db = otelgorm.SetSpanToGorm(ctx, db)

	if len(analyses) == 0 {
		return nil
	}

	// we are only interested in deliveries after the last known good one
	// this is here to improve the performance in the case where things have not been broken for long,
	// saving us having to do many group checks using environment (a json column).
	minDeliveryID := analyses[0].DeliveryID
	for _, analysis := range analyses[1:] {
		if analysis.DeliveryID < minDeliveryID {
			minDeliveryID = analysis.DeliveryID
		}
	}

	analysisKeys := transforms.MapUnique(analyses, func(a *ts.LatestAnalysis) ts.AnalysisKey {
		return a.AnalysisKey
	})

	return gormext.Chunks(ctx, 50, len(analysisKeys), func(start, end int) error {
		var rows []deliveryRow

		err := db.
			Table("ts_deliveries").
			Where("id >= ? AND repository_id = ? AND ref = ? AND analysis_key IN (?) AND failed", minDeliveryID, repoID, ref, analysisKeys[start:end]).
			Group("analysis_key, environment").
			Select("max(id) AS 'delivery_id', analysis_key, environment").
			Find(&rows).
			Error

		if err != nil {
			return err
		}

		if len(rows) == 0 {
			return nil
		}

		byDeliveryID := transforms.IndexBy(rows, func(row deliveryRow) ts.DeliveryID {
			return row.DeliveryID
		})

		var messages []*ts.AnalysisMessage

		err = db.Model(ts.AnalysisMessage{}).
			Where("repository_id = ? AND analysis_id IS NULL AND delivery_id IN (?)", repoID, maps.Keys(byDeliveryID)).
			Find(&messages).
			Error
		if err != nil {
			return errors.Wrap(err, "failed to fetch deliveries")
		}

		analysesByKey := transforms.GroupBy(analyses, func(a *ts.LatestAnalysis) ts.AnalysisKey {
			return a.AnalysisKey
		})

		for _, message := range messages {
			if row, ok := byDeliveryID[message.DeliveryID]; ok {
				if matches, ok := analysesByKey[row.AnalysisKey]; ok {
					for _, analysis := range matches {
						if message.DeliveryID >= analysis.DeliveryID && cmp.Equal(analysis.Environment, row.Environment) {
							analysis.AnalysisMessages = append(analysis.AnalysisMessages, message)
						}
					}
				}
			}
		}

		return nil
	})
}

func (s *Service) AnalysisIDs(ctx context.Context, repoID ts.RepositoryEID, filter ts.AnalysisFilter) ([]ts.AnalysisID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)
	var analysisIDs []ts.AnalysisID

	filter.RepositoryID = repoID

	err := mysql.
		ApplyAnalysisFilter(filter, db.Model(ts.Analysis{})).
		Group("configuration_hash_bytes").
		Pluck("MAX(id)", &analysisIDs).
		Error
	if err != nil {
		return nil, errors.Wrap(err, "failed to find latest analysis IDs")
	}

	return analysisIDs, nil
}

func latestAnalysisIDsForRef(db *gorm.DB, repoID ts.RepositoryEID, filter ts.LatestAnalysisFilter) ([]ts.AnalysisID, error) {
	var mostRecent []struct {
		ConfigurationHashBytes string
		ID                     ts.AnalysisID
	}

	// first find the most recent analyses
	// this won't include failed analyses that have occurred since
	if err := mysql.ApplyAnalysisFilter(ts.AnalysisFilter{
		RepositoryID:    repoID,
		ExcludeFork:     true,
		State:           ts.AnalysisStateFilterMostRecent,
		ToolIDs:         filter.ToolIDs,
		IncludeOutdated: true,
		Refs:            [][]byte{filter.Ref},
		DeliveryOrigin:  filter.DeliveryOrigin,
	}, db.Model(ts.Analysis{})).
		Table("ts_analyses").
		Select("configuration_hash_bytes, id").
		Find(&mostRecent).Error; err != nil {
		return nil, errors.Wrap(err, "failed to find most recent analysis IDs")
	}

	latest := make(map[string]ts.AnalysisID, len(mostRecent))
	for _, v := range mostRecent {
		latest[v.ConfigurationHashBytes] = v.ID
	}

	// now we need to look for any analyses that are not most recent but are still interesting
	// to the tool status page
	var noBaseline []struct {
		ConfigurationHashBytes string
		ID                     ts.AnalysisID
	}

	// this query can find any analyses that are complete but not necessarily most recent
	// we will need to make sure the query can use idx_analyses_on_repo_id_baseline_id
	// otherwise it will be painfully slow
	query := mysql.ApplyAnalysisFilter(ts.AnalysisFilter{
		RepositoryID:    repoID,
		ExcludeFork:     true,
		State:           ts.AnalysisStateFilterComplete,
		ToolIDs:         filter.ToolIDs,
		IncludeOutdated: true,
		Refs:            [][]byte{filter.Ref},
		DeliveryOrigin:  filter.DeliveryOrigin,
	}, db.Model(ts.Analysis{})).
		Table("ts_analyses").
		Group("configuration_hash_bytes").
		Select("configuration_hash_bytes, MAX(id) AS id")

	// by including NULL here we can find analyses on configurations that have never
	// been successful
	if err := query.Where("baseline_id IS NULL AND (? OR configuration_hash_bytes NOT IN (?))", len(latest) == 0, maps.Keys(latest)).Find(&noBaseline).Error; err != nil {
		return nil, errors.Wrap(err, "failed to find latest analysis IDs with no baseline")
	}

	var otherCompleted []struct {
		ConfigurationHashBytes string
		ID                     ts.AnalysisID
	}

	if len(latest) > 0 {
		// find any failed analyses with a most recent analysis as their baseline
		// this has to be run separately to the IS NULL query or the index wont kick in
		if err := query.Where("baseline_id IN (?)", maps.Values(latest)).Find(&otherCompleted).Error; err != nil {
			return nil, errors.Wrap(err, "failed to find latest analysis IDs")
		}
	}

	// now we include any analyses newer than most recent ones as they may contain
	// messages that explain the failure.
	// We also include analyses for configurations that never had a most_recent analysis.
	for _, v := range append(noBaseline, otherCompleted...) {
		// do not resurrect very old failed analyses with a null baseline
		latest[v.ConfigurationHashBytes] = max(latest[v.ConfigurationHashBytes], v.ID)
	}

	return maps.Values(latest), nil
}

func excludeOutdatedAnalyses(db *gorm.DB, repoID ts.RepositoryEID, analysisIDs []ts.AnalysisID) ([]ts.AnalysisID, error) {
	if len(analysisIDs) == 0 {
		return nil, nil
	}

	var rows []struct {
		ts.MatchingParameters
		ID         ts.AnalysisID
		IsOutdated bool
	}

	if err := db.Table("ts_analyses").
		Where(`ts_analyses.id IN (?) AND ts_analyses.repository_id = ?`, analysisIDs, repoID).
		Joins("INNER JOIN ts_tools ON ts_tools.id = ts_analyses.tool_id").
		Order("id ASC").
		Select(`ts_tools.canonical_name AS tool,
ts_analyses.repository_id AS repository_id,
ts_analyses.analysis_category AS category,
ts_analyses.is_outdated AND ts_analyses.most_recent AS is_outdated,
ts_analyses.id AS id`).
		Find(&rows).
		Error; err != nil {
		return nil, errors.Wrap(err, "failed to fetch analysis IDs")
	}

	grouped := make(map[ts.MatchingParameters]ts.AnalysisID, len(rows))

	for _, row := range rows {
		mp := ts.MatchingParams(row.Tool, row.RepositoryID, row.Category)
		if row.IsOutdated {
			delete(grouped, mp)
			continue
		}
		grouped[mp] = row.ID
	}

	return maps.Values(grouped), nil
}

func (s *Service) LatestAnalysisIDsForRef(ctx context.Context, repoID ts.RepositoryEID, filter ts.LatestAnalysisFilter) ([]ts.AnalysisID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	var analysisIDs = filter.AnalysisIDs

	if len(filter.AnalysisIDs) == 0 {
		var err error
		analysisIDs, err = latestAnalysisIDsForRef(db, repoID, filter)
		if err != nil {
			return nil, errors.Wrap(err, "failed to fetch analysis IDs for ref")
		}
	}

	if len(analysisIDs) == 0 {
		return nil, nil
	}

	analysisIDs, err := excludeOutdatedAnalyses(db, repoID, analysisIDs)

	if err != nil {
		return nil, errors.Wrap(err, "failed to fetch analysis IDs")
	}

	const threshold = 100

	// remove any misbehaving tools
	// if a tool has this many categories then we cant load it anyway
	if len(analysisIDs) > threshold {
		var toolsWithTooManyConfigurations []uint64
		if err := db.Table("ts_analyses").
			Where("id IN (?) AND repository_id = ?", analysisIDs, repoID).
			Group("tool_id").
			Having("count(*) > ?", threshold).
			Pluck("tool_id", &toolsWithTooManyConfigurations).
			Error; err != nil {
			return nil, errors.Wrap(err, "failed to find misbehaving tools")
		}

		if len(toolsWithTooManyConfigurations) > 0 {
			appctx.Stats(ctx).Counter("latest_analysis.misbehaving_tools", stats.Tags{}, 1)
			appctx.Logger(ctx).Warn("removed misbehaving tools", kvp.Uint64s("tool_ids", toolsWithTooManyConfigurations), repoID.AsKVP())
			if err := db.
				Table("ts_analyses").
				Where("id IN (?) AND repository_id = ?", analysisIDs, repoID).
				Where("tool_id NOT IN (?)", toolsWithTooManyConfigurations).
				Pluck("id", &analysisIDs).
				Error; err != nil {
				return nil, errors.Wrap(err, "failed to exclude misbehaving tools")
			}
		}
	}

	return analysisIDs, nil
}

// LatestAnalysesForRef returns analyses for ref, including analyses which contained errors.
// If the caller already has a set of analysis IDs they are interested in they can pass them in the filter to avoid looking up the
// latest analyses for each category.
func (s *Service) LatestAnalysesForRef(ctx context.Context, repoID ts.RepositoryEID, filter ts.LatestAnalysisFilter, withProcessedSARIF bool) ([]*ts.LatestAnalysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	analysisIDs, err := s.LatestAnalysisIDsForRef(ctx, repoID, filter)
	if err != nil {
		return nil, errors.Wrap(err, "failed to filter ids")
	}

	if len(analysisIDs) == 0 {
		return nil, nil
	}

	// when was the first analysis for this analysis' category?
	categoryCreatedAt := db.Table("ts_analyses _first").
		Where("_first.configuration_hash_bytes = ts_analyses.configuration_hash_bytes AND _first.repository_id = ?", repoID).
		Select("min(_first.created_at)").
		SubQuery()

	tipsQuery := db.Table("ts_analyses tips").
		Select("1").
		Where("tips.configuration_hash_bytes = ts_analyses.configuration_hash_bytes").
		Where("tips.repository_id = ts_analyses.repository_id").
		Where("tips.unique_most_recent").
		SubQuery()

	var analyses []*ts.LatestAnalysis

	if err := gormext.Chunks(ctx, 50, len(analysisIDs), func(start, end int) error {
		chunkAnalysisIDs := analysisIDs[start:end]

		var rows []*ts.LatestAnalysis

		query := db.
			Table("ts_analyses").
			Where("id IN (?) AND repository_id = ?", chunkAnalysisIDs, repoID).
			Preload("ToolVersion.Tool").
			Preload("AnalysisMessages", func(db *gorm.DB) *gorm.DB {
				return db.Where("repository_id = ?", repoID)
			}).
			Preload("AnalysisQuerySuites", func(db *gorm.DB) *gorm.DB {
				return db.Where("repository_id = ?", repoID)
			}).
			Order("ts_analyses.created_at DESC, ts_analyses.id DESC").
			Select("*, ? AS 'min_created_at', EXISTS(?) AS 'has_most_recent'", categoryCreatedAt, tipsQuery)

		// Processed SARIFs are not available yet on GHES, so we'll need to preload additional information from MySQL.
		if !withProcessedSARIF {
			query = query.
				Preload("AnalysisRules", func(db *gorm.DB) *gorm.DB {
					return db.Table("ts_analysis_rules").Where("repository_id = ?", repoID)
				}).
				Preload("AnalysisToolVersions", func(db *gorm.DB) *gorm.DB {
					return db.Where("ts_analysis_tool_versions.repository_id = ?", repoID)
				}).
				Preload("AnalysisToolVersions.ToolVersion")
		}

		err = query.Find(&rows).Error
		if err != nil {
			return err
		}

		analyses = append(analyses, rows...)

		return nil
	}); err != nil {
		return analyses, err
	}

	if err := addDeliveryMessages(ctx, db, repoID, filter.Ref, analyses); err != nil {
		return analyses, err
	}

	return analyses, nil
}

func (s *Service) AreAnalysesDeletable(ctx context.Context, repoID ts.RepositoryEID, analyses []ts.Analysis) (map[ts.AnalysisID]bool, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	return s.areAnalysesDeletable(ctx, db, repoID, analyses)
}

func (s *Service) areAnalysesDeletable(ctx context.Context, db *gorm.DB, repoID ts.RepositoryEID, analyses []ts.Analysis) (map[ts.AnalysisID]bool, error) {
	out := make(map[ts.AnalysisID]bool)
	pendingCheck := []ts.AnalysisID{}

	for _, analysis := range analyses {
		if analysis.RepositoryID != repoID {
			return nil, errors.New("areAnalysesDeletable - repositoryID mismatch")
		}
		out[analysis.ID] = true
		// If an analysis is most recent it is always deletable and it doesnt need further checking
		if !analysis.MostRecent {
			pendingCheck = append(pendingCheck, analysis.ID)
		}
	}

	// An analysis is not deletable if it is the baseline of other analysis
	notDeletableIDs := []ts.AnalysisID{}
	err := db.Model(&ts.Analysis{}).Where("repository_id = ? AND baseline_id IN (?) AND analysis_complete = true AND soft_deleted_at IS NULL", repoID, pendingCheck).
		Group("baseline_id"). // We are doing the group by to prevent fetching an arbitrary amount of analyses
		Pluck("baseline_id", &notDeletableIDs).Error
	if err != nil {
		return nil, errors.Wrap(err, "areAnalysesDeletable – could not retrieve successors")
	}

	for _, notDeletableID := range notDeletableIDs {
		out[notDeletableID] = false
	}

	return out, nil
}

// SoftDeleteAnalysis marks an analysis as deleted
func (s *Service) SoftDeleteAnalysis(ctx context.Context, repoID ts.RepositoryEID, analysisID ts.AnalysisID, permitConfigDeletion bool) (*ts.Analysis, error) {

	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	analysis := &ts.Analysis{}
	baseline := &ts.Analysis{}

	// retrieve analysis
	err := db.Where("id = ? AND soft_deleted_at IS NULL AND repository_id = ?", analysisID, repoID).First(analysis).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ts.ErrAnalysisNotFound
		}
		return nil, errors.Wrap(err, "failed to delete analysis – could not retrieve analysis ")
	}

	// confirm analysis is deletable
	deletable, err := s.areAnalysesDeletable(ctx, db, repoID, []ts.Analysis{*analysis})
	if err != nil {
		return nil, errors.Wrap(err, "failed to delete analyis - could not determine if it is deletable")
	}
	if !deletable[analysisID] {
		return nil, ts.ErrAnalysisIsNotDeletable
	}

	// retrieve baseline
	if analysis.BaselineID != nil {
		err = db.Where("id = ? AND soft_deleted_at IS NULL AND repository_id = ?", analysis.BaselineID, repoID).
			Where("cleaned = false AND analysis_complete = true").First(baseline).Error
		if err != nil && !gorm.IsRecordNotFoundError(err) {
			return nil, errors.Wrap(err, "failed to delete analysis – could not retrieve baseline ")
		}
	}

	// if the user is ok with deleting the entire configuration or the analysis is old, we don't bother recreating the alerts
	if permitConfigDeletion || !analysis.MostRecent {
		err = s.commitAnalysisDeletion(ctx, analysis, baseline)
		if err != nil {
			appctx.Logger(ctx).Info("successfully soft deleted analysis",
				analysis.RepositoryID.AsKVP(),
				kvp.Bool("gh.turboscan.confirm_config_delete", permitConfigDeletion),
				kvp.Uint64("gh.turboscan.analysis_id", uint64(analysis.ID)),
			)
		}
		if baseline.ID == 0 {
			return nil, err
		}
		return baseline, err
	}

	if baseline.ID == 0 {
		// If we couldn't find a suitable baseline, we consider the analysis to be the first of its configuration
		return nil, ts.ErrMissingDeletionConfirmation
	}

	// if the baseline hasn't been archived we don't need to modify any alerts
	if baseline.ArchivalState == ts.ArchivalState_LIVE {
		err = s.commitAnalysisDeletion(ctx, analysis, baseline)
		return baseline, err
	}

	// in order to reset the state to the baseline, we need to find all events corresponding to the deleted analysis and undo them
	var events []*ts.TimelineEvent
	err = db.Where("repository_id = ? AND analysis_id = ?", repoID, analysisID).Find(&events).Error
	if err != nil {
		return nil, errors.Wrap(err, "failed to fetch timeline events")
	}
	newAlertIDs := map[ts.LogicalAlertID]struct{}{}
	fixedAlertIDs := map[ts.LogicalAlertID]struct{}{}
	reappearedAlertIDs := map[ts.LogicalAlertID]struct{}{}
	for _, e := range events {
		switch e.EventType {
		case ts.TimelineEventTypeAlertAppearedInBranch, ts.TimelineEventTypeAlertCreated:
			newAlertIDs[e.LogicalAlertID] = struct{}{}
		case ts.TimelineEventTypeAlertClosedBecameFixed:
			fixedAlertIDs[e.LogicalAlertID] = struct{}{}
		case ts.TimelineEventTypeAlertReappeared:
			reappearedAlertIDs[e.LogicalAlertID] = struct{}{}
		case ts.TimelineEventTypeAlertClosedBecameOutdated, ts.TimelineEventTypeAlertResolvedByUser, ts.TimelineEventTypeAlertReopenedByUser, ts.TimelineEventTypeAlertDeletedByUser, ts.TimelineEventTypeUnknown:
			continue
		default:
			continue
		}
	}

	// We copy and update all relevant physical alerts to the baseline
	now := sqltime.Now()
	newBaselineAlerts := []*ts.PhysicalAlert{}
	currentAlerts := []*ts.PhysicalAlert{}
	err = db.Model(ts.PhysicalAlert{}).Where("repository_id = ? AND analysis_id = ?", repoID, analysisID).Find(&currentAlerts).Error
	if err != nil {
		return nil, errors.Wrap(err, "failed to fetch physical alerts")
	}
	for _, a := range currentAlerts {
		// ignore all alerts that were introduced in the deleted analysis
		if _, ok := newAlertIDs[a.LogicalAlertID]; ok {
			continue
		}
		cp := a.DeepCopy()
		cp.ID = 0
		for _, rl := range cp.RelatedLocations {
			rl.ID = 0
		}
		cp.LastStateChangeAt = now
		cp.AnalysisID = baseline.ID

		// if the alert was fixed in the deleted analysis, we need to reopen it
		if _, ok := fixedAlertIDs[a.LogicalAlertID]; ok {
			cp.LastSeenAnalysisID = nil
		}
		// if the alert was reopened in the deleted analysis, we need to fix it again
		if _, ok := reappearedAlertIDs[a.LogicalAlertID]; ok {
			// Since AnalysisDeletion is a niche use-case, we can approximate this to the analysis before the baseline.
			// Computing the correct LastSeenAnalysisID would be very fairly expensive otherwise.
			cp.LastSeenAnalysisID = baseline.BaselineID
		}
		newBaselineAlerts = append(newBaselineAlerts, cp)
	}

	err = s.writePhysicalAlerts(ctx, newBaselineAlerts, 100, repoID)
	if err != nil {
		return nil, errors.Wrap(err, "failed to write physical alerts")
	}

	err = s.commitAnalysisDeletion(ctx, analysis, baseline)
	if err != nil {
		// if the baseline is populated we return it as a reference
		appctx.Logger(ctx).Info("successfully soft deleted analysis and set new baseline",
			analysis.RepositoryID.AsKVP(),
			kvp.Uint64("gh.turboscan.analysis_id", uint64(analysis.ID)),
			kvp.Uint64("gh.turboscan.baseline_id", uint64(baseline.ID)),
		)
	}
	return baseline, err
}

func (s *Service) commitAnalysisDeletion(ctx context.Context, analysis, baseline *ts.Analysis) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// reload analysis to make sure it's still deletable
		err := tx.Where("id = ? AND soft_deleted_at IS NULL AND repository_id = ?", analysis.ID, analysis.RepositoryID).First(analysis).Error
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ts.ErrAnalysisNotFound
			}
			return errors.Wrap(err, "failed to delete analysis – could not retrieve analysis ")
		}
		mostRecent := analysis.MostRecent
		if !mostRecent {
			deletable, err := s.areAnalysesDeletable(ctx, tx, analysis.RepositoryID, []ts.Analysis{*analysis})
			if err != nil {
				return errors.Wrap(err, "failed to delete analyis - could not determine if it is deletable")
			}
			if !deletable[analysis.ID] {
				return ts.ErrAnalysisIsNotDeletable
			}
		}
		analysis.MarkAsDeleted()
		err = tx.Save(&analysis).Error
		if err != nil {
			return errors.Wrap(err, "failed to delete analysis - could not update analysis")
		}

		if baseline.ID != 0 && mostRecent {
			baseline.MostRecent = true
			baseline.ArchivalState = ts.ArchivalState_LIVE
			err = tx.Save(&baseline).Error
			if err != nil {
				return errors.Wrap(err, "failed to delete analysis - could not update baseline")
			}
		}
		return nil
	})
}

// CountAnalyses returns the number of Analyses that satisfy the filter
func (s *Service) CountAnalyses(ctx context.Context, filter ts.AnalysisFilter) (uint64, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	var count uint64
	err := mysql.ApplyAnalysisFilter(filter, db.Model(&ts.Analysis{})).Count(&count).Error
	if err != nil {
		return 0, errors.Wrap(err, "retrieving analyses count has failed")
	}

	return count, nil
}

// ProcessErrors returns the process error messages associated with the given analyses
func (s *Service) ProcessErrors(ctx context.Context, repoID ts.RepositoryEID, aIDs []ts.AnalysisID) (map[ts.AnalysisID][]*ts.ProcessError, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	if len(aIDs) == 0 {
		// Exit early if no id is given
		return make(map[ts.AnalysisID][]*ts.ProcessError), nil
	}

	// Fetch errors for each analysis
	var processErrors []*ts.ProcessError
	err := db.Where("repository_id = ?", repoID).
		Where("analysis_id in (?)", aIDs).
		Find(&processErrors).
		Error

	if err != nil {
		return nil, err
	}

	grouped := transforms.GroupBy(processErrors, func(err *ts.ProcessError) ts.AnalysisID {
		return *err.AnalysisID
	})

	return grouped, nil
}

// AnalysisExists returns whether an analysis exists that matches the specified filter.
func (s *Service) AnalysisExists(ctx context.Context, filter ts.AnalysisFilter) (bool, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	query := mysql.ApplyAnalysisFilter(filter, db.Model(&ts.Analysis{}))

	var id []ts.AnalysisID
	err := query.Select("id").Limit(1).Scan(&id).Error
	if err != nil {
		return false, errors.Wrap(err, "fetching analyses has failed")
	}
	return len(id) > 0, nil
}

// LatestAnalysisCreatedAt returns the most recent created_at date that matches the specified filter.
func (s *Service) LatestAnalysisCreatedAt(ctx context.Context, filter ts.AnalysisFilter) (*sqltime.Time, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	query := mysql.ApplyAnalysisFilter(filter, db.Model(&ts.Analysis{}))

	var createdAt sqltime.Time
	err := query.Order("ts_analyses.created_at DESC").Select("ts_analyses.created_at").Limit(1).Row().Scan(&createdAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &createdAt, nil
}

func (s *Service) SetAnalysisArchivalUrl(ctx context.Context, analysisID ts.AnalysisID, url string) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	err := db.Model(&ts.Analysis{}).
		Where("id = ?", analysisID).
		Update("archival_data_url", url).
		Error
	if err != nil {
		return errors.Wrap(err, "updating analysis archival url has failed")
	}
	return nil
}
