package twirp

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/twitchtv/twirp"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) CreateAlertLinks(ctx context.Context, req *proto.CreateAlertLinksRequest) (*proto.CreateAlertLinksResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.turboscan.alert_numbers", fmt.Sprint(req.AlertNumbers)),
		kvp.String("gh.turboscan.pull_request_id", fmt.Sprint(req.PullRequestId)),
		kvp.ByteString("gh.turboscan.ref_name", req.RefNameBytes),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}
	if len(req.AlertNumbers) == 0 {
		return nil, twerrors.RequiredArgumentError("alert_number")
	}

	if (req.PullRequestId == 0) == (len(req.RefNameBytes) == 0) {
		return nil, twerrors.NewErrorf(twirp.InvalidArgument, "precisely one of pull_request_id or ref_name_bytes must be provided")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)
	alertNumbers := req.AlertNumbers
	pullRequestID := ts.PullRequestEID(req.PullRequestId)
	refNameBytes := req.RefNameBytes

	logicalAlerts, err := r.alertService.Alerts(ctx, repoID, ts.AlertFilter{Numbers: alertNumbers}, ts.AnalysisFilter{RepositoryID: repoID}, &ts.FindOptions{})
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	if len(logicalAlerts) != len(alertNumbers) {
		return nil, twerrors.NotFoundError("not all alerts were found")
	}

	err = r.alertLinksService.CreateAlertLinks(ctx, repoID, logicalAlerts, pullRequestID, refNameBytes)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return &proto.CreateAlertLinksResponse{}, nil
}
