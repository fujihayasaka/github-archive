package twirp

import (
	"context"

	"github.com/twitchtv/twirp"
	"golang.org/x/exp/maps"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) CreateAlertLinks(ctx context.Context, req *proto.CreateAlertLinksRequest) (*proto.CreateAlertLinksResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received")

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if len(req.Links) == 0 {
		return nil, twerrors.RequiredArgumentError("links")
	}

	alertNumberSet := map[uint32]struct{}{}
	for _, link := range req.Links {
		if link.AlertNumber == 0 {
			return nil, twerrors.RequiredArgumentError("links[].alert_number")
		}

		if (link.PullRequestId == 0) == (len(link.RefNameBytes) == 0) {
			return nil, twerrors.NewErrorf(twirp.InvalidArgument, "precisely one of links[].pull_request_id or links[].ref_name_bytes must be provided")
		}

		alertNumberSet[link.AlertNumber] = struct{}{}
	}

	alertNumbers := maps.Keys(alertNumberSet)
	repoID := ts.RepositoryEID(req.RepositoryId)
	logicalAlerts, err := r.alertService.LogicalAlerts(ctx, repoID, alertNumbers, nil)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	if len(logicalAlerts) != len(alertNumbers) {
		return nil, twerrors.NotFoundError("not all alerts were found")
	}

	logicalAlertsByNumber := transforms.IndexBy(logicalAlerts, func(la *ts.LogicalAlert) uint32 {
		return la.Number
	})

	linksToCreate := []*ts.AlertLink{}
	for _, link := range req.Links {
		if la, ok := logicalAlertsByNumber[link.AlertNumber]; ok {
			linksToCreate = append(linksToCreate, &ts.AlertLink{
				RepositoryID:   repoID,
				LogicalAlertID: la.ID,
				AlertNumber:    la.Number,
				PullRequestID:  ts.PullRequestEID(link.PullRequestId),
				Ref:            link.RefNameBytes,
			})
		}
	}

	err = r.alertLinksService.CreateAlertLinks(ctx, repoID, linksToCreate)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return &proto.CreateAlertLinksResponse{}, nil
}
