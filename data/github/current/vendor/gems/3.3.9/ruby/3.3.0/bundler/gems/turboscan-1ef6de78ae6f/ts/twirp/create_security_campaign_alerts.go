package twirp

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) CreateSecurityCampaignAlerts(ctx context.Context, req *proto.CreateSecurityCampaignAlertsRequest) (*proto.CreateSecurityCampaignAlertsResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint64("gh.turboscan.security_campaign_id", req.SecurityCampaignId),
		kvp.String("gh.turboscan.repo_numbers", fmt.Sprint(req.RepoNumbers)),
	)

	if req.SecurityCampaignId == 0 {
		return nil, twerrors.RequiredArgumentError("security_campaign_id")
	}
	if len(req.RepoNumbers) == 0 {
		return nil, twerrors.RequiredArgumentError("repo_numbers")
	}

	securityCampaignID := ts.SecurityCampaignEID(req.SecurityCampaignId)
	repoNumbers := transforms.Map(req.RepoNumbers, func(rn *proto.RepoNumber) ts.RepoNumber {
		return ts.RepoNumber{
			RepositoryID: ts.RepositoryEID(rn.RepositoryId), Number: rn.Number,
		}
	})

	logicalAlertIDs, err := r.alertService.WriteSecurityCampaignAlerts(ctx, repoNumbers, securityCampaignID)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	if len(logicalAlertIDs) > 0 {
		err := r.es.AddCampaignEIDToAlerts(ctx, logicalAlertIDs, securityCampaignID)
		if err != nil {
			// At the moment we just ignore elastic search errors
			appctx.Logger(ctx).WithError(err).Error(
				"Failed to update ES index when creating security campaign alerts",
				kvp.Int("gh.turboscan.ids.count", len(logicalAlertIDs)),
			)

			appctx.Stats(ctx).Counter("es.dynamic_update.error", stats.Tags{"kind": "security_campaign_alerts"}, 1)
		}
	}

	return &proto.CreateSecurityCampaignAlertsResponse{}, nil
}
