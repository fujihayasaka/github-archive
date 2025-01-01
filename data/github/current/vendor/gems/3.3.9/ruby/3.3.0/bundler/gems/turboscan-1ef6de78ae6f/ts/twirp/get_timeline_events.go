package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func (r *ResultsResolver) GetTimelineEvents(ctx context.Context, req *proto.TimelineEventsRequest) (*proto.TimelineEventsResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(attribute.Int("gh.turboscan.alert_number", int(req.Number))),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint64("gh.turboscan.number", uint64(req.Number)),
		kvp.ByteStrings("gh.turboscan.ref_names", req.RefNamesBytes),
	)

	if req.Number == 0 {
		return nil, twerrors.RequiredArgumentError("number")
	}

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	alertID, err := r.alertService.AlertId(ctx, repoID, req.Number)
	if errors.Is(err, ts.ErrAlertNotFound) {
		return nil, o11y.RecordError(span, twerrors.NotFoundError("could not find result"))
	} else if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	timelineEventResult, err := r.timelineEventService.FindTimelineEvents(ctx,
		&ts.TimelineEventFilter{RepositoryID: repoID, LogicalAlertID: alertID},
		&ts.FindOptions{SortBy: "ts_timeline_events.event_timestamp"},
	)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return &proto.TimelineEventsResponse{
		Events: serializeTimelineEvents(timelineEventResult),
	}, nil
}
