package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/tstypes"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetTotalCountsForCampaigns(ctx context.Context, req *proto.TotalCountsForCampaignsRequest) (*proto.TotalCountsForCampaignsResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Any("gh.turboscan.alerts_filter", req.Filter),
	)

	if len(req.OwnerIds) == 0 {
		return nil, o11y.RecordError(span, twerrors.RequiredArgumentError("owner_ids"))
	}
	ownerIds := req.OwnerIds

	baseFilter, err := tstypes.CreateSearchByOrgsFilter(ownerIds, req.RepositoryIds, req.ExcludedRepositoryIds, req.Filter)
	if err != nil {
		return nil, o11y.RecordError(span, err)
	}

	subFilters := []*ts.SearchByOrgsFilter{
		// Open alerts
		{State: proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN},
		// Closed alerts
		{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED},
		// In progress alerts
		{
			State:      proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN,
			AlertLinks: proto.AlertLinksFilter_ALERT_LINKS_FILTER_ANY_LINKS,
		},
		// Dismissed alerts
		{State: proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_RESOLVED},
		// Autofix supported
		{
			Autofixes: []proto.AutofixFilter{
				proto.AutofixFilter_AUTOFIX_FILTER_SUPPORTED,
			},
		},
		// Autofix generated
		{
			Autofixes: []proto.AutofixFilter{
				proto.AutofixFilter_AUTOFIX_FILTER_GENERATED,
			},
		},
		// Autofix accepted
		{
			Autofixes: []proto.AutofixFilter{
				proto.AutofixFilter_AUTOFIX_FILTER_ACCEPTED,
			},
		},
	}

	counts, err := r.es.OrgAlertCounts(ctx, baseFilter, subFilters)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return &proto.TotalCountsForCampaignsResponse{
		OpenCount:             counts[0],
		ClosedCount:           counts[1],
		OpenWithLinksCount:    counts[2],
		DismissedCount:        counts[3],
		AutofixSupportedCount: counts[4],
		AutofixGeneratedCount: counts[5],
		AutofixAcceptedCount:  counts[6],
	}, nil
}
