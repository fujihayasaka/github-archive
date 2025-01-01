// Package pr_alerts handles the alerts to be showed in the PRs.
package pr_alerts

import (
	"context"
	"sort"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/mysql"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
	"golang.org/x/exp/maps"
)

const prAlertsChunkSize = 1000

type AnalysisUnarchiver interface {
	Unarchive(context.Context, ...*ts.Analysis) error
	UnarchiveAlerts(context.Context, ts.RepositoryEID, []uint32, ...*ts.Analysis) ([]*ts.LogicalAlert, error)
}

type Service struct {
	db *gorm.DB
}

func NewService(db *gorm.DB) *Service {
	as := &Service{
		db: db,
	}
	return as
}

func (s *Service) PullRequestAlerts(ctx context.Context, unarchiver AnalysisUnarchiver, repoID ts.RepositoryEID, opts *ts.PRAlertsOpts) (*ts.PRAlerts, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// 1. Fetch all HEAD analyses
	analyses, err := s.getAnalyses(ctx, repoID, opts.ToolIDs, opts.AfterCommits, nil)
	if err != nil {
		return nil, err
	}

	// 2. Fetch all base ref analyses
	baseRefAnalyses, err := s.getBaseRefAnalyses(ctx, repoID, opts.ToolIDs, opts.BaseRef)
	if err != nil {
		return nil, err
	}

	fileChangesAddedMap, fileChangesRemovedMap := fileChangesToMaps(opts.FileChanges)

	// 3. Get new alerts
	newAlerts, analysisAlertCounts, err := s.getAlertsInChanges(ctx, unarchiver, repoID, analyses, fileChangesAddedMap, opts)
	if err != nil {
		return nil, err
	}

	// 4. Get fixed alerts
	fixedAlerts, _, err := s.getAlertsInChanges(ctx, unarchiver, repoID, baseRefAnalyses, fileChangesRemovedMap, opts)
	if err != nil {
		return nil, err
	}

	// 5. Get missing categories
	missingCategories := transforms.IndexBy(getMissingBaseRefAnalyses(baseRefAnalyses, analyses), func(a ts.Analysis) ts.Category {
		return a.Category
	})

	// 6. Get summary about new categories
	candidateNewCategoryAnalyses := getCandidateNewCategoryAnalyses(baseRefAnalyses, analyses)
	newCategoryAnalyses, err := s.getNewCategoryAnalyses(ctx, repoID, opts.ToolIDs, candidateNewCategoryAnalyses)
	if err != nil {
		return nil, err
	}

	newCategories := make(map[ts.Category]uint64)
	for _, analysis := range newCategoryAnalyses {
		newCategories[analysis.Category] = uint64(analysisAlertCounts[analysis.ID])
	}

	// 7. Compute latest upload time from HEAD and base analyses
	var latestUploadTime *sqltime.Time
	for _, analysis := range analyses {
		if analysis.UploadFinishedAt != nil && (latestUploadTime == nil || analysis.UploadFinishedAt.After(latestUploadTime.Time)) {
			latestUploadTime = analysis.UploadFinishedAt
		}
	}
	for _, analysis := range baseRefAnalyses {
		if analysis.UploadFinishedAt != nil && (latestUploadTime == nil || analysis.UploadFinishedAt.After(latestUploadTime.Time)) {
			latestUploadTime = analysis.UploadFinishedAt
		}
	}

	out := &ts.PRAlerts{
		NewAlerts:         newAlerts,
		FixedAlerts:       fixedAlerts,
		MissingCategories: missingCategories,
		NewCategories:     newCategories,
		LatestUploadTime:  latestUploadTime,
	}

	return out, nil
}

var ErrNoAnalyses = errors.New("no analyses found")

func (s *Service) PullRequestAlertsSummary(ctx context.Context, unarchiver AnalysisUnarchiver, repoID ts.RepositoryEID, opts *ts.PRAlertsOpts) (ts.ToolAlertCounts, []ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// 1. Fetch all HEAD analyses
	analyses, err := s.getAnalyses(ctx, repoID, opts.ToolIDs, opts.AfterCommits, nil)
	if err != nil {
		return nil, nil, err
	}

	// 2. Fetch all base ref analyses
	baseRefAnalyses, err := s.getBaseRefAnalyses(ctx, repoID, opts.ToolIDs, opts.BaseRef)
	if err != nil {
		return nil, nil, err
	}

	if len(analyses) == 0 && len(baseRefAnalyses) == 0 {
		return nil, nil, ErrNoAnalyses
	}

	fileChangesAddedMap, _ := fileChangesToMaps(opts.FileChanges)

	// 3. Get new alerts
	newAlerts, _, err := s.getAlertsInChanges(ctx, unarchiver, repoID, analyses, fileChangesAddedMap, opts)
	if err != nil {
		return nil, nil, err
	}

	// 4.1 Determine alert counts for each tool with alerts
	toolAlertCounts, err := countToolAlerts(newAlerts)
	if err != nil {
		return nil, nil, err
	}

	// 4.2 . Determine found categories and make sure there is an entry for each tool
	// This is so that if there are 0 alerts, there still is an entry in the map.
	for _, analysis := range analyses {
		if _, ok := toolAlertCounts[analysis.ToolID]; !ok {
			toolAlertCounts[analysis.ToolID] = ts.AlertCounts{
				BySeverity:         make(map[ts.SeverityLevel]int),
				BySecuritySeverity: make(map[proto.SecuritySeverity]int),
			}
		}
	}

	// 5. Get missing analyses
	missingAnalyses := getMissingBaseRefAnalyses(baseRefAnalyses, analyses)

	return toolAlertCounts, missingAnalyses, nil
}

func countToolAlerts(alerts []*ts.LogicalAlert) (ts.ToolAlertCounts, error) {
	countsByTool := make(ts.ToolAlertCounts)
	for _, alert := range alerts {
		counts, ok := countsByTool[alert.Rule.ToolID]
		if !ok {
			counts = ts.AlertCounts{
				BySeverity:         make(map[ts.SeverityLevel]int),
				BySecuritySeverity: make(map[proto.SecuritySeverity]int),
			}
		}

		counts.Total++
		pa, err := alert.Canonical()
		if err != nil {
			return nil, err
		}

		// We take the severities from the physical alert, same as when we are serializing a Result.
		counts.BySeverity[pa.SeverityLevel]++
		counts.BySecuritySeverity[pa.SecuritySeverityLevel()]++

		countsByTool[alert.Rule.ToolID] = counts
	}

	return countsByTool, nil
}

func (s *Service) getAlertsInChanges(ctx context.Context, unarchiver AnalysisUnarchiver, repoID ts.RepositoryEID, analyses ts.MP2Analysis, fileChangesMap map[string][]*proto.Change, opts *ts.PRAlertsOpts) ([]*ts.LogicalAlert, map[ts.AnalysisID]uint32, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// If there are no changes, then no alerts can be affected
	if len(fileChangesMap) == 0 {
		return nil, nil, nil
	}

	analysesList := maps.Values(analyses)

	// 1. Load the alerts with locations on changed lines for the analyses
	affectedAlerts, err := s.getAffectedAlerts(ctx, unarchiver, repoID, analysesList, fileChangesMap, opts)
	if err != nil {
		return nil, nil, err
	}

	// 2. Fetch the unresolved logical alerts to return to the monolith
	newLogicalAlertMap, err := s.getUnresolvedLogicalAlerts(ctx, repoID, maps.Keys(affectedAlerts))
	if err != nil {
		return nil, nil, err
	}

	// 3. Extend the logical alerts with their canonical physical alert and
	// count the number of alerts per analysis
	analysisAlertCounts := make(map[ts.AnalysisID]uint32, len(analysesList))
	for _, a := range analysesList {
		analysisAlertCounts[a.ID] = 0
	}

	newAlerts := []*ts.LogicalAlert{}
	for _, alert := range newLogicalAlertMap {
		canonical, ok := affectedAlerts[alert.ID]
		if ok {
			alert.PhysicalAlerts = []*ts.PhysicalAlert{canonical}
			newAlerts = append(newAlerts, alert)

			analysisAlertCounts[canonical.AnalysisID]++
		}
	}

	sort.Slice(newAlerts, func(i, j int) bool {
		a := newAlerts[i]
		b := newAlerts[j]

		if a.FilePath != b.FilePath {
			return a.FilePath < b.FilePath
		}
		if a.Region.StartLine != b.Region.StartLine {
			return a.Region.StartLine < b.Region.StartLine
		}
		if a.Region.StartColumn != b.Region.StartColumn {
			return a.Region.StartColumn < b.Region.StartColumn
		}
		return newAlerts[i].Number < newAlerts[j].Number
	})

	return newAlerts, analysisAlertCounts, nil
}

func (s *Service) getNewCategoryAnalyses(ctx context.Context, repoID ts.RepositoryEID, toolIDs []ts.ToolID, candidateAnalyses ts.MP2Analysis) (ts.MP2Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	m := make(ts.MP2Analysis)
	if len(candidateAnalyses) == 0 {
		return m, nil
	}

	// Find analysis IDs for _new_ categories, meaning categories that have only been seen on 1 branch
	filter := ts.AnalysisFilter{
		RepositoryID: repoID,
		ToolIDs:      toolIDs,
		State:        ts.AnalysisStateFilterMostRecent,
	}

	query := mysql.ApplyAnalysisFilter(filter, db)
	query = query.Group("ts_analyses.analysis_category")

	var newCategoryAnalysisIDs []ts.AnalysisID
	err := query.Table("ts_analyses").
		Select("max(ts_analyses.id) as max_id").
		Having("count(*) = 1").
		Pluck("max_id", &newCategoryAnalysisIDs).
		Error
	if err != nil {
		return nil, errors.Wrap(err, "find analyses has failed")
	}

	if len(newCategoryAnalysisIDs) == 0 {
		return m, nil
	}

	// Load the full analyses
	filter.AnalysisIDs = newCategoryAnalysisIDs
	newCategoryAnalyses, err := mysql.FindWithAnalysisFilter(ctx, filter, db, &ts.FindOptions{
		Preloads: []string{"Tool", "ToolVersion"},
	})
	if err != nil {
		return nil, errors.Wrap(err, "find analyses has failed")
	}

	for _, analysis := range newCategoryAnalyses {
		mp := analysis.MatchingParams()
		if _, ok := candidateAnalyses[mp]; ok {
			m[mp] = candidateAnalyses[mp]
		}
	}

	return m, nil
}

// getUnresolvedLogicalAlerts returns the logical alerts with the specified ids
func (s *Service) getUnresolvedLogicalAlerts(ctx context.Context, repoID ts.RepositoryEID, ids []ts.LogicalAlertID) (map[ts.LogicalAlertID]*ts.LogicalAlert, error) {
	_, span := o11y.StartSpan(ctx)
	defer span.End()

	query := s.db.Table("ts_logical_alerts").
		Where("repository_id = ? AND id in (?)", repoID, ids).
		Where("ts_logical_alerts.resolution in (?)", ts.AlertResolutionNone).
		Preload("Rule")

	logicalAlerts := []*ts.LogicalAlert{}
	err := query.Find(&logicalAlerts).Error
	if err != nil {
		return nil, errors.Wrap(err, "finding logical alerts has failed")
	}

	mapped := transforms.IndexBy(logicalAlerts, func(la *ts.LogicalAlert) ts.LogicalAlertID {
		return la.ID
	})

	return mapped, nil
}

func (s *Service) fetchArchivedPhysicalAlerts(ctx context.Context, unarchiver AnalysisUnarchiver, analyses []*ts.Analysis) ([]*ts.PhysicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	if len(analyses) == 0 {
		return nil, nil
	}

	err := unarchiver.Unarchive(ctx, analyses...)
	if err != nil {
		return nil, err
	}
	var out []*ts.PhysicalAlert
	for _, analysis := range analyses {
		for _, pa := range analysis.PhysicalAlerts {
			pa.Analysis = analysis // fill the analysis association reference
			out = append(out, pa)
		}
	}

	return out, nil
}

// Given a set of analyses, returns the alerts that are present in the changed lines (given inside the PRAlertsOpts)
func (s *Service) getAffectedAlerts(ctx context.Context, unarchiver AnalysisUnarchiver, repoID ts.RepositoryEID, analyses []ts.Analysis, fileChangesMap map[string][]*proto.Change, opts *ts.PRAlertsOpts) (map[ts.LogicalAlertID]*ts.PhysicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	if len(analyses) == 0 {
		return nil, nil
	}

	// 1. Split analyses into archived and live
	liveAnalyses := map[ts.AnalysisID]*ts.Analysis{}
	var archivedAnalyses []*ts.Analysis
	for i, analysis := range analyses {
		if analysis.ArchivalDataUrl != "" {
			archivedAnalyses = append(archivedAnalyses, &analyses[i])
		} else {
			analysisCopy := analysis
			liveAnalyses[analysis.ID] = &analysisCopy
		}
	}

	// 2. Variables that we want to populate in the loop
	logicalsToCanonical := map[ts.LogicalAlertID]*ts.PhysicalAlert{}
	alertReasons := map[string]int{"location": 0, "related_location": 0, "code_flow": 0}

	start := time.Now()
	cursorStart := ts.PhysicalAlertID(0)
	cursor := &cursorStart

	// 3. Populate the first chunk with the archived alerts
	physicalAlerts, err := s.fetchArchivedPhysicalAlerts(ctx, unarchiver, archivedAnalyses)
	if err != nil {
		return nil, err
	}

	appctx.Stats(ctx).DistributionMs("pr_alerts.alerts", stats.Tags{"analysis_type": "archived"}, time.Since(start))
	appctx.Logger(ctx).Info("PR alerts coming from the archive",
		repoID.AsKVP(),
		kvp.String("base_ref", opts.BaseRef),
		kvp.Strings("after_commits", toStrings(opts.AfterCommits)),
		kvp.Int("amount", len(physicalAlerts)),
	)

	var liveFetchTime time.Duration
	for {
		if err := appctx.ContextError(ctx, "get_affected_alerts"); err != nil {
			return nil, err
		}

		// Process chunk
		for _, pa := range physicalAlerts {
			inclusionReason := getInclusionReason(pa, fileChangesMap)

			if inclusionReason != "" {
				appctx.Stats(ctx).Counter("pr_alerts.inclusion_reason", stats.Tags{"reason": inclusionReason}, 1)
				alertReasons[inclusionReason]++

				if inclusionReason != "" {
					_, ok := logicalsToCanonical[pa.LogicalAlertID]
					if !ok {
						logicalsToCanonical[pa.LogicalAlertID] = pa
					}
				}
			}
		}

		// There is a next chunk?
		if len(liveAnalyses) == 0 || cursor == nil || (*cursor > 0 && len(physicalAlerts) < prAlertsChunkSize) {
			break
		}

		// Load next chunk
		start = time.Now()
		physicalAlerts, cursor, err = s.getPhysicalAlerts(ctx, repoID, liveAnalyses, prAlertsChunkSize, *cursor)
		if err != nil {
			return nil, err
		}
		liveFetchTime += time.Since(start)
	}

	appctx.Stats(ctx).DistributionMs("pr_alerts.alerts", stats.Tags{"analysis_type": "live"}, liveFetchTime)

	fields := []kvp.Field{
		repoID.AsKVP(),
		kvp.String("base_ref", opts.BaseRef),
		kvp.Strings("after_commits", toStrings(opts.AfterCommits)),
	}
	for k, v := range alertReasons {
		fields = append(fields, kvp.Int(k, v))
	}
	appctx.Logger(ctx).Info("PR alerts inclusion reasons", fields...)

	return logicalsToCanonical, nil
}

func (s *Service) getPhysicalAlerts(ctx context.Context, repoID ts.RepositoryEID, analyses map[ts.AnalysisID]*ts.Analysis, limit uint32, cursor ts.PhysicalAlertID) ([]*ts.PhysicalAlert, *ts.PhysicalAlertID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, s.db)

	if len(analyses) == 0 {
		return nil, nil, nil
	}

	query := db.
		Where("repository_id = ?", repoID).
		Where("analysis_id IN (?)", maps.Keys(analyses)).
		Where("NOT is_fixed").
		Where("id > ?", cursor).
		Order("id ASC").
		Limit(limit).
		Preload("RelatedLocations")

	physicalAlerts := []*ts.PhysicalAlert{}
	err := query.Find(&physicalAlerts).Error
	if err != nil {
		return nil, nil, errors.Wrap(err, "fetching physical alerts has failed")
	}

	var nextCursor *ts.PhysicalAlertID
	if len(physicalAlerts) > 0 {
		for _, pa := range physicalAlerts {
			pa.Analysis = analyses[pa.AnalysisID] // fill in association
		}
		nextCursor = &physicalAlerts[len(physicalAlerts)-1].ID
	}

	return physicalAlerts, nextCursor, nil
}

func getInclusionReason(pa *ts.PhysicalAlert, fileChangesMap map[string][]*proto.Change) string {
	// First check the result location
	region := pa.Region

	if region == (ts.Region{}) {
		// if regions is empty, we need will do a best effort with the canonical logical alert
		// which if it is new in the branch will have the correct region in the logical alert
		// but if it's not new, then it could be off, but will still be in the same file and we
		// can't do better
		if pa.LogicalAlert != nil {
			region = pa.LogicalAlert.Region
		} else {
			return ""
		}
	}

	filePath := pa.FilePath

	if pa.LogicalAlert != nil {
		filePath = pa.LogicalAlert.FilePath
	}

	if alertIntersectsAnyChange(&region, fileChangesMap[filePath]) {
		return "location"
	}

	// Then check the related locations
	for _, rl := range pa.RelatedLocations {
		if alertIntersectsAnyChange(&rl.Region, fileChangesMap[rl.FilePath]) {
			return "related_location"
		}
	}

	return ""
}

func (s *Service) getAnalyses(ctx context.Context, repoID ts.RepositoryEID, toolIDs []ts.ToolID, commitOIDs []ts.Sha, refs [][]byte) (ts.MP2Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	if len(commitOIDs) == 0 {
		return nil, ts.ErrAnalysisNotFound
	}

	// 1. Get the highest id of the successful analysis per(tool, category, commit)
	filter := ts.AnalysisFilter{
		RepositoryID:    repoID,
		ExcludeFork:     false, // Include analysis on PRs as After (i.e., head) of the Diff. This enables comparing refs of the form refs/pull/:id
		State:           ts.AnalysisStateFilterSuccessful,
		IncludeOutdated: true,
	}

	if len(refs) > 0 {
		filter.Refs = refs
	}

	if len(toolIDs) > 0 {
		filter.ToolIDs = toolIDs
	}

	query := mysql.ApplyAnalysisFilter(filter, db).Where("ts_analyses.commit_oid IN (?)", commitOIDs)
	query = query.Group("ts_analyses.tool_id, ts_analyses.analysis_category, ts_analyses.commit_oid")

	var analysisIDs []ts.AnalysisID
	err := query.Table("ts_analyses").
		Select("max(ts_analyses.id) as max_id"). // By doing the max() we get only one result (the most recent) per group (of tool, category, commit)
		Pluck("max_id", &analysisIDs).
		Error
	if err != nil {
		return nil, errors.Wrap(err, "find analyses has failed")
	}
	// Return early if no analyses where found
	m := make(ts.MP2Analysis)
	if len(analysisIDs) == 0 {
		return m, nil
	}

	// 2. Load the full analyses
	filter.AnalysisIDs = analysisIDs
	analyses, err := mysql.FindWithAnalysisFilter(ctx, filter, db, &ts.FindOptions{
		Preloads: []string{"Tool", "ToolVersion"},
	})
	if err != nil {
		return nil, errors.Wrap(err, "find analyses has failed")
	}

	// 3. Build the result maintaining the commitOIDs priorities
	commitPriorities := make(map[ts.Sha]int)
	for n, commitOid := range commitOIDs {
		commitPriorities[commitOid] = len(commitOIDs) - n // Priority goes in decreasing order from first to last
	}

	for _, analysis := range analyses {
		existing, present := m[analysis.MatchingParams()]
		if !present || commitPriorities[analysis.CommitOid] > commitPriorities[existing.CommitOid] {
			m[analysis.MatchingParams()] = analysis
		}
	}

	return m, nil
}

func (s *Service) getBaseRefAnalyses(ctx context.Context, repoID ts.RepositoryEID, toolIDs []ts.ToolID, baseRef string) (ts.MP2Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	filter := ts.AnalysisFilter{
		RepositoryID:    repoID,
		ToolIDs:         toolIDs,
		ExcludeFork:     true,
		State:           ts.AnalysisStateFilterMostRecent,
		Refs:            [][]byte{[]byte(baseRef)},
		IncludeOutdated: false,
	}

	opt := &ts.FindOptions{
		Preloads: []string{"Tool", "ToolVersion"},
	}
	analyses, err := mysql.FindWithAnalysisFilter(ctx, filter, s.db, opt)
	if err != nil {
		return nil, errors.Wrap(err, "find analyses has failed")
	}

	res := make(ts.MP2Analysis)
	for _, analysis := range analyses {
		res[analysis.MatchingParams()] = analysis
	}
	return res, nil
}

// getMissingBaseRefAnalyses returns the set of baseRefAnalyses that are not present in analyses
// like the tool status page, it ignores baseRefAnalyses that are older than 90 days and considered inactive
func getMissingBaseRefAnalyses(baseRefAnalyses ts.MP2Analysis, analyses ts.MP2Analysis) []ts.Analysis {
	// This horizon must match the value used in the tool status page.
	// https://github.com/github/github/blob/f2d9d772dad0ed05c5f3ca52f554fe56b56d0cba/packages/security_products/app/models/code_scanning/status.rb#L266
	ninetyDaysAgo := time.Now().Add(-time.Hour * 24 * 90)

	return transforms.FilterMap(maps.Keys(baseRefAnalyses), func(k ts.MatchingParameters) (ts.Analysis, bool) {
		baseRefAnalysis := baseRefAnalyses[k]

		// If the analysis is older than 90 days, we don't require it to be present on the PR
		if baseRefAnalysis.CreatedAt.Before(ninetyDaysAgo) {
			return baseRefAnalysis, false
		}

		// If an analysis is missing we return the corresponding baseRefAnalysis that causes us to expect it.
		_, found := analyses[k]

		return baseRefAnalysis, !found
	})
}

func getCandidateNewCategoryAnalyses(baseRefAnalyses ts.MP2Analysis, analyses ts.MP2Analysis) ts.MP2Analysis {
	candidates := make(ts.MP2Analysis)

	for mp, analysis := range analyses {
		// An analysis category can only be new if we can't find a base ref analysis with a matching category.
		// Note that this does not guarantee it is new, hence why we treat it as a _candidate_.
		if _, ok := baseRefAnalyses[mp]; !ok {
			candidates[mp] = analysis
		}
	}

	return candidates
}

func fileChangesToMaps(fileChanges []*proto.FileChange) (map[string][]*proto.Change, map[string][]*proto.Change) {
	added := map[string][]*proto.Change{}
	removed := map[string][]*proto.Change{}
	for _, fc := range fileChanges {
		existingAdded := added[fc.FilePath]
		existingRemoved := removed[fc.FilePath]

		for _, c := range fc.Changes {
			if c.Added {
				existingAdded = append(existingAdded, c)
			} else {
				existingRemoved = append(existingRemoved, c)
			}
		}

		if len(existingAdded) > 0 {
			added[fc.FilePath] = existingAdded
		}

		if len(existingRemoved) > 0 {
			removed[fc.FilePath] = existingRemoved
		}
	}
	return added, removed
}

func alertIntersectsAnyChange(alertRegion *ts.Region, changes []*proto.Change) bool {
	for _, c := range changes {
		// We only consider the start line of the alert's region, because we
		// show annotations on the start line of an alert, so there isn't really
		// a motivation to consider the end line. If the start line is outside
		// the diff but the end line isn't, then there isn't a good place to
		// show the alert. Finally, almost all alerts have single-line
		// locations.
		if c.StartLine <= alertRegion.StartLine && alertRegion.StartLine <= c.EndLine {
			return true
		}
	}

	return false
}

type AlertService interface {
	Alerts(ctx context.Context, repoID ts.RepositoryEID, alertFilter ts.AlertFilter, analysisFilter ts.AnalysisFilter, options *ts.FindOptions) ([]*ts.LogicalAlert, error)
}

func (s *Service) AnnotationAlerts(ctx context.Context, repoID ts.RepositoryEID, numbers []uint32, commitOIDs []ts.Sha, liveAlerts AlertService, historicalAlerts AnalysisUnarchiver) ([]*ts.LogicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	analyses, err := s.getAnalyses(ctx, repoID, []ts.ToolID{}, commitOIDs, nil)
	if err != nil {
		return nil, err
	}

	if len(analyses) == 0 {
		appctx.Logger(ctx).Info("no diff analyses found",
			repoID.AsKVP(),
			kvp.Uint32s("gh.turboscan.numbers", numbers),
			kvp.Strings("gh.commit.shas", toStrings(commitOIDs)),
		)
		return nil, nil
	}

	archivedAnalyses := make([]*ts.Analysis, 0, len(analyses))

	analysisIDs := make([]ts.AnalysisID, 0, len(analyses))
	for _, analysis := range maps.Values(analyses) {
		if analysis.ArchivalDataUrl != "" {
			archivedAnalyses = append(archivedAnalyses, &analysis)
		}
		analysisIDs = append(analysisIDs, analysis.ID)
	}

	var logicalAlertsFromArchive []*ts.LogicalAlert
	if len(archivedAnalyses) > 0 {
		start := time.Now()
		logicalAlertsFromArchive, err = historicalAlerts.UnarchiveAlerts(ctx, repoID, numbers, archivedAnalyses...)
		if err != nil {
			return nil, err
		}
		appctx.Stats(ctx).DistributionMs("diff_alerts.alerts", stats.Tags{"analysis_type": "historic"}, time.Since(start))
	}

	// Since archivedAnalyses won't include any fixed alerts, and we still want the ones for the most recent commit,
	// we'll need to fetch those from the db.
	// This will also cover all GHES analyses that are not yet archived.
	var logicalAlertsFromLive []*ts.LogicalAlert
	start := time.Now()
	options := &ts.FindOptions{
		Pagination: &ts.Pagination{
			Limit: uint32(len(numbers)),
		},
		Preloads: []string{
			"Rule",
			"Rule.Tags",
			"Rule.Tool",
			"PhysicalAlerts",
			"PhysicalAlerts.RelatedLocations",
			"PhysicalAlerts.Analysis",
			"PhysicalAlerts.Analysis.Tool",
			"PhysicalAlerts.Analysis.ToolVersion",
			"PhysicalAlerts.LastSeenAnalysis",
		},
		SortBy: alert.SortBy(proto.AlertSortOrder_WEIGHT),
	}

	logicalAlertsFromLive, err = liveAlerts.Alerts(ctx, repoID, ts.AlertFilter{Numbers: numbers}, ts.AnalysisFilter{RepositoryID: repoID, AnalysisIDs: analysisIDs, IncludeOutdated: true}, options)
	if err != nil {
		return nil, err
	}
	appctx.Stats(ctx).DistributionMs("diff_alerts.alerts", stats.Tags{"analysis_type": "live"}, time.Since(start))
	logicalAlerts := mergeLiveAndHistoric(logicalAlertsFromLive, logicalAlertsFromArchive)

	// Sort alerts into the order determined by the passed-in numbers
	indexByNumber := make(map[uint32]int)
	for i, n := range numbers {
		indexByNumber[n] = i
	}
	sort.Slice(logicalAlerts, func(i, j int) bool {
		return indexByNumber[logicalAlerts[i].Number] < indexByNumber[logicalAlerts[j].Number]
	})

	return logicalAlerts, nil
}

func mergeLiveAndHistoric(live, historic []*ts.LogicalAlert) []*ts.LogicalAlert {
	if len(historic) == 0 {
		return live
	} else if len(live) == 0 {
		return historic
	}

	m := transforms.IndexBy(live, func(la *ts.LogicalAlert) ts.LogicalAlertID { return la.ID })

	for _, la := range historic {
		laInMap, ok := m[la.ID]
		// In case when a logical alert is both in live and historic, we prefer the more recent one
		if !ok || laInMap.PhysicalAlerts[0].Analysis.CreatedAt.Time.Before(la.PhysicalAlerts[0].Analysis.CreatedAt.Time) {
			m[la.ID] = la
		}
	}

	return maps.Values(m)
}

func toStrings(in []ts.Sha) []string {
	strs := make([]string, len(in))
	for i, sha := range in {
		strs[i] = sha.String()
	}
	return strs
}
