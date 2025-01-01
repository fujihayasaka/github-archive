package twirp

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetLinksForAlerts(ctx context.Context, req *proto.GetLinksForAlertsRequest) (*proto.GetLinksForAlertsResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	reposAndAlerts := req.ReposAndAlerts

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.turboscan.repos_and_alerts", fmt.Sprint(reposAndAlerts)),
	)

	if len(req.ReposAndAlerts) == 0 {
		return nil, twerrors.RequiredArgumentError("repos_and_alerts")
	}
	for _, a := range reposAndAlerts {
		if a.Number == 0 {
			return nil, twerrors.RequiredArgumentError("number")
		}
		if a.RepositoryId == 0 {
			return nil, twerrors.RequiredArgumentError("repository_id")
		}
	}

	// group alert numbers by repo
	alertsByRepo := make(map[ts.RepositoryEID][]uint32)
	for _, a := range reposAndAlerts {
		repoId := ts.RepositoryEID(a.RepositoryId)
		alertsByRepo[repoId] = append(alertsByRepo[repoId], a.Number)
	}

	alertLinks := []*proto.AlertLink{}

	// run one query per repo
	for repoID, alertsForRepo := range alertsByRepo {
		if err := appctx.ContextError(ctx, "get_links_for_alerts"); err != nil {
			return nil, err
		}

		logicalAlerts, err := r.alertService.LogicalAlerts(ctx, repoID, alertsForRepo, nil)
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}

		alertLinksForRepo, err := r.alertLinksService.AlertLinks(ctx, repoID, logicalAlerts)
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}

		// Combine results for all repos
		for _, link := range alertLinksForRepo {
			alertLinks = append(alertLinks, &proto.AlertLink{
				RepositoryId:  uint64(link.RepositoryID),
				AlertNumber:   link.AlertNumber,
				PullRequestId: uint64(link.PullRequestID),
				RefNameBytes:  link.Ref,
			})
		}
	}

	return &proto.GetLinksForAlertsResponse{
		Links: alertLinks,
	}, nil
}
