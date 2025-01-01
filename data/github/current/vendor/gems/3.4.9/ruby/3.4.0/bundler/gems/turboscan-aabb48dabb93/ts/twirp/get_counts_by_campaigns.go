package twirp

import (
	"context"
	"fmt"
	"sort"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/tstypes"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetCountsByCampaigns(ctx context.Context, req *proto.CountsByCampaignsRequest) (*proto.CountsByCampaignsResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.turboscan.security_campaign_ids", fmt.Sprint(req.SecurityCampaignIds)),
	)

	if len(req.OwnerIds) == 0 {
		return nil, o11y.RecordError(span, twerrors.RequiredArgumentError("owner_ids"))
	}
	ownerIds := req.OwnerIds
	if len(req.SecurityCampaignIds) == 0 {
		return nil, o11y.RecordError(span, twerrors.RequiredArgumentError("security_campaign_ids"))
	}

	filter, err := tstypes.CreateSearchByOrgsFilter(ownerIds, req.RepositoryIds, req.ExcludedRepositoryIds, req.Filter)
	if err != nil {
		return nil, o11y.RecordError(span, err)
	}
	for _, rn := range req.SecurityCampaignIds {
		filter.SecurityCampaignIDs = append(filter.SecurityCampaignIDs, ts.SecurityCampaignEID(rn))
	}

	counts, err := r.es.OrgAlertsStatsByCampaignID(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	// Sort counts
	sort.Slice(counts, func(i, j int) bool {
		return counts[i].CampaignId < counts[j].CampaignId
	})

	return &proto.CountsByCampaignsResponse{
		CampaignCounts: counts,
	}, nil
}
