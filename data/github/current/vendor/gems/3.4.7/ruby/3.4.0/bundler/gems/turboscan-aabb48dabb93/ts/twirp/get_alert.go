package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func (r *ResultsResolver) GetAlert(ctx context.Context, req *proto.AlertRequest) (*proto.AlertResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(attribute.Int("gh.turboscan.alert_number", int(req.Number))),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint64("gh.turboscan.number", uint64(req.Number)),
		kvp.Bool("gh.turboscan.include_related_locations", req.IncludeRelatedLocations),
	)

	if req.Number == 0 {
		return nil, twerrors.RequiredArgumentError("number")
	}

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	filter := ts.AlertFilter{
		Numbers: []uint32{req.Number},
	}
	alerts, err := r.alertService.LogicalAlerts(ctx, repoID, []uint32{req.Number}, []string{"DefaultConfiguration"})
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	if len(alerts) == 0 {
		return nil, o11y.RecordError(span, twerrors.NotFoundError("could not find result"))
	}
	logicalAlert := alerts[0]

	if logicalAlert.DefaultConfiguration == nil {
		// No default configuration means the alert does not have any associated physical alerts, so we should return a 404
		return nil, o11y.RecordError(span, twerrors.NotFoundError("could not find result"))
	}

	analysisFilter := ts.AnalysisFilter{
		RepositoryID:    repoID,
		Refs:            [][]byte{logicalAlert.DefaultConfiguration.Ref},
		State:           ts.AnalysisStateFilterMostRecent,
		IncludeOutdated: true,
	}
	opts := &ts.FindOptions{
		Preloads:   []string{"Rule", "Rule.Tags", "Rule.Tool", "PhysicalAlerts", "PhysicalAlerts.Analysis", "PhysicalAlerts.Analysis.Tool", "PhysicalAlerts.Analysis.ToolVersion", "PhysicalAlerts.LastSeenAnalysis"},
		Pagination: &ts.Pagination{Limit: 1},
	}
	filter.IDs = []ts.LogicalAlertID{logicalAlert.ID}
	// reload the alert to populate all derived fields
	alerts, err = r.alertService.Alerts(ctx, repoID, filter, analysisFilter, opts)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	} else if len(alerts) == 0 {
		return nil, o11y.RecordError(span, twerrors.NotFoundError("could not find result"))
	}
	logicalAlert = alerts[0]
	ruleTags, err := logicalAlert.Rule.GetTags()
	if err != nil {
		return nil, twerrors.InternalErrorWith(err)
	}
	pa := logicalAlert.PhysicalAlerts[0]
	result, err := serializeResult(*logicalAlert)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	var relatedLocations []*ts.RelatedLocation
	if req.IncludeRelatedLocations {
		targetAnalysis := pa.Analysis
		if pa.IsFixed {
			targetAnalysis = pa.LastSeenAnalysis
		}
		_, lMap, err := r.archiveService.ExtractCodePaths(ctx, targetAnalysis, []*ts.LogicalAlert{logicalAlert})
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
		relatedLocations = lMap[logicalAlert.ID]
	}
	return &proto.AlertResponse{
		Result:           result,
		RuleTags:         ruleTags,
		RelatedLocations: serializeRelatedLocationsResult(relatedLocations),
		HasCodePaths:     pa.HasCodePaths(),
		RuleHelp:         logicalAlert.Rule.Help,
		RefNameBytes:     pa.Analysis.Ref,
		QueryUri:         logicalAlert.Rule.QueryURI,
	}, nil
}
