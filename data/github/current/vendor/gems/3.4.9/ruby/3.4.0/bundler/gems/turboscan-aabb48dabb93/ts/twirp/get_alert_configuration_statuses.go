package twirp

import (
	"context"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/timeline"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/tstypes"
	"github.com/github/turboscan/ts/twirp/twerrors"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
)

// GetAlertConfigurationStatuses returns information about the status of an alert in all configurations where that alert has been detected.
// It is used for the Affected Branches section of the alert show page.
func (r *ResultsResolver) GetAlertConfigurationStatuses(ctx context.Context, req *proto.AlertConfigurationStatusesRequest) (*proto.AlertConfigurationStatusesResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(attribute.Int("gh.turboscan.alert_number", int(req.AlertNumber))),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint64("gh.turboscan.alert_number", uint64(req.AlertNumber)),
		kvp.Uint64("gh.turboscan.limit", uint64(req.Limit)),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}
	if req.AlertNumber == 0 {
		return nil, twerrors.RequiredArgumentError("alert_number")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	// attempt to use a replica for this endpoint if available
	ctx = gormext.WithTryReplica(ctx, true)

	alerts, err := r.alertService.LogicalAlerts(ctx, repoID, []uint32{req.AlertNumber}, []string{"DefaultConfiguration"})
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	if len(alerts) == 0 {
		return nil, o11y.RecordError(span, twerrors.NotFoundError("alert not found"))
	}
	logicalAlert := alerts[0]

	if logicalAlert.DefaultConfiguration == nil {
		// No default configuration means the alert does not have any associated physical alerts, so we should return a 404
		return nil, o11y.RecordError(span, twerrors.NotFoundError("could not find result"))
	}

	alertFilter := ts.AlertFilter{
		IDs:   []ts.LogicalAlertID{logicalAlert.ID},
		State: proto.AlertStateFilter_ALERT_STATE_FILTER_ALL,
	}
	analysisFilter := ts.AnalysisFilter{
		RepositoryID: repoID,
		BranchesOnly: true,
		State:        ts.AnalysisStateFilterMostRecent,
	}

	// TODO: Page is set to 1 but should be configurable from Twirp request.
	pagination := tstypes.CreatePaginationInfo(req.Limit, 1)
	options := &ts.FindOptions{
		Preloads:   []string{"Analysis", "Analysis.Tool", "Analysis.ToolVersion", "LastSeenAnalysis"},
		Pagination: &pagination,
	}

	physicalAlerts, err := r.alertService.PhysicalAlerts(ctx, repoID, alertFilter, analysisFilter, options)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	var timelineEventsPerConfiguration map[ts.ConfigurationID][]*ts.TimelineEvent
	var initialAnalysesPerConfiguration map[ts.ConfigurationID]*ts.Analysis

	if len(physicalAlerts) > 0 {
		timelineEventsPerConfiguration, err = getTimelineEventsPerConfiguration(ctx, r.timelineEventService, logicalAlert.ID)
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}

		initialAnalysesPerConfiguration, err = getInitialAnalysesForAlerts(ctx, r.alertService, repoID, physicalAlerts)
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
	}

	configStatuses := make([]*proto.AlertConfigurationStatus, 0, len(physicalAlerts))
	for _, pa := range physicalAlerts {
		configurationID := pa.Analysis.ConfigurationID
		events := timelineEventsPerConfiguration[configurationID]

		var createdAt *sqltime.Time
		var createdAtCommit ts.Sha

		createdAtEvent := getAlertIntroductionEvent(events)
		createdAtSource := "none"
		if createdAtEvent != nil {
			createdAtSource = "timeline_event"
			createdAt = &createdAtEvent.CreatedAt
			createdAtCommit = createdAtEvent.CommitOid
		} else if initialAnalysis, ok := initialAnalysesPerConfiguration[configurationID]; ok {
			createdAtSource = "initial_analysis"
			createdAt = &initialAnalysis.CreatedAt
			createdAtCommit = initialAnalysis.CommitOid
		}

		appctx.Stats(ctx).Counter("twirp.get_alert_configuration_statuses.alert_introduction", stats.Tags{"source": createdAtSource}, 1)

		var fixedAt *sqltime.Time
		var fixedAtCommit ts.Sha
		if pa.IsFixed && pa.LastSeenAnalysis != nil {
			fixedAt = &pa.LastSeenAnalysis.CreatedAt
			fixedAtCommit = pa.LastSeenAnalysis.CommitOid
		}

		configStatus := serializeAlertConfigurationStatus(pa.Analysis, createdAt, createdAtCommit, fixedAt, fixedAtCommit)
		configStatuses = append(configStatuses, configStatus)
	}

	return &proto.AlertConfigurationStatusesResponse{
		Statuses: configStatuses,
	}, nil
}

func getTimelineEventsPerConfiguration(ctx context.Context, timelineEventService *timeline.Service, id ts.LogicalAlertID) (map[ts.ConfigurationID][]*ts.TimelineEvent, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	timelineEventFilter := ts.TimelineEventFilter{
		LogicalAlertID: id,
		EventTypes: []ts.TimelineEventType{
			ts.TimelineEventTypeAlertAppearedInBranch,
			ts.TimelineEventTypeAlertCreated,
			ts.TimelineEventTypeAlertReappeared,
		},
	}
	timelineEvents, err := timelineEventService.FindTimelineEvents(ctx,
		&timelineEventFilter,
		&ts.FindOptions{
			Preloads: []string{"Analysis", "Analysis.Tool", "Analysis.ToolVersion"},
			SortBy:   "ts_timeline_events.event_timestamp",
		},
	)
	if err != nil {
		return nil, err
	}

	return transforms.GroupBy(timelineEvents, func(te *ts.TimelineEvent) ts.ConfigurationID {
		return te.Analysis.ConfigurationID
	}), nil
}

func getAlertIntroductionEvent(timelineEvents []*ts.TimelineEvent) *ts.TimelineEvent {
	var createdEvent *ts.TimelineEvent

	for _, te := range timelineEvents {
		// Prefer TimelineEventTypeAlertCreated over other events
		if te.EventType == ts.TimelineEventTypeAlertCreated {
			createdEvent = te
		} else if createdEvent == nil {
			createdEvent = te
		}
	}

	return createdEvent
}

func getInitialAnalysesForAlerts(ctx context.Context, alertService *alert.Service, repoID ts.RepositoryEID, physicalAlerts []*ts.PhysicalAlert) (map[ts.ConfigurationID]*ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	configurationIDs := transforms.MapUnique(physicalAlerts, func(p *ts.PhysicalAlert) ts.ConfigurationID {
		return p.Analysis.ConfigurationID
	})

	filter := ts.AnalysisFilter{
		RepositoryID: repoID,
		State:        ts.AnalysisStateFilterSuccessful,
	}
	analyses, err := alertService.InitialAnalysesForConfigurations(ctx, repoID, filter, configurationIDs)
	if err != nil {
		return nil, err
	}

	m := make(map[ts.ConfigurationID]*ts.Analysis)
	for _, a := range analyses {
		m[a.ConfigurationID] = &a
	}

	return m, nil
}
