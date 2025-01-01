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

func (r *ResultsResolver) GetCodePaths(ctx context.Context, req *proto.CodePathsRequest) (*proto.CodePathsResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(attribute.Int("gh.turboscan.alert_number", int(req.Number))),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint64("gh.turboscan.number", uint64(req.Number)),
	)

	if req.Number == 0 {
		return nil, twerrors.RequiredArgumentError("number")
	}

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	preloads := []string{"Rule", "Rule.Tags", "Rule.Tool", "DefaultConfiguration"}
	alerts, err := r.alertService.LogicalAlerts(ctx, repoID, []uint32{req.Number}, preloads)
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

	filter := ts.AlertFilter{
		IDs: []ts.LogicalAlertID{logicalAlert.ID},
	}
	analysisFilter := ts.AnalysisFilter{
		RepositoryID:    repoID,
		Refs:            [][]byte{logicalAlert.DefaultConfiguration.Ref},
		State:           ts.AnalysisStateFilterMostRecent,
		IncludeOutdated: true,
	}
	physicalAlerts, err := r.alertService.PhysicalAlerts(ctx, repoID, filter, analysisFilter, &ts.FindOptions{
		Preloads: []string{"Analysis", "Analysis.Tool", "Analysis.ToolVersion", "LastSeenAnalysis"},
	})
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	if len(physicalAlerts) == 0 {
		// If no physical alerts are found, it's probably because the alert is not present in any of the recent configurations, so we should return a 404
		return nil, o11y.RecordError(span, twerrors.NotFoundError("could not find result"))
	}
	fixed := true
	for _, pa := range physicalAlerts {
		if !pa.IsFixed {
			fixed = false
			break
		}
	}
	logicalAlert.IsFixed = &fixed

	pa := physicalAlerts[0]
	logicalAlert.PhysicalAlerts = []*ts.PhysicalAlert{pa}

	result, err := serializeResult(*logicalAlert)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	var codeflows *ts.CodeFlowsDocument
	var codeFlowResult []ts.CodeFlows

	targetAnalysis := pa.Analysis
	if pa.IsFixed {
		targetAnalysis = pa.LastSeenAnalysis
	}
	cMap, lMap, err := r.archiveService.ExtractCodePaths(ctx, targetAnalysis, []*ts.LogicalAlert{logicalAlert})
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	codeflows = cMap[logicalAlert.ID]
	if codeflows != nil {
		codeFlowResult = ts.GroupByCodeFlowIndex(codeflows.Document)
	}
	relatedLocations := lMap[logicalAlert.ID]

	return &proto.CodePathsResponse{
		Result:           result,
		CodePaths:        serializeCodeFlowResult(codeFlowResult),
		RelatedLocations: serializeRelatedLocationsResult(relatedLocations),
		RefNameBytes:     pa.Analysis.Ref,
	}, nil
}
