// Package alert deals with the database
package alert

import (
	"bytes"
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/experiment"
	"github.com/github/turboscan/ts/flipper"
	"golang.org/x/exp/maps"

	"github.com/github/turboscan/ts/glob"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/mysql"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/github/turboscan/ts/transforms"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/alerts"
	"github.com/github/turboscan/ts/mysql/gormbulk"
	"github.com/github/turboscan/ts/mysql/scopes"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/sequence"

	"github.com/SamuelTissot/sqltime"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

// Service handles interactions with Alerts.
type Service struct {
	db              *gorm.DB
	sequenceCreator sequence.CreatorFunc
}

func TestService(db *gorm.DB) *Service {
	return NewService(db, sequence.NewMemorySequenceCreator())
}

// NewService creates an alert service with the given parameters
func NewService(db *gorm.DB, seqCreator sequence.CreatorFunc) *Service {
	as := &Service{
		db:              db,
		sequenceCreator: seqCreator,
	}
	return as
}

func (s *Service) AlertId(ctx context.Context, repoID ts.RepositoryEID, number uint32) (ts.LogicalAlertID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	var result struct{ Id ts.LogicalAlertID }
	err := db.Table("ts_logical_alerts").Where("repository_id = ? and number = ?", repoID, number).Select("id").Scan(&result).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return 0, ts.ErrAlertNotFound
		}
		return 0, errors.Wrap(err, "fetching alert id has failed")
	}

	return result.Id, nil
}

// LogicalAlerts returns a set of alerts based on their numbers. It does not load any physical alerts or populate any derived fields.
func (s *Service) LogicalAlerts(ctx context.Context, repoID ts.RepositoryEID, numbers []uint32, preloads []string) ([]*ts.LogicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	alerts := []*ts.LogicalAlert{}
	query := db.Table("ts_logical_alerts").
		Where("repository_id = ? and number IN (?)", repoID, numbers)

	for _, preload := range preloads {
		query = query.Preload(preload)
	}
	err := query.Find(&alerts).Error
	if err != nil {
		return nil, errors.Wrap(err, "fetching logical alerts has failed")
	}
	return alerts, nil
}

// WriteSecurityCampaignAlerts writes a new security campaign alert for each logical alert in the given repository.
// The logical alert IDs are returned.
func (s *Service) WriteSecurityCampaignAlerts(ctx context.Context, repoNumbers []ts.RepoNumber,
	securityCampaignID ts.SecurityCampaignEID) ([]ts.LogicalAlertID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	query := db.Table("ts_logical_alerts")
	for _, repoNumber := range repoNumbers {
		query = query.Or("repository_id = ? and number = ?", repoNumber.RepositoryID, repoNumber.Number)
	}

	securityCampaignAlerts := []*ts.SecurityCampaignAlert{}
	err := query.Select("id as logical_alert_id, repository_id").Find(&securityCampaignAlerts).Error

	if err != nil {
		return nil, errors.Wrap(err, "fetching logical alert has failed")
	}

	if len(securityCampaignAlerts) == 0 {
		return nil, nil
	}

	for _, alert := range securityCampaignAlerts {
		alert.SecurityCampaignID = securityCampaignID
	}

	securityCampaignAlertsScope := func(db *gorm.DB, alert *ts.SecurityCampaignAlert) *gorm.DB {
		return db.Where("security_campaign_id = ? and logical_alert_id = ? and repository_id = ?", alert.SecurityCampaignID, alert.LogicalAlertID, alert.RepositoryID)
	}
	logicalAlertIDs := transforms.Map(securityCampaignAlerts, func(alert *ts.SecurityCampaignAlert) ts.LogicalAlertID {
		return alert.LogicalAlertID
	})

	err = gormbulk.InsertIgnore(ctx, securityCampaignAlertsScope, &gormbulk.InsertOptions[ts.SecurityCampaignAlert]{
		DB:        s.db,
		Objects:   securityCampaignAlerts,
		ChunkSize: 100,
	})

	return logicalAlertIDs, err
}

// DeleteSecurityCampaignAlerts writes a new security campaign alert for each logical alert in the given repository.
// The logical alert IDs are returned.
func (s *Service) DeleteSecurityCampaignAlerts(ctx context.Context, securityCampaignID ts.SecurityCampaignEID) ([]ts.LogicalAlertID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	logger := appctx.Logger(ctx).WithFields(
		kvp.Uint64("gh.turboscan.security_campaign_id", uint64(securityCampaignID)),
	)

	securityCampaignAlerts := []*ts.SecurityCampaignAlert{}
	err := db.Where("security_campaign_id = ?", securityCampaignID).Find(&securityCampaignAlerts).Error
	if err != nil {
		return nil, errors.Wrap(err, "fetching security campaigns alerts to delete has failed")
	}

	if len(securityCampaignAlerts) == 0 {
		logger.Info("No security campaign alerts to delete")
		return nil, nil
	}

	idsToDelete := []uint64{}
	logicalAlertIDs := []ts.LogicalAlertID{}
	logicalAlertIDsAsUint := []uint64{}
	for _, alert := range securityCampaignAlerts {
		idsToDelete = append(idsToDelete, uint64(alert.ID))
		logicalAlertIDs = append(logicalAlertIDs, alert.LogicalAlertID)
		logicalAlertIDsAsUint = append(logicalAlertIDsAsUint, uint64(alert.LogicalAlertID))
	}
	logger = appctx.Logger(ctx).WithFields(
		kvp.Uint64s("gh.turboscan.security_campaign_alert_ids", idsToDelete),
		kvp.Uint64s("gh.turboscan.logical_alert_ids", logicalAlertIDsAsUint),
	)

	logger.Info("Deleting security campaign alerts")

	err = db.Table("ts_security_campaign_alerts").
		Where("id IN (?)", idsToDelete).Delete("").Error
	if err != nil {
		return nil, errors.Wrap(err, "error deleting security campaigns alerts")
	}

	logger.Info("Finished deleting security campaign alerts")

	return logicalAlertIDs, err
}

// filterPreload removes a preload and returns true if it is required.
func filterPreload(preloads []string, target string) ([]string, bool) {
	var required bool
	result := make([]string, 0, len(preloads))

	for _, preload := range preloads {
		if preload == target {
			continue
		}
		// mark the preload as necessary if a dependent record is required
		if strings.HasPrefix(preload+".", target) {
			required = true
		}
		result = append(result, preload)
	}
	return result, required || len(preloads) != len(result)
}

// AlertsWithCursor returns all Alerts for the given repository while providing cursor support.
func (s *Service) AlertsWithCursor(ctx context.Context, repoID ts.RepositoryEID, alertFilter ts.AlertFilter,
	analysisFilter ts.AnalysisFilter, order proto.AlertSortOrder, options *ts.FindOptions) (SearchResult[*ts.LogicalAlert], error) {

	sort := ExtractAlertExpressionSorters(order)

	return Fetch(ctx, sort, options, &alertFilter, func(filter *ts.AlertFilter, options *ts.FindOptions) ([]*ts.LogicalAlert, error) {
		return s.Alerts(ctx, repoID, *filter, analysisFilter, options)
	})
}

func alertsBaseQuery(db *gorm.DB, repoID ts.RepositoryEID, analysisIDs []ts.AnalysisID, alertFilter ts.AlertFilter, options *ts.FindOptions) *gorm.DB {
	logicalAlertsTableWithHint := "ts_logical_alerts"
	if alertFilter.Numbers == nil {
		logicalAlertsTableWithHint = "ts_logical_alerts USE INDEX (PRIMARY)"
	}

	query := db.Table(logicalAlertsTableWithHint).
		Joins("JOIN ts_physical_alerts ON ts_physical_alerts.logical_alert_id = ts_logical_alerts.id AND ts_physical_alerts.repository_id = ts_logical_alerts.repository_id AND ts_physical_alerts.repository_id = ?", repoID).
		Where("ts_logical_alerts.repository_id = ?", repoID).
		Where("ts_physical_alerts.analysis_id IN (?)", analysisIDs)

	query = strictInFilter(query, "ts_logical_alerts.id in (?)", alertFilter.IDs)
	query = strictInFilter(query, "ts_logical_alerts.number in (?)", alertFilter.Numbers)
	query = strictInFilter(query, "ts_logical_alerts.sarif_identifier in (?)", alertFilter.SarifIdentifiers)

	if len(alertFilter.ExcludedSarifIdentifiers) > 0 {
		query = query.Not("ts_logical_alerts.sarif_identifier in (?)", alertFilter.ExcludedSarifIdentifiers)
	}

	if len(alertFilter.SeverityLevels) > 0 {
		query = addMultiSeverityFilters(alertFilter.SeverityLevels, false, query)
	}

	if len(alertFilter.ExcludedSeverityLevels) > 0 {
		query = addMultiSeverityFilters(alertFilter.ExcludedSeverityLevels, true, query)
	}

	if len(alertFilter.Resolutions) > 0 {
		query = query.Where("ts_logical_alerts.resolution in (?)", alertFilter.Resolutions)
	}

	if len(alertFilter.ExcludedResolutions) > 0 {
		query = query.Not("ts_logical_alerts.resolution in (?)", alertFilter.ExcludedResolutions)
	}

	switch alertFilter.Classification {
	case proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_UNCLASSIFIED:
		query = query.Where("JSON_LENGTH(ts_logical_alerts.file_classification) = 0")
	case proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_ANY_CLASSIFICATION:
		query = query.Where("JSON_LENGTH(ts_logical_alerts.file_classification) > 0")
	case proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_NO_FILTER:
		// pass
	}

	switch alertFilter.State {
	case proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN:
		// Having the be min be 0 means that at least one associated physical alert is not fixed.
		query = query.Having("min(ts_physical_alerts.is_fixed) = 0 AND max(ts_logical_alerts.resolution) = ?", ts.AlertResolutionNone)
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED:
		// Having the min be 1 true means that all associated physical alerts are fixed.
		query = query.Having("min(ts_physical_alerts.is_fixed) = 1 OR max(ts_logical_alerts.resolution) <> ?", ts.AlertResolutionNone)
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_RESOLVED:
		query = query.Having("max(ts_logical_alerts.resolution) <> ?", ts.AlertResolutionNone)
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_FIXED:
		// Having the min be 1 true means that all associated physical alerts are fixed.
		query = query.Having("min(ts_physical_alerts.is_fixed) = 1")
	case proto.AlertStateFilter_ALERT_STATE_FILTER_ALL, proto.AlertStateFilter_ALERT_STATE_FILTER_NONE:
		// pass
	}

	if len(alertFilter.FilePaths) > 0 {
		query = query.Where("ts_logical_alerts.file_path REGEXP ?", glob.GlobsToRegexes(alertFilter.FilePaths))
	}

	if len(alertFilter.LanguageFilePaths) > 0 {
		query = query.Where("ts_logical_alerts.file_path REGEXP ?", glob.GlobsToRegexes(alertFilter.LanguageFilePaths))
	}

	// We group all refs for the given logical alert, so that we can reason about
	// the refs in which it is fixed or not
	query = query.Group("ts_logical_alerts.id, ts_logical_alerts.number, ts_logical_alerts.weight, ts_logical_alerts.updated_at, ts_logical_alerts.created_at")

	if len(alertFilter.Cursor) > 0 {
		for _, cursorFilter := range alertFilter.Cursor {
			query = query.Having(cursorFilter.Expression, cursorFilter.Value)
		}
	}

	if options != nil {
		if options.Pagination != nil {
			query = options.Pagination.Apply(query)
		}
		if options.SortBy != "" {
			query = query.Order(options.SortBy)
		}
	}

	return query
}

// Alerts returns all Alerts for the given repository that meet the given conditions
// NOTE: this is currently implemented with a query that requires the db to look at
// all logical alerts for a given repo. This might prove too slow in practice, and we
// might need to change it. See https://github.com/github/dsp-code-scanning/issues/390 for details.
// Using options to preload PhysicalAlerts will only load the most recently created PhysicalAlert for each logical alert.
//
// filter: Filter conditions to apply (e.g., refs, rules)
// options: FindOptions to apply (e.g. paging, preloads)
func (s *Service) Alerts(ctx context.Context, repoID ts.RepositoryEID, alertFilter ts.AlertFilter, analysisFilter ts.AnalysisFilter, options *ts.FindOptions) ([]*ts.LogicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	// Fetch the corresponding analysis IDs first
	analysisIDs := []ts.AnalysisID{}
	start := time.Now()
	query := mysql.ApplyAnalysisFilter(analysisFilter, db.Table("ts_analyses")).Limit(10000).Pluck("id", &analysisIDs)
	if err := query.Error; err != nil {
		return nil, errors.Wrap(err, "fetching analyses has failed")
	}
	appctx.Stats(ctx).DistributionMs("alerts.query", stats.Tags{"query": "get-analysis-ids"}, time.Since(start))
	appctx.Stats(ctx).Distribution("alerts.query.fetched_analyses", stats.Tags{}, float64(len(analysisIDs)))

	start = time.Now()
	var logicalAlertsIDs []ts.LogicalAlertID
	err := alertsBaseQuery(db, repoID, analysisIDs, alertFilter, options).Pluck("ts_logical_alerts.id", &logicalAlertsIDs).Error
	if err != nil {
		return nil, err
	}
	appctx.Stats(ctx).DistributionMs("alerts.query", stats.Tags{"query": "get-logical-alert-ids"}, time.Since(start))

	start = time.Now()
	var logicalAlerts []*ts.LogicalAlert
	loadQuery := db.Table("ts_logical_alerts USE INDEX (PRIMARY)").
		Joins("JOIN ts_physical_alerts USE INDEX (`idx_physical_alerts_on_repo_id_analysis_id_logical_alert_id`) ON ts_physical_alerts.logical_alert_id = ts_logical_alerts.id AND ts_physical_alerts.repository_id = ts_logical_alerts.repository_id AND ts_physical_alerts.repository_id = ? AND ts_physical_alerts.analysis_id IN (?)", repoID, analysisIDs).
		Where("ts_logical_alerts.id IN (?)", logicalAlertsIDs).
		Group("ts_physical_alerts.logical_alert_id").
		Select("ts_logical_alerts.*, MIN(ts_physical_alerts.is_fixed) AS is_fixed, MAX(COALESCE(resolved_at, ts_physical_alerts.last_state_change_at)) as last_state_change_at, GROUP_CONCAT(last_seen_analysis_id) AS last_seen_analysis_ids")

	// copy options so that we can modify the preloads without mutating the original struct
	optionsCopy := *options
	// Pagination was applied when fetching alert IDs, so we don't need to apply it again here
	optionsCopy.Pagination = nil
	var useCanonicalPreload bool
	optionsCopy.Preloads, useCanonicalPreload = filterPreload(optionsCopy.Preloads, "PhysicalAlerts")
	// only load the canonical instance of each PhysicalAlert for the current configuration
	if useCanonicalPreload {
		loadQuery = loadQuery.Preload("PhysicalAlerts", buildCanonicalPhysicalAlertsPreload(repoID, analysisFilter, alertFilter))
	}
	// apply the find options _after_ the modified PhysicalAlerts preload has been defined,
	// otherwise gorm will use the standard preload method when a dependant record is defined
	// (e.g: PhysicalAlerts.Analysis).
	loadQuery = optionsCopy.Apply(loadQuery)

	err = loadQuery.Find(&logicalAlerts).Error
	if err != nil {
		return nil, errors.Wrap(err, "finding logical alerts has failed")
	}
	appctx.Stats(ctx).DistributionMs("alerts.query", stats.Tags{"query": "load-logical-alerts"}, time.Since(start))

	// Compute the LastObservedFixAt date for each fixed alert
	baselines := []ts.AnalysisID{}
	idsByAlert := make(map[ts.LogicalAlertID][]ts.AnalysisID)
	for _, alert := range logicalAlerts {
		if alert.IsFixed == nil || !*alert.IsFixed {
			continue
		}
		if alert.LastSeenAnalysisIDs == "" {
			continue
		}
		rawIDs := strings.Split(alert.LastSeenAnalysisIDs, ",")
		for _, raw := range rawIDs {
			id, parseErr := strconv.ParseUint(raw, 10, 64)
			if parseErr == nil {
				idsByAlert[alert.ID] = append(idsByAlert[alert.ID], ts.AnalysisID(id))
				baselines = append(baselines, ts.AnalysisID(id))
			}
		}
	}
	if len(baselines) == 0 {
		return logicalAlerts, nil
	}
	start = time.Now()
	var fixDates []struct {
		BaselineID   ts.AnalysisID
		MaxCreatedAt *sqltime.Time
	}
	err = db.Table("ts_analyses").
		Select("baseline_id, MAX(created_at) as max_created_at").
		Where("repository_id = ?", repoID).
		Where("baseline_id IN (?)", baselines).
		Where("analysis_complete = TRUE AND failed = FALSE AND soft_deleted_at IS NULL").
		Group("baseline_id").
		Scan(&fixDates).Error
	if err != nil {
		return nil, err
	}
	fixedMap := make(map[ts.AnalysisID]*sqltime.Time)
	for _, row := range fixDates {
		fixedMap[row.BaselineID] = row.MaxCreatedAt
	}
	for _, alert := range logicalAlerts {
		for _, baseline := range idsByAlert[alert.ID] {
			fixedAt := alert.GetFixedAt()
			if fixedAt == nil || fixedAt.Before(fixedMap[baseline].Time) {
				alert.LastObservedFixAt = fixedMap[baseline]
			}
		}
	}
	appctx.Stats(ctx).DistributionMs("alerts.query", stats.Tags{"query": "get-fixed-at-dates"}, time.Since(start))
	return logicalAlerts, nil
}

// buildCanonicalPhysicalAlertsPreload creates a preload function for LogicalAlert->PhysicalAlerts which will load the
// most recently created physical alert for each logical alert with respect to the filters.
// Usage:
//
//	query.Model(&ts.LogicalAlert{}).Preload("PhysicalAlerts", buildCanonicalPhysicalAlertsPreload(...))
func buildCanonicalPhysicalAlertsPreload(repoID ts.RepositoryEID, analysisFilter ts.AnalysisFilter, alertFilter ts.AlertFilter) func(*gorm.DB) *gorm.DB {
	return func(db *gorm.DB) *gorm.DB {
		canonicalAlerts := buildPhysicalAlertsQuery(db.Model(&ts.PhysicalAlert{}), repoID, analysisFilter, alertFilter).
			// put the physical alerts into their logical alert groups and order them
			Select("ts_physical_alerts.id, ts_physical_alerts.repository_id, ts_physical_alerts.logical_alert_id AS group_id, RANK() OVER(PARTITION BY ts_physical_alerts.logical_alert_id ORDER BY ts_physical_alerts.created_at DESC, ts_physical_alerts.id DESC) AS idx").
			Where("ts_physical_alerts.repository_id = ?", repoID)

		physicalAlerts := db.Model(&ts.PhysicalAlert{}).
			Where("ts_physical_alerts.repository_id = ?", repoID).
			// only select the first (canonical) physical alert from each group
			Joins("INNER JOIN ? AS _canonical_alerts ON ts_physical_alerts.repository_id = _canonical_alerts.repository_id AND ts_physical_alerts.id = _canonical_alerts.id AND ts_physical_alerts.logical_alert_id = _canonical_alerts.group_id AND _canonical_alerts.idx = 1", canonicalAlerts.SubQuery())

		return physicalAlerts
	}
}

// Count returns the number of alerts that match the filter
func (s *Service) Count(ctx context.Context, repoID ts.RepositoryEID, alertFilter ts.AlertFilter, analysisFilter ts.AnalysisFilter) (uint64, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	return experiment.Do(ctx, "counts", flipper.WithCodeScanningCountsExperiment(ctx, repoID), experiment.Options[uint64]{
		Candidate: func() (uint64, error) {
			return experimentalCount(ctx, db, repoID, alertFilter, analysisFilter)
		},
		Control: func() (uint64, error) {
			return originalCount(ctx, db, repoID, alertFilter, analysisFilter)
		},
	})
}

func originalCount(ctx context.Context, db *gorm.DB, repoID ts.RepositoryEID, alertFilter ts.AlertFilter, analysisFilter ts.AnalysisFilter) (uint64, error) {
	var count uint64
	start := time.Now()
	err := buildLogicalAlertsBaseQuery(db, repoID, analysisFilter, alertFilter).Select("1").Count(&count).Error
	appctx.Stats(ctx).DistributionMs("counts.query", stats.Tags{"query": "get-counts"}, time.Since(start))
	return count, errors.Wrap(err, "retrieving alert counts has failed")
}

func experimentalCount(ctx context.Context, db *gorm.DB, repoID ts.RepositoryEID, alertFilter ts.AlertFilter, analysisFilter ts.AnalysisFilter) (uint64, error) {
	var count uint64

	// Fetch the corresponding analysis IDs first
	analysisIDs := []ts.AnalysisID{}
	start := time.Now()
	query := mysql.ApplyAnalysisFilter(analysisFilter, db.Table("ts_analyses")).Limit(10000).Pluck("id", &analysisIDs)
	if err := query.Error; err != nil {
		return count, errors.Wrap(err, "fetching analyses has failed")
	}
	appctx.Stats(ctx).DistributionMs("counts.query", stats.Tags{"query": "get-analysis-ids"}, time.Since(start))
	appctx.Stats(ctx).Distribution("counts.query.fetched_analyses", stats.Tags{}, float64(len(analysisIDs)))

	start = time.Now()
	err := alertsBaseQuery(db, repoID, analysisIDs, alertFilter, nil).Select("1").Count(&count).Error
	appctx.Stats(ctx).DistributionMs("counts.query", stats.Tags{"query": "get-counts-experimental"}, time.Since(start))
	return count, errors.Wrap(err, "retrieving experimental alert counts has failed")
}

// CountByTool returns the number of alerts that match the filter, grouped by tool.
func (s *Service) CountByTool(ctx context.Context, repo ts.RepositoryEID, alertFilter ts.AlertFilter, analysisFilter ts.AnalysisFilter) (map[ts.ToolName]uint64, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	var counts []struct {
		ToolID ts.ToolID
		Alerts uint64
	}

	alertTools := buildLogicalAlertsQuery(db, repo, analysisFilter, alertFilter).
		Select("ts_logical_alerts.id, ts_analyses.tool_id").
		Group("ts_logical_alerts.id, ts_analyses.tool_id").
		SubQuery()

	err := db.
		Raw(`SELECT alert_tools.tool_id, COUNT(alert_tools.id) AS alerts FROM ? AS alert_tools GROUP BY alert_tools.tool_id`, alertTools).
		Find(&counts).
		Error
	if err != nil {
		return nil, errors.Wrap(err, "counting alerts by tool has failed")
	}

	mappedCounts := map[ts.ToolID]uint64{}

	for _, count := range counts {
		mappedCounts[count.ToolID] = count.Alerts
	}

	var tools []ts.Tool
	if err := db.Scopes(scopes.ToolsUsed(repo)).Find(&tools).Error; err != nil {
		return nil, errors.Wrap(err, "fetching tools has failed")
	}

	result := map[ts.ToolName]uint64{}

	for _, tool := range tools {
		result[tool.CanonicalName] += mappedCounts[tool.ID]
	}

	return result, nil
}

// strictInFilter will create a query that returns no results if items is non-nil but has length 0
func strictInFilter[T any](db *gorm.DB, clause string, items []T) *gorm.DB {
	if items == nil {
		return db
	}
	if len(items) == 0 {
		// force the query to match nothing
		return db.Where("1 = 0")
	}
	return db.Where(clause, items)
}

func buildLogicalAlertsBaseQuery(db *gorm.DB, repoID ts.RepositoryEID, analysisFilter ts.AnalysisFilter, filter ts.AlertFilter) *gorm.DB {
	logicalAlertsTableWithHint := "ts_logical_alerts"
	if filter.Numbers == nil {
		logicalAlertsTableWithHint = "ts_logical_alerts USE INDEX (PRIMARY)"
	}

	query := db.Table(logicalAlertsTableWithHint).
		// VITESS: repository_id MUST be a JOIN to the FROM table; we add the additional constant filter on repository_id to improve performance
		Joins("JOIN ts_physical_alerts ON ts_physical_alerts.logical_alert_id = ts_logical_alerts.id AND ts_physical_alerts.repository_id = ts_logical_alerts.repository_id AND ts_physical_alerts.repository_id = ?", repoID).
		Joins("JOIN ts_analyses ON ts_analyses.id = ts_physical_alerts.analysis_id AND ts_analyses.repository_id = ts_logical_alerts.repository_id").
		// VITESS: the FROM table can use a repository_id parameter
		Where("ts_logical_alerts.repository_id = ?", repoID)

	query = mysql.ApplyAnalysisFilter(analysisFilter, query)

	query = strictInFilter(query, "ts_logical_alerts.id in (?)", filter.IDs)
	query = strictInFilter(query, "ts_logical_alerts.number in (?)", filter.Numbers)
	query = strictInFilter(query, "ts_logical_alerts.sarif_identifier in (?)", filter.SarifIdentifiers)

	if len(filter.ExcludedSarifIdentifiers) > 0 {
		query = query.Not("ts_logical_alerts.sarif_identifier in (?)", filter.ExcludedSarifIdentifiers)
	}

	if len(filter.SeverityLevels) > 0 {
		query = addMultiSeverityFilters(filter.SeverityLevels, false, query)
	}

	if len(filter.ExcludedSeverityLevels) > 0 {
		query = addMultiSeverityFilters(filter.ExcludedSeverityLevels, true, query)
	}

	if len(filter.Resolutions) > 0 {
		query = query.Where("ts_logical_alerts.resolution in (?)", filter.Resolutions)
	}

	if len(filter.ExcludedResolutions) > 0 {
		query = query.Not("ts_logical_alerts.resolution in (?)", filter.ExcludedResolutions)
	}

	if len(filter.Cursor) > 0 {
		for _, cursorFilter := range filter.Cursor {
			query = query.Having(cursorFilter.Expression, cursorFilter.Value)
		}
	}

	switch filter.Classification {
	case proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_UNCLASSIFIED:
		query = query.Where("JSON_LENGTH(ts_logical_alerts.file_classification) = 0")
	case proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_ANY_CLASSIFICATION:
		query = query.Where("JSON_LENGTH(ts_logical_alerts.file_classification) > 0")
	case proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_NO_FILTER:
		// pass
	}

	// We group all refs for the given logical alert, so that we can reason about
	// the refs in which it is fixed or not
	query = query.Group("ts_logical_alerts.id")

	switch filter.State {
	case proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN:
		// Having the be min be 0 means that at least one associated physical alert is not fixed.
		query = query.Having("min(ts_physical_alerts.is_fixed) = 0 AND max(ts_logical_alerts.resolution) = ?", ts.AlertResolutionNone)
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED:
		// Having the min be 1 true means that all associated physical alerts are fixed.
		query = query.Having("min(ts_physical_alerts.is_fixed) = 1 OR max(ts_logical_alerts.resolution) <> ?", ts.AlertResolutionNone)
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_RESOLVED:
		query = query.Having("max(ts_logical_alerts.resolution) <> ?", ts.AlertResolutionNone)
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_FIXED:
		// Having the min be 1 true means that all associated physical alerts are fixed.
		query = query.Having("min(ts_physical_alerts.is_fixed) = 1")
	case proto.AlertStateFilter_ALERT_STATE_FILTER_ALL, proto.AlertStateFilter_ALERT_STATE_FILTER_NONE:
		// pass
	}

	if len(filter.FilePaths) > 0 {
		query = query.Where("ts_logical_alerts.file_path REGEXP ?", glob.GlobsToRegexes(filter.FilePaths))
	}

	if len(filter.LanguageFilePaths) > 0 {
		query = query.Where("ts_logical_alerts.file_path REGEXP ?", glob.GlobsToRegexes(filter.LanguageFilePaths))
	}

	return query
}

func buildLogicalAlertsQuery(db *gorm.DB, repoID ts.RepositoryEID, analysisFilter ts.AnalysisFilter, filter ts.AlertFilter) *gorm.DB {
	return buildLogicalAlertsBaseQuery(db, repoID, analysisFilter, filter).
		// Find the analyses that fixed the alert. Only analysis that completed successfully and were not deleted should be considered.
		Joins("LEFT JOIN ts_analyses a_fix ON ts_physical_alerts.last_seen_analysis_id = a_fix.baseline_id AND a_fix.repository_id = ts_logical_alerts.repository_id AND a_fix.analysis_complete AND NOT a_fix.failed AND a_fix.soft_deleted_at IS NULL").
		// VITESS: select columns used in ORDER BY
		Select("ts_logical_alerts.*, MIN(ts_physical_alerts.is_fixed) AS is_fixed, MAX(COALESCE(resolved_at, ts_physical_alerts.last_state_change_at)) as last_state_change_at, MAX(a_fix.created_at) as last_observed_fix_at")
}

func createOrQuery(queries []string) string {
	queryString := ""
	for i, query := range queries {
		if i != 0 {
			queryString += " OR "
		}
		queryString += query
	}

	return queryString
}

func addMultiSeverityFilters(severities []proto.Severity, excluded bool, query *gorm.DB) *gorm.DB {
	queries := []string{}
	for _, sev := range severities {
		q := severityFilter(sev)
		if len(q) > 0 {
			queries = append(queries, q)
		}
	}

	if excluded {
		return query.Not(createOrQuery(queries))
	}

	return query.Where(createOrQuery(queries))
}

func severityFilter(severity proto.Severity) string {
	// We explicitly require the Security Severity to be NOT NULL because otherwise, the negated version of this query will return null instead of true/false.
	switch severity {
	case proto.Severity_SEVERITY_CRITICAL:
		return "(ts_logical_alerts.security_severity IS NOT NULL AND 9 <= ts_logical_alerts.security_severity AND ts_logical_alerts.security_severity <= 10)"
	case proto.Severity_SEVERITY_HIGH:
		return "(ts_logical_alerts.security_severity IS NOT NULL AND 7 <= ts_logical_alerts.security_severity AND ts_logical_alerts.security_severity < 9)"
	case proto.Severity_SEVERITY_MEDIUM:
		return "(ts_logical_alerts.security_severity IS NOT NULL AND 4 <= ts_logical_alerts.security_severity AND ts_logical_alerts.security_severity < 7)"
	case proto.Severity_SEVERITY_LOW:
		return "(ts_logical_alerts.security_severity IS NOT NULL AND 0 <= ts_logical_alerts.security_severity AND ts_logical_alerts.security_severity < 4)"
	case proto.Severity_SEVERITY_ERROR:
		return ruleSeverityFilter(ts.SeverityLevelError)
	case proto.Severity_SEVERITY_WARNING:
		return ruleSeverityFilter(ts.SeverityLevelWarning)
	case proto.Severity_SEVERITY_NOTE:
		return ruleSeverityFilter(ts.SeverityLevelNote)
	case proto.Severity_NO_SEVERITY:
		return ""
	}
	return ""
}

func ruleSeverityFilter(ruleSeverity ts.SeverityLevel) string {
	// Security severity must be empty or invalid for rule severity to apply.
	filterSecuritySeverity := `
	(ts_logical_alerts.security_severity IS NULL
     OR ts_logical_alerts.security_severity <= 0
	 OR 10 < ts_logical_alerts.security_severity)`
	filterRuleSeverity := "(ts_logical_alerts.severity_level = " + strconv.Itoa(int(ruleSeverity)) + ")"
	return "(" + filterSecuritySeverity + " AND " + filterRuleSeverity + ")"
}

// NOTE: buildPhysicalAlertsQuery will only apply the parts of AlertFilter that correspond to columns in ts_physical_alerts.
// For any query that involves data from the ts_logical_alerts table, use buildLogicalAlertsQuery
func buildPhysicalAlertsQuery(db *gorm.DB, repoID ts.RepositoryEID, analysisFilter ts.AnalysisFilter, filter ts.AlertFilter) *gorm.DB {
	query := db.
		Joins("JOIN ts_analyses ON ts_analyses.id = ts_physical_alerts.analysis_id AND ts_analyses.repository_id = ts_physical_alerts.repository_id").
		Where("ts_physical_alerts.repository_id = ?", repoID)
	query = mysql.ApplyAnalysisFilter(analysisFilter, query)

	if filter.IDs != nil {
		query = query.Where("ts_physical_alerts.logical_alert_id in (?)", filter.IDs)
	}

	switch filter.State {
	case proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN:
		query = query.Where("NOT ts_physical_alerts.is_fixed")
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_FIXED:
		query = query.Where("ts_physical_alerts.is_fixed")
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED,
		proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_RESOLVED,
		proto.AlertStateFilter_ALERT_STATE_FILTER_NONE,
		proto.AlertStateFilter_ALERT_STATE_FILTER_ALL:
		// pass
	}

	return query
}

// alertsRuleIDs returns all the Rule IDs used in the given repository. A rule is
// considered "used" if there exists at least one LogicalAlert associated with
// it.
func (s *Service) alertsRuleIDs(ctx context.Context, repoID ts.RepositoryEID) ([]ts.RuleID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	var ruleIDs []ts.RuleID
	err := db.Model(&ts.LogicalAlert{}).
		Where("ts_logical_alerts.repository_id = ?", repoID).
		Pluck("DISTINCT ts_logical_alerts.rule_id", &ruleIDs).
		Error

	if err != nil {
		return nil, errors.Wrap(err, "finding rule ids has failed")
	}

	return ruleIDs, nil
}

func applyRuleFilter(db *gorm.DB, filter *ts.RuleFilter) (*gorm.DB, error) {
	ruleQuery := db

	toolIDs := filter.ToolIDs

	// if no tool ids were provided we only want to return rules belonging to tools that have analysed this repository
	// without this clause we would match global rules from all possible global tools
	if toolIDs == nil && filter.RepoID > 0 {
		err := db.New().Model(&ts.Analysis{}).Where("repository_id = ?", filter.RepoID).Pluck("DISTINCT tool_id", &toolIDs).Error
		if err != nil {
			return nil, errors.Wrap(err, "could not load tool ids for rule filter")
		}
	}

	if toolIDs != nil {
		ruleQuery = ruleQuery.Where("ts_rules.tool_id IN (?)", toolIDs)
	}

	if len(filter.SarifIdentifiers) > 0 {
		ruleQuery = ruleQuery.Where("ts_rules.sarif_identifier IN (?)", filter.SarifIdentifiers)
	}

	if len(filter.SearchQuery) > 0 {
		filter_wildcarded := "%" + filter.SearchQuery + "%"
		ruleQuery = ruleQuery.Where("(ts_rules.sarif_identifier LIKE ? or ts_rules.short_description LIKE ?)", filter_wildcarded, filter_wildcarded)
	}

	if len(filter.Tags) > 0 {
		subquery := ruleQuery.
			Joins("INNER JOIN ts_rule_tags ON ts_rules.id = ts_rule_tags.rule_id AND ts_rule_tags.tag IN (?)", filter.Tags).
			Select("ts_rules.id").
			Group("ts_rules.id").
			Having("COUNT(1) = ?", len(filter.Tags)).
			SubQuery()

		ruleQuery = db.Joins("INNER JOIN ? AS _matching_rules ON ts_rules.id = _matching_rules.id", subquery)
	}

	return ruleQuery, nil
}

// AlertsRules returns a set of Rules used in the given repository. A rule is
// considered "used" if there exists at least one LogicalAlert associated with
// it.
func (s *Service) AlertsRules(ctx context.Context, filter ts.RuleFilter) ([]ts.Rule, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	activeRuleIDs, err := s.alertsRuleIDs(ctx, filter.RepoID)
	if err != nil {
		return nil, errors.Wrap(err, "finding rules for repository has failed")
	}
	if len(activeRuleIDs) == 0 {
		return []ts.Rule{}, nil
	}

	var rules []ts.Rule

	query, err := applyRuleFilter(db.Model(&ts.Rule{}), &filter)
	if err != nil {
		return nil, errors.Wrap(err, "applying rule filter has failed")
	}

	query = query.Where("ts_rules.id IN (?)", activeRuleIDs).Preload("Tool").Preload("Tags").Limit(1000)

	err = query.Find(&rules).Error
	if err != nil {
		return nil, errors.Wrap(err, "finding rules has failed")
	}

	return rules, nil
}

// Rule returns the first rule for the given repo, tool, and sarif identifier
func (s *Service) Rule(ctx context.Context, repoID ts.RepositoryEID, toolID ts.ToolID, sarifID string) (ts.Rule, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	var rule ts.Rule

	query, err := applyRuleFilter(
		db.Model(&ts.Rule{}),
		&ts.RuleFilter{
			RepoID:           repoID,
			ToolIDs:          []ts.ToolID{toolID},
			SarifIdentifiers: []string{sarifID},
		},
	)
	if err != nil {
		return rule, errors.Wrap(err, "applying rule filter has failed")
	}

	err = query.First(&rule).Error
	if gorm.IsRecordNotFoundError(err) {
		return rule, ts.ErrRuleNotFound
	} else if err != nil {
		return rule, errors.Wrap(err, "fetching rule has failed")
	}
	return rule, nil
}

// RulesTags returns the set of all tags used in a given repo,
// with optional additional filtering
func (s *Service) RulesTags(ctx context.Context, filter ts.RuleTagFilter) ([]string, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	activeRuleIDs, err := s.alertsRuleIDs(ctx, filter.RepoID)
	if err != nil {
		return nil, errors.Wrap(err, "finding rules for repository has failed")
	}

	// TODO:We do not have enough information to exclude Tags from forks
	query := db.
		Table("ts_rule_tags").
		Where("ts_rule_tags.rule_id IN (?)", activeRuleIDs)

	if filter.ToolIDs != nil {
		query = query.
			Joins("INNER JOIN ts_rules ON ts_rules.id = ts_rule_tags.rule_id").
			Where("ts_rules.tool_id IN (?)", filter.ToolIDs)
	}

	var tags []string
	err = query.Pluck("DISTINCT ts_rule_tags.tag", &tags).Error
	if err != nil {
		return nil, errors.Wrap(err, "finding rule tags has failed")
	}

	return tags, nil
}

func setLastStateChangeAt(baseline []*ts.PhysicalAlert, newAlerts []*ts.PhysicalAlert) {
	if len(baseline) == 0 {
		return
	}
	keyFunc := func(a *ts.PhysicalAlert) ts.LogicalAlertID { return a.LogicalAlertID }
	baselineSet := transforms.IndexBy(baseline, keyFunc)
	newSet := transforms.IndexBy(newAlerts, keyFunc)
	small, large := baselineSet, newSet
	if len(small) > len(large) {
		small, large = newSet, baselineSet
	}
	for k := range small {
		if _, ok := large[k]; ok && !baselineSet[k].IsFixed {
			newSet[k].LastStateChangeAt = baselineSet[k].LastStateChangeAt
		}
	}
}

// SaveAlerts populates the alerts specified in the SARIF Run into the database. It does the following:
// - Creates rules that do not exist yet.
// - Creates or updates the logical alert records
// - Associates each physical alert to an existing (or new) logical alert
// - Saves the new physical alert records
func (s *Service) SaveAlerts(ctx context.Context, analysis *ts.Analysis, repository *ts.Repository, newAlerts []*ts.PhysicalAlert) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// Create logical alerts and get references to existing logical alerts
	err := s.populateLogicalAlerts(ctx, analysis, repository, newAlerts)
	if err != nil {
		return errors.Wrap(err, "unable to write the logical alerts")
	}

	setLastStateChangeAt(analysis.BaselineAlerts, newAlerts)

	err = s.writePhysicalAlerts(ctx, newAlerts, 100, repository.RepositoryID)
	if err != nil {
		return errors.Wrap(err, "unable to write the physical alerts")
	}

	return nil
}

// populateLogicalAlerts assigns logical alerts to the physical alerts, either by linking to existing or by creating fresh logical alerts.
func (s *Service) populateLogicalAlerts(ctx context.Context, analysis *ts.Analysis, repository *ts.Repository,
	newAlerts []*ts.PhysicalAlert) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	logicals, err := FetchLogicalAlertsForPhysicalAlerts(ctx, s.db, analysis.RepositoryID, newAlerts)
	if err != nil {
		return err
	}

	existingLogicalAlerts := maps.Values(logicals)

	// Split the logical alerts into the ones we have seen before, and the ones we haven't
	existingAlerts := make(map[ts.LogicalAlertID]*ts.LogicalAlert) // Alerts we have seen before
	uniqueAlerts := []*ts.PhysicalAlert{}                          // Alerts we see the first time in this analysis
	for _, alert := range newAlerts {
		l, ok := logicals[alerts.FromBytes(alert.StableAlertIdentifier)]
		if ok {
			alert.LogicalAlertID = l.ID
			alert.LogicalAlert = l
			existingAlerts[l.ID] = l
		} else {
			uniqueAlerts = append(uniqueAlerts, alert)
		}
	}

	// UPDATE: The alerts that already exist might need updating
	// NOTE: This breaks our transactionality assumption, since we update these entries
	//       before committing the analysis. We decided to accept this for now.
	now := sqltime.Now()
	unchangedAlertIDs := []ts.LogicalAlertID{}

	for _, pa := range newAlerts {
		if la, ok := existingAlerts[pa.LogicalAlertID]; ok {
			update := make(map[string]interface{})

			// do not allow forks to change the rule version, alert weight or physical alert properties
			if analysis.SourceRepositoryID == analysis.RepositoryID {
				if pa.RuleID != la.RuleID {
					// Rule can change when metadata is updated
					la.RuleID = pa.RuleID
					appctx.Stats(ctx).Counter("alerts.rule_update", stats.Tags{}, 1)
					update["rule_id"] = la.RuleID
				}
				// Update logical alert if weight or severities changed
				if pa.Weight != la.Weight {
					la.Weight = pa.Weight
					appctx.Stats(ctx).Counter("alerts.weight_update", stats.Tags{}, 1)
					update["weight"] = la.Weight
				}
				if pa.SecuritySeverity != la.SecuritySeverity {
					la.SecuritySeverity = pa.SecuritySeverity
					appctx.Stats(ctx).Counter("alerts.security_severity_update", stats.Tags{}, 1)
					update["security_severity"] = la.SecuritySeverity
				}
				if pa.SeverityLevel != la.SeverityLevel {
					la.SeverityLevel = pa.SeverityLevel
					appctx.Stats(ctx).Counter("alerts.severity_level_update", stats.Tags{}, 1)
					update["severity_level"] = la.SeverityLevel
				}

				if IsCanonicalAlertUpdate(analysis, repository, la) {
					appctx.Stats(ctx).Counter("alerts.instance_fields_update", stats.Tags{}, 1)
					la.DefaultConfigurationID = analysis.ConfigurationID
					update["default_configuration_id"] = analysis.ConfigurationID
					// setting la.DefaultConfiguration because GORM will otherwise potentially overwrite the default configuration
					// via hooks if we save it again later for any reason
					la.DefaultConfiguration = analysis.Configuration
					la.FilePath = pa.FilePath
					update["file_path"] = pa.FilePath
					la.Region = pa.Region
					update["start_line"] = pa.Region.StartLine
					update["end_line"] = pa.Region.EndLine
					update["start_column"] = pa.Region.StartColumn
					update["end_column"] = pa.Region.EndColumn
					la.Message = pa.Message
					update["message"] = pa.Message
					la.MessageMarkdown = pa.MessageMarkdown
					update["message_markdown"] = pa.MessageMarkdown
					la.FileClassification = pa.FileClassification
					update["file_classification"] = pa.FileClassification
				}
			}

			if len(update) > 0 {
				update["updated_at"] = now
				err := db.Model(&la).UpdateColumns(update).Error
				if err != nil {
					return err
				}
			} else {
				unchangedAlertIDs = append(unchangedAlertIDs, la.ID)
				la.UpdatedAt = now
			}
		}
	}
	if len(unchangedAlertIDs) > 0 {
		// Existing alerts that do not have any other change get a timestamp update
		la := ts.LogicalAlert{}
		err = db.Model(&la).Where("id IN (?)", unchangedAlertIDs).UpdateColumn("updated_at", now).Error
		if err != nil {
			return err
		}
	}

	logicalAlerts := []*ts.LogicalAlert{}

	// CREATE: The alerts we have not seen before need to be created in the database.
	if len(uniqueAlerts) > 0 {
		// Allocate sequential numbers for the alerts
		seq := s.sequenceCreator(uint64(analysis.RepositoryID))
		first, err := seq.Incr(ctx, uint32(len(uniqueAlerts)))
		if err != nil {
			return err
		}

		for n, alert := range uniqueAlerts {
			guid, err := ts.NewLogicalAlertGUID()
			if err != nil {
				return err
			}

			now := sqltime.Now()
			la := &ts.LogicalAlert{
				RepositoryID:          analysis.RepositoryID,
				Number:                first + uint32(n),
				RuleID:                alert.RuleID,
				SarifIdentifier:       alert.RuleSarifIdentifier,
				Weight:                alert.Weight,
				StableAlertIdentifier: alert.StableAlertIdentifier,
				SeverityLevel:         alert.SeverityLevel,
				SecuritySeverity:      alert.SecuritySeverity,
				GUID:                  guid,
				// Set the analysisID for later processing
				FirstSeenAnalysisID: analysis.ID,
				// We set created_at and updated_at as they are not set by the bulk writer
				BaseModel: ts.BaseModel{
					CreatedAt: analysis.CreatedAt,
					UpdatedAt: now,
				},

				// set initial physicalAlertFields
				FilePath:               alert.FilePath,
				Region:                 alert.Region,
				Message:                alert.Message,
				MessageMarkdown:        alert.MessageMarkdown,
				FileClassification:     alert.FileClassification,
				DefaultConfigurationID: analysis.ConfigurationID,
			}
			logicalAlerts = append(logicalAlerts, la)
		}
		err = s.writeLogicalAlerts(ctx, logicalAlerts)
		if err != nil {
			return err
		}
		// Assign logical alert ids
		for n, alert := range uniqueAlerts {
			alert.LogicalAlertID = logicalAlerts[n].ID
			alert.LogicalAlert = logicalAlerts[n]
		}
	}

	analysis.SetNewLogicalAlerts(logicalAlerts)
	analysis.SetExistingLogicalAlerts(existingLogicalAlerts)

	return nil
}

// IsCanonicalAlertUpdate returns true if the logical alert example instance information should be updated
func IsCanonicalAlertUpdate(analysis *ts.Analysis, repository *ts.Repository, la *ts.LogicalAlert) bool {
	return bytes.Equal(analysis.Ref, repository.DefaultRef) || // The analysis is on the default ref
		la.DefaultConfigurationID == 0 || // The logical alert has no default configuration yet
		!bytes.Equal(la.DefaultConfiguration.Ref, repository.DefaultRef) // The logical alert is not already on the default ref
}

// writeLogicalAlerts writes the specified logical alerts to the database
func (s *Service) writeLogicalAlerts(ctx context.Context, newAlerts []*ts.LogicalAlert) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	return gormbulk.Insert(ctx, &gormbulk.InsertOptions[ts.LogicalAlert]{
		DB:        s.db,
		Objects:   newAlerts,
		ChunkSize: 100,
	})
}

// writePhysicalAlerts inserts chunkSize rows in each statement
// for PhysicalAlert, RelatedLocation and ThreadFlowLocation
func (s *Service) writePhysicalAlerts(ctx context.Context, newAlerts []*ts.PhysicalAlert, chunkSize int, repoID ts.RepositoryEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	if len(newAlerts) == 0 {
		return nil
	}

	paDB := db.Omit("Message", "MessageMarkdown", "FilePath", "FileClassification", "Fingerprint")

	if err := gormbulk.Insert(ctx, &gormbulk.InsertOptions[ts.PhysicalAlert]{
		DB:        paDB,
		Objects:   newAlerts,
		ChunkSize: chunkSize,
	}); err != nil {
		return errors.Wrap(err, "failed to insert new alerts")
	}
	return nil
}

// CopyFixedAlerts copies all fixed alerts from the previous analysis
// and adds them to the specified analysis
func (s *Service) CopyFixedAlerts(ctx context.Context, repo *ts.Repository, analysis *ts.Analysis, alerts []*ts.PhysicalAlert) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// All alerts in the baseline that were not part of this analysis
	// are either fixed now or earlier so we need to move them across to the new state
	now := sqltime.Now()
	fixed := []*ts.PhysicalAlert{}

	fixedLogicalAlertIDs := []ts.LogicalAlertID{}
	for _, a := range alerts {
		cp := a.DeepCopy()
		cp.ID = 0
		cp.Analysis = &ts.Analysis{}
		for _, rl := range cp.RelatedLocations {
			rl.ID = 0
		}
		if !cp.IsFixed {
			// Fixed in this analysis
			ref := cp.AnalysisID
			cp.LastSeenAnalysisID = &ref
			cp.LastStateChangeAt = now
			cp.IsFixed = true
		}

		// Update the analysis to this
		cp.AnalysisID = analysis.ID
		// We keep the created_at unchanged (to match the original creation time, but let updated_at be set)
		cp.UpdatedAt = sqltime.Time{}
		fixed = append(fixed, cp)

		fixedLogicalAlertIDs = append(fixedLogicalAlertIDs, a.LogicalAlertID)
	}
	err := s.writePhysicalAlerts(ctx, fixed, 100, repo.RepositoryID)
	if err != nil {
		return err
	}

	analysis.SetFixedAlerts(fixed)
	fixedLogicalAlerts := []*ts.LogicalAlert{}
	err = s.db.Model(&ts.LogicalAlert{}).Find(&fixedLogicalAlerts, "repository_id = ? AND id in (?)", analysis.RepositoryID, fixedLogicalAlertIDs).Error
	if err != nil {
		return err
	}
	analysis.SetFixedLogicalAlerts(fixedLogicalAlerts)

	return nil
}

func (s *Service) setLogicalAlertsResolution(ctx context.Context, las []*ts.LogicalAlert,
	resolution ts.AlertResolution, resolverID *ts.UserEID, resolutionNote ts.Note, updateTime sqltime.Time, dismissalApproverID *uint64) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	if len(las) == 0 {
		return errors.New("no alerts specified")
	}

	laIDs := make([]ts.LogicalAlertID, 0, len(las))
	for _, la := range las {
		switch {
		case la.Resolution == resolution:
			appctx.Logger(ctx).Info("not changing alert resolution to the same value", kvp.Int64("gh.turboscan.logical_alert_id", int64(la.ID)))
		default:
			laIDs = append(laIDs, la.ID)
		}
	}

	var resolver *ts.UserEID
	var resolvedAt *time.Time
	// We do not set the resolver, resolvedAt, or resolutionNotePointer when reopening an alert
	if resolution != ts.AlertResolutionNone {
		resolver = resolverID
		resolvedAt = &updateTime.Time
	}

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	// We're using `UpdateColumns` below instead of a regular `Update` in order to set the custom `updated_at` timestamp.
	// This will not call any of the gorm callbacks, but that should be ok in this case.
	err := db.
		Model(ts.LogicalAlert{}).
		Where("id in (?)", laIDs).
		UpdateColumns(map[string]interface{}{
			"resolution":            resolution,
			"resolver_id":           resolver,
			"resolved_at":           resolvedAt,
			"updated_at":            updateTime,
			"resolution_note":       resolutionNote,
			"dismissal_approver_id": dismissalApproverID,
		}).
		Error

	if err != nil {
		return errors.Wrap(err, "resolving logical alerts has failed")
	}

	for _, la := range las {
		la.Resolution = resolution
		la.ResolverID = resolver
		la.DismissalApproverID = dismissalApproverID
		la.ResolutionNote = resolutionNote
		la.UpdatedAt = updateTime

		if resolvedAt != nil {
			sqlResolutionTime := sqltime.Time{Time: *resolvedAt}
			la.ResolvedAt = &sqlResolutionTime
			// the last_state_change_at is always the same as resolved_at in this case.
			la.LastStateChangeAt = &sqlResolutionTime
		} else {
			la.ResolvedAt = nil
		}
	}

	return nil
}

// ResolveLogicalAlerts mark alerts as being resolved with the
// specified resolution
func (s *Service) ResolveLogicalAlerts(ctx context.Context, las []*ts.LogicalAlert, resolution ts.AlertResolution, resolverID ts.UserEID, resolutionNote ts.Note, updateTime sqltime.Time, dismissalApproverID *uint64) error {
	return s.setLogicalAlertsResolution(ctx, las, resolution, &resolverID, resolutionNote, updateTime, dismissalApproverID)
}

// ReopenLogicalAlerts allows a user to re-open an array of manually resolved alerts
func (s *Service) ReopenLogicalAlerts(ctx context.Context, las []*ts.LogicalAlert, updateTime sqltime.Time) error {
	err := s.setLogicalAlertsResolution(ctx, las, ts.AlertResolutionNone, nil, "", updateTime, nil)
	if err != nil {
		return err
	}

	// update LastStateChangeAt for all related physical alerts
	// as they are used primarily as a cache key and any cache is now invalid
	if len(las) > 0 {
		repositoryID := las[0].RepositoryID
		laIds := transforms.Map(las, func(t *ts.LogicalAlert) ts.LogicalAlertID { return t.ID })
		err = s.db.Exec(`UPDATE ts_physical_alerts
			SET last_state_change_at = NOW()
			WHERE repository_id = ? AND logical_alert_id IN (?)`,
			repositoryID, laIds).Error
	}
	return err
}

// CheckLogicalAlertLimits looks in the DB to see if logical alert limits have been exceeded
func (s *Service) CheckLogicalAlertLimits(ctx context.Context, repoID ts.RepositoryEID, hardLimit int, softLimit int) (bool, bool, error) {
	hardLimitExceeded := false
	softLimitExceeded := false
	err := s.db.Raw(`
		SELECT COUNT(1) >= ?, COUNT(1) >= ?
		FROM (
		SELECT 1 FROM ts_logical_alerts
		WHERE repository_id = ?
		LIMIT ?)
		AS total
	`,
		hardLimit, softLimit, repoID, hardLimit).Row().Scan(&hardLimitExceeded, &softLimitExceeded)
	return hardLimitExceeded, softLimitExceeded, errors.Wrap(err, "checking logical alert limits failed")
}

func (s *Service) PhysicalAlertByIDs(ctx context.Context, repoID ts.RepositoryEID, ids []ts.PhysicalAlertID, options *ts.FindOptions) ([]*ts.PhysicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	query := db.
		Where("ts_physical_alerts.id IN (?)", ids).
		Where("ts_physical_alerts.repository_id = ?", repoID)
	query = options.Apply(query)

	var pa []*ts.PhysicalAlert
	err := query.Find(&pa).Error
	if err != nil {
		return nil, errors.Wrap(err, "fetching physical alerts failed")
	}
	return pa, nil
}

// PhysicalAlerts returns the list of PhysicalAlerts that match the filters.
func (s *Service) PhysicalAlerts(ctx context.Context, repoID ts.RepositoryEID, alertFilter ts.AlertFilter, analysisFilter ts.AnalysisFilter, options *ts.FindOptions) ([]*ts.PhysicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	query := buildPhysicalAlertsQuery(db.Model(ts.PhysicalAlert{}), repoID, analysisFilter, alertFilter).Select("ts_physical_alerts.created_at, ts_physical_alerts.*")
	// this order by is _extremely_ expensive
	// removing it in combination with "analysis_id IN (?)" instead of a JOIN avoids a temporary table + filesort
	// and allows the query planner to use a BETWEEN instead of an OFFSET/LIMIT, radically improving the performance
	// see https://github.com/github/turboscan/pull/1559
	// unfortunately, it is required because CopyFixedAlerts will insert records with old created_at timestamps
	// and we should not prefer these over newer alerts
	query = query.Order("ts_physical_alerts.created_at DESC")
	query = options.Apply(query)

	physicalAlerts := []*ts.PhysicalAlert{}
	err := query.Find(&physicalAlerts).Error
	if err != nil {
		return nil, errors.Wrap(err, "fetching physical alerts has failed")
	}
	return physicalAlerts, nil
}

func (s *Service) PhysicalAlertsByAlertNumbers(ctx context.Context, repoID ts.RepositoryEID, alertNOs []uint32, analysisFilter ts.AnalysisFilter, options *ts.FindOptions) ([]*ts.PhysicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	query := db.
		Joins("JOIN ts_analyses ON ts_analyses.id = ts_physical_alerts.analysis_id AND ts_analyses.repository_id = ts_physical_alerts.repository_id").
		Joins("JOIN ts_logical_alerts ON ts_logical_alerts.id = ts_physical_alerts.logical_alert_id AND ts_logical_alerts.repository_id = ts_physical_alerts.repository_id")
	query = mysql.ApplyAnalysisFilter(analysisFilter, query)

	query = query.
		Where("ts_physical_alerts.repository_id = ?", repoID).
		Where("ts_logical_alerts.number in (?)", alertNOs)
	query = options.Apply(query)

	physicalAlerts := []*ts.PhysicalAlert{}
	err := query.Find(&physicalAlerts).Error
	if err != nil {
		return nil, errors.Wrap(err, "fetching physical alerts has failed")
	}
	return physicalAlerts, nil
}

// CountPhysicalAlerts returns the number of PhysicalAlerts that match the filters.
func (s *Service) CountPhysicalAlerts(ctx context.Context, repoID ts.RepositoryEID, alertFilter ts.AlertFilter, analysisFilter ts.AnalysisFilter) (uint64, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	query := buildPhysicalAlertsQuery(db.Model(ts.PhysicalAlert{}), repoID, analysisFilter, alertFilter)

	var totalCount int
	err := query.Count(&totalCount).Error
	if err != nil {
		return 0, errors.Wrap(err, "counting physical alerts has failed")
	}
	return uint64(totalCount), nil
}

// GetAlertsByKeys returns full logical alerts (including canonical physical alert)
// from the specified keys
func (s *Service) GetAlertsByKeys(ctx context.Context, keys []ts.ESAlertKey) ([]*ts.LogicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	start := time.Now()
	defer func() {
		appctx.Stats(ctx).DistributionMs("es.request", stats.Tags{"method": "get-alerts-by-keys"}, time.Since(start))
	}()

	logicalIDs := []ts.LogicalAlertID{}
	physicalIDs := []ts.PhysicalAlertID{}
	for _, k := range keys {
		logicalIDs = append(logicalIDs, k.LogicalAlertID)
		physicalIDs = append(physicalIDs, k.PhysicalAlertID)
	}

	logicalAlerts := []*ts.LogicalAlert{}
	err := db.Where("id IN (?)", logicalIDs).
		Preload("Rule").
		Preload("Rule.Tags").
		Preload("Rule.Tool").
		Find(&logicalAlerts).Error
	if err != nil {
		return nil, err
	}
	lMap := map[ts.LogicalAlertID]*ts.LogicalAlert{}
	for _, l := range logicalAlerts {
		lMap[l.ID] = l
	}
	physicalAlerts := []*ts.PhysicalAlert{}
	err = db.Where("id IN (?)", physicalIDs).
		Preload("Analysis").
		Preload("Analysis.Tool").
		Preload("Analysis.ToolVersion").
		Preload("LastSeenAnalysis").
		Find(&physicalAlerts).Error
	if err != nil {
		return nil, err
	}

	pMap := map[ts.LogicalAlertID]*ts.PhysicalAlert{}
	for _, p := range physicalAlerts {
		pMap[p.LogicalAlertID] = p
	}
	result := []*ts.LogicalAlert{}
	for _, k := range keys {
		ctx := appctx.With(ctx,
			k.RepositoryID.AsKVP(),
			kvp.Uint64("gh.turboscan.logical_alert_id", uint64(k.LogicalAlertID)),
			kvp.Uint64("gh.turboscan.physical_alert_id", uint64(k.PhysicalAlertID)),
		)
		l, lOk := lMap[k.LogicalAlertID]
		p, pOk := pMap[k.LogicalAlertID]
		if !lOk || !pOk {
			// This can happen if e.g. the index is inconsistent and
			// the physical alert has been garbage collected.
			// There is no known reason for why the logical alert should be
			// missing, but we'll be roboust anyway.
			appctx.Logger(ctx).Info("Could not find logical or physical alert from key")
			appctx.Stats(ctx).Counter("es.alert_keys", stats.Tags{"status": "missing"}, 1)
			continue
		}
		if p.Analysis.SoftDeletedAt != nil {
			// This can happen if e.g. the index is inconsistent and
			// the analysis has been deleted.
			appctx.Logger(ctx).Info("Physical alert has been soft deleted")
			appctx.Stats(ctx).Counter("es.alert_keys", stats.Tags{"status": "soft-deleted"}, 1)
			continue
		}
		appctx.Stats(ctx).Counter("es.alert_keys", stats.Tags{"status": "present"}, 1)
		l.PhysicalAlerts = append(l.PhysicalAlerts, p)
		l.IsFixed = k.IsFixed
		if p.LastSeenAnalysisID != nil {
			l.LastObservedFixAt = k.LastObservedFixAt
		}
		// We take the last state change at from the ES index, to make sure we
		// are consistent with an eventual sort.
		l.LastStateChangeAt = k.LastStateChangeAt
		result = append(result, l)
	}
	return result, nil
}

func (s *Service) RetrieveBaselineAlerts(ctx context.Context, analysis *ts.Analysis) ([]*ts.PhysicalAlert, error) {
	if analysis.BaselineID == nil {
		return nil, nil
	}
	analysisFilter := ts.AnalysisFilter{
		RepositoryID:    analysis.RepositoryID,
		AnalysisIDs:     []ts.AnalysisID{*analysis.BaselineID},
		IncludeOutdated: true,
	}
	return s.PhysicalAlerts(ctx, analysis.RepositoryID, ts.AlertFilter{}, analysisFilter, &ts.FindOptions{
		Preloads: []string{"Analysis"},
	})
}
