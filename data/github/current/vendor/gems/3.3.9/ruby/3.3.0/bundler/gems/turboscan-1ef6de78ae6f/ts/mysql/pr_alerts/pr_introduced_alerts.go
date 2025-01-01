package pr_alerts

import (
	"context"
	"fmt"
	"sort"

	"github.com/SamuelTissot/sqltime"
	"github.com/pkg/errors"
	"golang.org/x/exp/maps"

	"github.com/jinzhu/gorm"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/mysql"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/github/turboscan/ts/transforms"
)

type IntroducedAlert struct {
	PhysicalAlert *ts.PhysicalAlert
	FixedAt       *sqltime.Time
	IntroducedAt  *sqltime.Time
}

type AlertSet map[ts.LogicalAlertID]*ts.PhysicalAlert

func (s AlertSet) Add(alert *ts.PhysicalAlert) {
	s[alert.LogicalAlertID] = alert
}
func (s AlertSet) AddMany(alerts []*ts.PhysicalAlert) {
	for _, alert := range alerts {
		s.Add(alert)
	}
}

func (s AlertSet) SortedValues() []*ts.PhysicalAlert {
	elements := maps.Values(s)
	sort.Slice(elements, func(i, j int) bool {
		return elements[i].ID < elements[j].ID
	})
	return elements
}

func (s AlertSet) LogicalAlertNumbers() []uint32 {
	return transforms.Map(maps.Values(s), func(a *ts.PhysicalAlert) uint32 { return a.LogicalAlert.Number })
}

func (s *Service) getAnalysesForPullRequestIntroducedAlerts(ctx context.Context, repoID ts.RepositoryEID, refs [][]byte, toolIDs []ts.ToolID) ([]ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	filter := ts.AnalysisFilter{
		RepositoryID: repoID,
		State:        ts.AnalysisStateFilterMostRecent,
		ToolIDs:      toolIDs,
		Refs:         refs,
	}
	analyses, err := mysql.FindWithAnalysisFilter(ctx, filter, db, &ts.FindOptions{
		Preloads: []string{"Tool", "ToolVersion"},
	})
	if err != nil {
		return nil, errors.Wrap(err, "find analyses has failed")
	}
	return analyses, nil
}

func (s *Service) PullRequestIntroducedAlerts(ctx context.Context, unarchiver AnalysisUnarchiver, repoID ts.RepositoryEID, opts *ts.PRAlertsOpts) ([]*IntroducedAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// This endpoint only cares about Alerts introduced in the PR
	// Therefor, we scope by the analyses that belong to the PR early on.
	// We will miss analysis triggered by `on: push` workflows, but that is expected.
	r := [][]byte{
		[]byte(fmt.Sprintf("refs/pull/%d/merge", opts.PRNumber)),
		[]byte(fmt.Sprintf("refs/pull/%d/head", opts.PRNumber)),
	}
	tips, err := s.getAnalysesForPullRequestIntroducedAlerts(ctx, repoID, r, opts.ToolIDs)
	if err != nil {
		return nil, err
	}

	if len(tips) == 0 {
		appctx.Logger(ctx).Info("PullRequestIntroducedAlerts: Cannot find tip analyses or ref",
			repoID.AsKVP(),
			kvp.String("gh.turboscan.tools", fmt.Sprint(opts.ToolIDs)),
		)
		return []*IntroducedAlert{}, nil
	}

	// First analysis to provide the ref, as they must all be the same
	ref := tips[0].Ref
	for _, tip := range tips {
		if string(tip.Ref) != string(ref) {
			appctx.Logger(ctx).Error("PullRequestIntroducedAlerts: Mismatched refs found",
				repoID.AsKVP(),
				kvp.String("expected_ref", string(ref)),
				kvp.String("found_ref", string(tip.Ref)),
			)
		}
	}

	// Find the PR alerts using simplify-diff mechanism. We are interested in the alerts that were introduced in the PR and are still open.
	fileChangesAddedMap, _ := fileChangesToMaps(opts.FileChanges)
	affectedAlerts, err := s.getAffectedAlerts(ctx, unarchiver, repoID, tips, fileChangesAddedMap, opts)
	if err != nil {
		return nil, err
	}
	// Fetch their Logical alerts to preload the association
	newLogicalAlertMap, err := s.getLogicalAlerts(ctx, repoID, maps.Keys(affectedAlerts))
	if err != nil {
		return nil, err
	}
	for _, alert := range affectedAlerts {
		alert.LogicalAlert = newLogicalAlertMap[alert.LogicalAlertID]
	}

	// Now we need to figure out the alerts that were introduced in the PR but were also fixed within the PR.
	// Fetch all BASE analyses
	bases, err := s.getFirstAnalysesForRef(ctx, repoID, ref)
	if err != nil {
		return nil, err
	}
	var fixedAlerts []*ts.PhysicalAlert
	if len(bases) > 0 {
		var firstAnalysisID ts.AnalysisID
		// Find the first analysis ID
		for _, a := range bases {
			if firstAnalysisID == 0 || a.ID < firstAnalysisID {
				firstAnalysisID = a.ID
			}
		}

		var tipIDs []ts.AnalysisID
		for _, tip := range tips {
			tipIDs = append(tipIDs, tip.ID)
		}
		fixedAlerts, err = s.introducedAndFixedAlertsInPR(ctx, repoID, tipIDs, firstAnalysisID)
		if err != nil {
			return nil, err
		}
	}

	alertsSet := make(AlertSet)
	// First add the new alerts
	alertsSet.AddMany(maps.Values(affectedAlerts))
	// Later the fixed alerts, so they overwrite the news ones
	alertsSet.AddMany(fixedAlerts)

	// Check timeline events:
	// If the alert was introduced in the PR, we should be able to find a timeline event for it
	// Unless it was re-introduced in the first analysis.
	timelineEventsByLogicalAlertID, err := s.findTimelineEvents(ctx, repoID, alertsSet.LogicalAlertNumbers(), string(ref))
	if err != nil {
		return nil, err
	}

	var introAlerts []*IntroducedAlert
	for _, alert := range alertsSet.SortedValues() {
		a := &IntroducedAlert{PhysicalAlert: alert}
		if v, ok := timelineEventsByLogicalAlertID[alert.LogicalAlertID]; ok {
			introAt := v.EventTimestamp
			a.IntroducedAt = &introAt
			if alert.IsFixed {
				// LastObservedFixAt is not stored in the db
				// but rather calculated when the fixed alert is loaded by the
				// `introducedAndFixedAlertsInPR` function.
				a.FixedAt = alert.LogicalAlert.LastObservedFixAt
			}
			introAlerts = append(introAlerts, a)
		} else if !alert.IsFixed {
			// When we can't find a timeline event. If the alert is new
			// we should be able to assume it was introduced in the first analysis
			var introAt sqltime.Time
			if len(bases) == 0 {
				// If we cannot find the first analysis, we just have to go with the tip analyis time
				introAt = alert.Analysis.CreatedAt
			} else {
				introAt = bases[0].CreatedAt
			}
			a.IntroducedAt = &introAt
			introAlerts = append(introAlerts, a)

			// Note: if the alert is fixed and we didn't find a timeline event, we don't add it to the list
			// as that was a pre-existing alert that was fixed in the PR
		}
	}

	return introAlerts, nil
}

func (s *Service) getFirstAnalysesForRef(ctx context.Context, repoID ts.RepositoryEID, ref []byte) ([]*ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))
	var analyses []*ts.Analysis

	filter := ts.AnalysisFilter{
		RepositoryID:    repoID,
		ExcludeFork:     false, // Include analysis on PRs as After (i.e., head) of the Diff. This enables comparing refs of the form refs/pull/:id
		State:           ts.AnalysisStateFilterSuccessful,
		IncludeOutdated: true,
		Refs:            [][]byte{ref},
	}

	query := mysql.ApplyAnalysisFilter(filter, db)
	query = query.Where("baseline_id IS NULL").
		Preload("Tool").Preload("ToolVersion")

	err := query.Find(&analyses).Error
	return analyses, err
}

// introducedAndFixedAlertsInPR returns the alerts that were introduced and fixed in the PR.
// Note: some post-filter needs to happen, as the results list might cointain alerts that were not introduced in the PR however were fixed in it.
func (s *Service) introducedAndFixedAlertsInPR(
	ctx context.Context,
	repoID ts.RepositoryEID,
	tipIDs []ts.AnalysisID,
	baseAnalysisID ts.AnalysisID) (res []*ts.PhysicalAlert, err error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))
	cursor := ts.PhysicalAlertID(0)

	var physicalAlerts []*ts.PhysicalAlert
	var baselines []ts.AnalysisID
	for {
		if cursor > 0 && len(physicalAlerts) < prAlertsChunkSize {
			break
		}

		query := db.
			Where("repository_id = ?", repoID).
			Where("analysis_id IN (?)", tipIDs).
			Where("id > ?", cursor).
			Where("last_seen_analysis_id >= ?", baseAnalysisID). // Only return alerts fixed after the analysis we are comparing to
			Order("id ASC").
			Limit(prAlertsChunkSize).
			Preload("RelatedLocations").
			Preload("LogicalAlert").
			Preload("Analysis.Tool")

		physicalAlerts := []*ts.PhysicalAlert{}
		err = query.Find(&physicalAlerts).Error
		if err != nil {
			return nil, errors.Wrap(err, "fetching physical alerts has failed")
		}

		if len(physicalAlerts) > 0 {
			cursor = physicalAlerts[len(physicalAlerts)-1].ID
			for _, pa := range physicalAlerts {
				res = append(res, pa)
				baselines = append(baselines, *pa.LastSeenAnalysisID)
			}
		} else {
			break // No more alerts
		}
	}

	if len(baselines) > 0 {
		// Find when the alerts were fixed
		var fixingAnalyses []*ts.Analysis
		err = db.Table("ts_analyses").
			Select("baseline_id, created_at").
			Where("repository_id = ?", repoID).
			Where("baseline_id IN (?)", baselines).
			Find(&fixingAnalyses).Error
		if err != nil {
			return nil, err
		}
		maxCreatedAtByBaseline := map[ts.AnalysisID]sqltime.Time{}
		for _, a := range fixingAnalyses {
			if fixedAt, ok := maxCreatedAtByBaseline[*a.BaselineID]; ok {
				if a.CreatedAt.After(fixedAt.Time) {
					maxCreatedAtByBaseline[*a.BaselineID] = a.CreatedAt
				}
			} else {
				maxCreatedAtByBaseline[*a.BaselineID] = a.CreatedAt
			}
		}
		for _, pa := range res {
			fixingAnalysisCreatedAt, ok := maxCreatedAtByBaseline[*pa.LastSeenAnalysisID]
			if ok {
				pa.LogicalAlert.LastObservedFixAt = &fixingAnalysisCreatedAt
			}
		}
	}

	return
}

func (s *Service) getLogicalAlerts(ctx context.Context, repoID ts.RepositoryEID, ids []ts.LogicalAlertID) (map[ts.LogicalAlertID]*ts.LogicalAlert, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	query := db.Table("ts_logical_alerts").
		Where("repository_id = ? AND id in (?)", repoID, ids)

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

// findTimelineEvents retrieves timeline events for the alert numbers and ref.
// That are of an 'introductory' nature (i.e., AlertCreated, AlertAppearedInBranch, AlertReappeared).
func (s *Service) findTimelineEvents(ctx context.Context, repoID ts.RepositoryEID, logicalAlertNOs []uint32, ref string) (map[ts.LogicalAlertID]*ts.TimelineEvent, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	db := otelgorm.SetSpanToGorm(ctx, gormext.TryGetReplica(ctx, s.db))

	var events []*ts.TimelineEvent

	// if the event relates to a specific analysis (which is the case for several event types, but not all),
	// we only want to fetch the event if the analysis has been marked as complete (i.e., everything from that analysis was committed
	// to the database).
	db = db.Select("ts_timeline_events.*").Model(ts.TimelineEvent{}).
		Joins("LEFT JOIN ts_analyses a ON a.id = ts_timeline_events.analysis_id AND a.repository_id = ts_timeline_events.repository_id").
		Joins("JOIN ts_logical_alerts la ON la.id = ts_timeline_events.logical_alert_id AND la.repository_id = ts_timeline_events.repository_id").
		Where("la.number IN (?)", logicalAlertNOs).
		Where("ts_timeline_events.repository_id = ?", repoID).
		Where("ts_timeline_events.ref = ?", ref).
		Where("ts_timeline_events.event_type IN (?)", []ts.TimelineEventType{ts.TimelineEventTypeAlertCreated, ts.TimelineEventTypeAlertAppearedInBranch, ts.TimelineEventTypeAlertReappeared}).
		Where("(a.analysis_complete = TRUE OR a.id IS NULL)")
	err := db.Find(&events).Error
	if gorm.IsRecordNotFoundError(err) {
		return nil, ts.ErrTimeLineEventsNotFound
	} else if err != nil {
		return nil, errors.Wrap(err, "finding timeline events has failed")
	}

	timelineEventsByLogicalAlertID := make(map[ts.LogicalAlertID]*ts.TimelineEvent)
	for _, te := range events {
		// prefer TimelineEventTypeAlertCreated over other events
		if te.EventType == ts.TimelineEventTypeAlertCreated {
			timelineEventsByLogicalAlertID[te.LogicalAlertID] = te
		} else {
			if _, ok := timelineEventsByLogicalAlertID[te.LogicalAlertID]; !ok {
				timelineEventsByLogicalAlertID[te.LogicalAlertID] = te
			}
		}
	}

	return timelineEventsByLogicalAlertID, nil
}
