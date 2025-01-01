package twirp

import (
	"context"
	"fmt"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/auditlog"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func (r *ResultsResolver) SetAlertsStatus(ctx context.Context, req *proto.SetAlertsStatusRequest) (*proto.SetAlertsStatusResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(
			attribute.Int("gh.turboscan.numbers.count", len(req.Numbers)),
			attribute.Int("gh.turboscan.resolver_id", int(req.ResolverId)),
		),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		ts.RepositoryEID(req.RepositoryId).AsKVP(),
		kvp.String("gh.turboscan.resolution", req.Resolution.String()),
		kvp.Uint64("gh.turboscan.resolver_id", uint64(req.ResolverId)),
		kvp.Uint64("gh.turboscan.numbers.count", uint64(len(req.Numbers))),
		kvp.ByteStrings("gh.turboscan.ref_names", req.RefNamesBytes),
	)

	if len(req.Numbers) == 0 {
		return nil, twerrors.RequiredArgumentError("numbers")
	}

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if req.ResolverId == 0 {
		return nil, twerrors.RequiredArgumentError("resolver_id")
	}

	resolution, err := resolutionFromProto(req.Resolution)
	if err != nil {
		return nil, twerrors.InvalidArgumentError("resolution", "")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)
	numbers := req.Numbers
	resolverID := ts.UserEID(req.ResolverId)
	resolutionNote := ts.ToNote(req.ResolutionNote)

	filter := ts.AlertFilter{
		Numbers: numbers,
		State:   proto.AlertStateFilter_ALERT_STATE_FILTER_ALL,
	}
	analysisFilter := ts.AnalysisFilter{
		RepositoryID:    repoID,
		Refs:            req.RefNamesBytes,
		State:           ts.AnalysisStateFilterMostRecent,
		IncludeOutdated: true,
	}

	options := &ts.FindOptions{
		Preloads: []string{
			"Rule",
			"Rule.Tags",
			"Rule.Tool",
			"PhysicalAlerts",
			"PhysicalAlerts.Analysis",
			"PhysicalAlerts.Analysis.ToolVersion",
			"PhysicalAlerts.Analysis.Tool",
			"PhysicalAlerts.LastSeenAnalysis",
		},
		Pagination: &ts.Pagination{
			Limit: uint32(len(numbers)),
		},
	}
	logicalAlerts, err := r.alertService.Alerts(ctx, repoID, filter, analysisFilter, options)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	// This can happen if one user deletes some alerts and the other user tries to dismiss those alerts.
	// There were two choices at this point, the first one was to return a partial success but that
	// provides a weird user experience such that the user wouldn't realise which dismissals
	// succeeded; the other choice was to fail early - we chose to fail early.
	if len(logicalAlerts) != len(numbers) {
		return nil, o11y.RecordError(span, twerrors.NotFoundError("could not find all specified alerts"))
	}

	updateTime := sqltime.Now()
	if resolution == ts.AlertResolutionNone {
		err = r.alertService.ReopenLogicalAlerts(ctx, logicalAlerts, updateTime)
	} else {
		err = r.alertService.ResolveLogicalAlerts(ctx, logicalAlerts, resolution, resolverID, resolutionNote, updateTime)
	}
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	lAlertsMap := map[ts.LogicalAlertID]*ts.LogicalAlert{}
	for _, la := range logicalAlerts {
		filter.IDs = append(filter.IDs, la.ID)
		lAlertsMap[la.ID] = la
	}

	auditLogContext := auditlog.AuditLogContext{
		Actor:      req.ResolverLogin,
		OrgID:      req.OrgId,
		Org:        req.Org,
		BusinessID: req.BusinessId,
		Business:   req.Business,
	}

	err = r.writeTimelineEventsForAlertResolutionChange(ctx, logicalAlerts, resolution, resolverID, resolutionNote, auditLogContext)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	// If elastic search is configured, then update the index
	if r.es != nil {
		esErr := r.indexAlertsStatusChange(ctx, repoID, filter.IDs, resolution, resolverID, updateTime)
		if esErr != nil {
			// At the moment we just ignore elastic search errors
			appctx.Logger(ctx).Error(
				fmt.Sprintf("Failed updating ES index when updating alert: %s", esErr),
				repoID.AsKVP(),
				kvp.Int("gh.turboscan.numbers.count", len(req.Numbers)),
			)

			appctx.Stats(ctx).Counter("es.dynamic_update.error", stats.Tags{"kind": "set_alert_status"}, 1)
		}
	}

	results := make([]*proto.Result, 0, len(logicalAlerts))
	for _, la := range logicalAlerts {
		result, err := serializeResult(*la)
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
		results = append(results, result)
	}

	return &proto.SetAlertsStatusResponse{
		Results: results,
	}, nil
}

// Should be called after we change the resolution state for a set of
// logical alerts in order to write appropriate timeline events
func (r *ResultsResolver) writeTimelineEventsForAlertResolutionChange(ctx context.Context, las []*ts.LogicalAlert, resolution ts.AlertResolution, userID ts.UserEID, resolutionNote ts.Note, auditLogContext auditlog.AuditLogContext) error {
	tes := []*ts.TimelineEvent{}
	now := sqltime.Now()
	var eventType ts.TimelineEventType
	if resolution == ts.AlertResolutionNone {
		eventType = ts.TimelineEventTypeAlertReopenedByUser
	} else {
		eventType = ts.TimelineEventTypeAlertResolvedByUser
	}
	for _, la := range las {
		tes = append(tes, &ts.TimelineEvent{
			RepositoryID:   la.RepositoryID,
			UserID:         &userID,
			EventType:      eventType,
			LogicalAlertID: la.ID,
			Resolution:     resolution,
			ResolutionNote: resolutionNote,
			EventTimestamp: now,
		})
	}

	err := r.timelineEventService.WriteTimelineEvents(ctx, tes)
	if err != nil {
		return err
	}

	for idx := range las {
		err = r.aeh.NewAlertEvent(ctx, las[idx], tes[idx], auditLogContext)
		if err != nil {
			return err
		}
	}
	return nil
}

func resolutionFromProto(rr proto.ResultResolution) (ts.AlertResolution, error) {
	var resolution ts.AlertResolution
	switch rr {
	case proto.ResultResolution_NO_RESOLUTION:
		resolution = ts.AlertResolutionNone
	case proto.ResultResolution_FALSE_POSITIVE:
		resolution = ts.AlertResolutionFalsePositive
	case proto.ResultResolution_WONT_FIX:
		resolution = ts.AlertResolutionWontFix
	case proto.ResultResolution_USED_IN_TESTS:
		resolution = ts.AlertResolutionUsedInTests
	default:
		return ts.AlertResolutionNone, errors.New("invalid alert resolution")
	}
	return resolution, nil
}

func (r *ResultsResolver) indexAlertsStatusChange(ctx context.Context, repoID ts.RepositoryEID, ids []ts.LogicalAlertID, resolution ts.AlertResolution, resolverID ts.UserEID, updatedAt sqltime.Time) error {
	updates := map[string]interface{}{
		"resolved":    resolution != ts.AlertResolutionNone,
		"resolution":  resolution.String(),
		"resolver_id": fmt.Sprint(resolverID),
		"updated_at":  updatedAt,
		"resolved_at": updatedAt,
	}

	// Update ElasticSearch index
	err := r.es.UpdateAlerts(ctx, repoID, ids, updates)
	if err != nil {
		return errors.Wrap(err, "failed to update alerts in ES")
	}

	// Emit insight events
	if r.ieh == nil {
		return nil
	}

	// Re-read alerts from ES and emit insights events
	filter := ts.SearchByOrgsFilter{
		LogicalAlertIDs: ids,
		IncludeRepositoriesWithoutCodeScanningEnabled: true, // Shouldn't be necessary since users can only update alerts for repos with code scanning enabled, but we include them just in case enablement data is out-of-sync
	}
	result, err := r.es.SearchOrgAlerts(ctx, &filter, ts.Pagination{Limit: uint32(len(ids))}, ts.SearchResultsSort{})
	if err != nil {
		return errors.Wrap(err, "failed to read logical alerts from ES")
	}

	return r.ieh.EmitHydroEvents(ctx, result.Documents, updates)
}
