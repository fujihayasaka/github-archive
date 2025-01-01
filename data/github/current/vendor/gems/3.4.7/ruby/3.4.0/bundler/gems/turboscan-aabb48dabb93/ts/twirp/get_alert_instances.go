package twirp

import (
	"context"
	"strings"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/twirp/tstypes"
	"github.com/github/turboscan/ts/twirp/twerrors"

	"github.com/github/turboscan/ts/gormext"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/twitchtv/twirp"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
)

// GetAlertInstances retrieves all PhysicalAlerts associated with a TIP for the LogicalAlert specified by "alert_number"
func (r *ResultsResolver) GetAlertInstances(ctx context.Context, req *proto.AlertInstancesRequest) (*proto.AlertInstancesResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(attribute.Int("gh.turboscan.alert_number", int(req.AlertNumber))),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint64("gh.turboscan.alert_number", uint64(req.AlertNumber)),
		kvp.Uint64("gh.turboscan.limit", uint64(req.Limit)),
		kvp.Uint64("gh.turboscan.numeric_page", uint64(req.NumericPage)),
		kvp.ByteStrings("gh.turboscan.ref_names", req.RefNamesBytes),
		kvp.Bool("gh.turboscan.skip_pagination", req.SkipPagination),
		kvp.Bool("gh.turboscan.branches_only", req.BranchesOnly),
		kvp.Bool("gh.turboscan.no_count", req.NoCount),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}
	if req.AlertNumber == 0 {
		return nil, twerrors.RequiredArgumentError("alert_number")
	}
	if req.BranchesOnly {
		for _, refName := range req.RefNamesBytes {
			if !strings.HasPrefix(string(refName), "refs/heads/") {
				return nil, twerrors.NewError(twirp.InvalidArgument, "branches_only is incompatible with ref_names that don't start with 'refs/heads/'")
			}
		}
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	skipPagination := req.SkipPagination

	filter := ts.AlertFilter{
		Numbers: []uint32{req.AlertNumber},
		State:   proto.AlertStateFilter_ALERT_STATE_FILTER_ALL,
	}
	analysisFilter := ts.AnalysisFilter{
		RepositoryID:    repoID,
		State:           ts.AnalysisStateFilterMostRecent,
		IncludeOutdated: true,
	}

	// attempt to use a replica for this endpoint if available
	ctx = gormext.WithTryReplica(ctx, true)

	alerts, err := r.alertService.LogicalAlerts(ctx, repoID, []uint32{req.AlertNumber}, []string{"DefaultConfiguration"})
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	if len(alerts) == 0 {
		return nil, o11y.RecordError(span, twerrors.NotFoundError("alert not found"))
	}
	la := alerts[0]
	// We're only applying more restrictive filters now rather than already in the above call to alertService.Alert
	// so that they cannot prevent us from finding the logical alert.
	analysisFilter.Refs = req.RefNamesBytes
	analysisFilter.BranchesOnly = req.BranchesOnly

	options := &ts.FindOptions{
		Preloads: []string{"Analysis", "Analysis.Tool", "Analysis.ToolVersion", "LastSeenAnalysis"},
	}
	if !skipPagination {
		pagination := tstypes.CreatePaginationInfo(req.Limit, req.NumericPage)
		options.Pagination = &pagination
	}

	filter.IDs = []ts.LogicalAlertID{la.ID}
	physicalAlerts, err := r.alertService.PhysicalAlerts(ctx, repoID, filter, analysisFilter, options)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	var count uint64
	if !req.NoCount {
		count, err = r.alertService.CountPhysicalAlerts(ctx, repoID, filter, analysisFilter)
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
	}

	instances := make([]*proto.AlertInstance, 0, len(physicalAlerts))
	for _, pa := range physicalAlerts {
		instances = append(instances, serializeAlertInstance(pa, la))
	}

	return &proto.AlertInstancesResponse{
		Instances:  instances,
		TotalCount: count,
	}, nil
}
