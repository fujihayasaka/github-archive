package twirp

import (
	"context"

	"github.com/twitchtv/twirp"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) DeleteAlertLinks(ctx context.Context, req *proto.DeleteAlertLinksRequest) (*proto.DeleteAlertLinksResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Int("gh.turboscan.alert_links.count", len(req.Links)),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if len(req.Links) == 0 {
		return nil, twerrors.NewErrorf(twirp.InvalidArgument, "links should be provided")
	}

	for _, link := range req.Links {
		if link.AlertNumber == 0 {
			return nil, twerrors.RequiredArgumentError("links[].alert_number")
		}

		if (link.PullRequestId == 0) == (len(link.RefNameBytes) == 0) {
			return nil, twerrors.NewErrorf(twirp.InvalidArgument, "precisely one of links[].pull_request_id or links[].ref_name_bytes must be provided")
		}
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	alertLinksWithoutID := transforms.Map(req.Links, func(link *proto.AlertLinkPayload) ts.AlertLinkWithoutID {
		return ts.AlertLinkWithoutID{
			RepositoryID:  repoID,
			AlertNumber:   link.AlertNumber,
			PullRequestID: ts.PullRequestEID(link.PullRequestId),
			Ref:           link.RefNameBytes,
		}
	})

	err := r.alertLinksService.DeleteAlertLinks(ctx, alertLinksWithoutID)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return &proto.DeleteAlertLinksResponse{}, nil
}
