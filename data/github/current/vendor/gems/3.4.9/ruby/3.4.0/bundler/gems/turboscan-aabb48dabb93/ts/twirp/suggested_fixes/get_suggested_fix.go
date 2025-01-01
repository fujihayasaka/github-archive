package suggested_fixes

import (
	"context"
	"strconv"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// GetSuggestedFix returns suggested fixes for the given alerts (if available)
func (s *Service) GetSuggestedFix(ctx context.Context, req *proto.GetSuggestedFixRequest) (*proto.GetSuggestedFixResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(
			attribute.String("gh.commit.sha", req.HeadCommitOid),
			attribute.IntSlice("gh.turboscan.alert_numbers", transforms.Map(req.AlertNumbers, func(n uint32) int { return int(n) }))),
	)

	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Any("gh.turboscan.alert_numbers", req.AlertNumbers),
		kvp.ByteStrings("gh.git.ref", req.RefNamesBytes),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if req.HeadCommitOid == "" {
		return nil, twerrors.RequiredArgumentError("head_commit_oid")
	}

	if len(req.RefNamesBytes) == 0 {
		return nil, twerrors.RequiredArgumentError("ref_names_bytes")
	}

	if len(req.AlertNumbers) == 0 {
		return nil, twerrors.RequiredArgumentError("alert_numbers")
	}

	sfas, err := s.sf.GetSuggestedFixAlerts(ctx, ts.RepositoryEID(req.RepositoryId), req.AlertNumbers, req.RefNamesBytes)
	if err != nil {
		return nil, err
	}

	suggestedFixAlerts := make(map[uint32]*proto.SuggestedFixAlert)

	for _, sfa := range sfas {
		var outdated bool

		if sfa.SuggestedFix != nil {
			var err error
			outdated, err = s.sf.IsFixOutdated(ctx, sfa.SuggestedFix, ts.ToSha(req.HeadCommitOid))
			if err != nil {
				return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
			}

			appctx.Stats(ctx).Counter("suggested_fix.get", stats.Tags{"outdated": strconv.FormatBool(outdated), "state": sfa.State.DBString()}, 1)
		}

		suggestedFixAlerts[sfa.LogicalAlertNumber] = serializeSuggestedFixAlert(sfa, outdated)
	}

	return &proto.GetSuggestedFixResponse{
		SuggestedFixAlerts: suggestedFixAlerts,
	}, nil
}
