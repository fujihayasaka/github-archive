package twirp

import (
	"context"
	"fmt"

	"golang.org/x/exp/maps"
	"golang.org/x/exp/slices"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/tstypes"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetRepoCountsByCampaigns(ctx context.Context, req *proto.RepoCountsByCampaignsRequest) (*proto.RepoCountsByCampaignsResponse, error) {
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

	// Count open alerts
	filter.State = proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN
	open, openCount, err := r.es.CountOrgAlertsByRepositoryID(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	// Count closed alerts
	filter.State = proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED
	closed, closedCount, err := r.es.CountOrgAlertsByRepositoryID(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	// Count open alerts with links
	filter.State = proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN
	filter.AlertLinks = proto.AlertLinksFilter_ALERT_LINKS_FILTER_ANY_LINKS
	openLinks, openLinksCount, err := r.es.CountOrgAlertsByRepositoryID(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	repoIDs := transforms.Unique(append(maps.Keys(open), maps.Keys(closed)...))

	slices.Sort(repoIDs)

	return &proto.RepoCountsByCampaignsResponse{
		OpenCount:          uint64(openCount),
		ClosedCount:        uint64(closedCount),
		OpenWithLinksCount: uint64(openLinksCount),
		RepositoryCounts: transforms.Map(repoIDs, func(repoID ts.RepositoryEID) *proto.RepoCountsByCampaignsResponse_RepositoryCounts {
			return &proto.RepoCountsByCampaignsResponse_RepositoryCounts{
				RepositoryId:       uint64(repoID),
				OpenCount:          uint64(open[repoID]),
				ClosedCount:        uint64(closed[repoID]),
				OpenWithLinksCount: uint64(openLinks[repoID]),
			}
		}),
	}, nil
}
