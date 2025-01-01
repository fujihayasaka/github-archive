package suggested_fixes

import (
	"context"
	"strconv"

	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/twirp/tstypes"

	"github.com/github/github-telemetry-go/kvp"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (s *Service) GetSuggestedFixStatesForOrg(ctx context.Context, req *proto.GetSuggestedFixStatesForOrgRequest) (*proto.GetSuggestedFixStatesForOrgResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		trace.WithAttributes(
			attribute.IntSlice("gh.turboscan.owner_ids", transforms.Map(req.OwnerIds, func(n uint64) int { return int(n) })),
		),
	)

	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint32("gh.turboscan.limit", req.Limit),
		kvp.String("gh.turboscan.before_cursor", req.BeforeCursor),
		kvp.String("gh.turboscan.after_cursor", req.AfterCursor),
		kvp.Uint64s("gh.repo.ids.excluded", req.ExcludedRepositoryIds),
	)

	if len(req.OwnerIds) == 0 {
		return nil, o11y.RecordError(span, twerrors.RequiredArgumentError("owner_ids"))
	}

	filter, err := tstypes.CreateSearchByOrgsFilter(req.OwnerIds, req.RepositoryIds, req.ExcludedRepositoryIds, req.Filter)
	if err != nil {
		return nil, o11y.RecordError(span, err)
	}

	pagination, err := tstypes.CreateCursorPaginationInfo(req.Limit, req.BeforeCursor, req.AfterCursor)
	if err != nil {
		return nil, o11y.RecordError(span, err)
	}

	searchResult, err := s.es.SearchOrgAlerts(ctx, filter, pagination, ts.DefaultSearchResultsSort)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	suggestedFixAlerts := make([]*proto.RepoSuggestedFixState, 0, len(searchResult.Documents))

	for _, doc := range searchResult.Documents {
		repoID, err := strconv.ParseUint(doc.RepositoryID, 10, 64)
		if err != nil {
			return nil, o11y.RecordError(span, twirp.InternalErrorWith(err))
		}

		autofixState := ts.SuggestedFixAlertState(doc.AutofixState)

		var stateUpdatedAt *timestamppb.Timestamp
		if doc.AutofixStateUpdatedAt != nil {
			stateUpdatedAt = timestamppb.New(doc.AutofixStateUpdatedAt.Time)
		}

		sfs := &proto.RepoSuggestedFixState{
			RepositoryId:   repoID,
			AlertNumber:    doc.Number,
			Eligible:       doc.AutofixEligible,
			State:          serializeSuggestedFixAlertState(autofixState),
			StateUpdatedAt: stateUpdatedAt,
		}

		suggestedFixAlerts = append(suggestedFixAlerts, sfs)
	}

	return &proto.GetSuggestedFixStatesForOrgResponse{
		SuggestedFixStates: suggestedFixAlerts,
		NextCursor:         searchResult.NextCursor,
		PrevCursor:         searchResult.PrevCursor,
	}, nil
}
