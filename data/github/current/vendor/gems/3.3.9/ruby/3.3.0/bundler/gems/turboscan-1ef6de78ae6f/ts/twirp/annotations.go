package twirp

import (
	"context"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/github/turboscan/ts/validate"
)

func (r *ResultsResolver) Annotations(ctx context.Context, req *proto.AnnotationsRequest) (*proto.AnnotationsResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint32s("gh.turboscan.numbers", req.Numbers),
		kvp.String("gh.pull_request.head_sha", req.HeadCommitOid),
		kvp.String("gh.pull_request.merge_sha", req.MergeCommitOid),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if len(req.Numbers) == 0 {
		return nil, twerrors.RequiredArgumentError("numbers")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	var commitOids []ts.Sha

	if req.MergeCommitOid != "" {
		if !validate.IsCommitOid(req.MergeCommitOid) {
			return nil, twerrors.InvalidArgumentError("merge_commit_oid", "must be a valid commit oid")
		}

		commitOids = append(commitOids, ts.ToSha(req.MergeCommitOid))
	}
	if req.HeadCommitOid != "" {
		if !validate.IsCommitOid(req.HeadCommitOid) {
			return nil, twerrors.InvalidArgumentError("head_commit_oid", "must be a valid commit oid")
		}

		commitOids = append(commitOids, ts.ToSha(req.HeadCommitOid))
	}

	if len(commitOids) == 0 {
		// really the commit oid should be a protobuf `oneof`
		// because it is not we have to say we require one of the two arguments
		return nil, twerrors.RequiredArgumentError("head_commit_oid")
	}

	logicalAlerts, err := r.prAlertsService.AnnotationAlerts(
		ctx, repoID, req.Numbers, commitOids, r.alertService, r.archiveService,
	)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	// We record how many alerts were actually found in the call
	total := int64(len(req.Numbers))
	found := int64(len(logicalAlerts))
	appctx.Stats(ctx).Counter("annotations.logical_alerts", stats.Tags{"found": "true"}, found)
	appctx.Stats(ctx).Counter("annotations.logical_alerts", stats.Tags{"found": "false"}, total-found)

	results := make([]*proto.AnnotationResult, 0, len(logicalAlerts))
	for _, la := range logicalAlerts {
		pa, err := la.Canonical()
		if err != nil {
			return nil, twerrors.InternalErrorWith(err)
		}

		result, err := serializeResult(*la)
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}

		results = append(results, &proto.AnnotationResult{
			Result:           result,
			RelatedLocations: serializeRelatedLocationsResult(pa.RelatedLocations),
			HasCodePaths:     pa.HasCodePaths(),
		})
	}

	return &proto.AnnotationsResponse{
		Results: results,
	}, nil
}
