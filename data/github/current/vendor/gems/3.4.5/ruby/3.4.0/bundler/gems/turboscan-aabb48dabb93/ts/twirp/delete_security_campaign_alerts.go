package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) DeleteSecurityCampaignAlerts(ctx context.Context, req *proto.DeleteSecurityCampaignAlertsRequest) (*proto.DeleteSecurityCampaignAlertsResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint64("gh.turboscan.security_campaign_id", req.SecurityCampaignId),
	)

	if req.SecurityCampaignId == 0 {
		return nil, twerrors.RequiredArgumentError("security_campaign_id")
	}
	securityCampaignID := ts.SecurityCampaignEID(req.SecurityCampaignId)

	// First delete the alerts from the DB
	logicalAlertIDs, err := r.alertService.DeleteSecurityCampaignAlerts(ctx, securityCampaignID)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	// Then attempt to update the ES index
	if len(logicalAlertIDs) > 0 {
		err := r.es.RemoveCampaignEIDFromAlerts(ctx, logicalAlertIDs, securityCampaignID)
		if err != nil {
			// At the moment we just ignore elastic search errors
			appctx.Logger(ctx).WithError(err).Error(
				"Failed to update ES index when delete security campaign alerts",
				kvp.Int("gh.turboscan.ids.count", len(logicalAlertIDs)),
			)

			appctx.Stats(ctx).Counter("es.dynamic_update.error", stats.Tags{"kind": "delete_security_campaign_alerts"}, 1)
		}
	}

	return &proto.DeleteSecurityCampaignAlertsResponse{}, nil
}
