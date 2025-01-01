package twirp

import (
	"context"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/github/turboscan/ts/validate"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func (r *ResultsResolver) PullRequestAlerts(ctx context.Context, req *proto.PullRequestAlertsRequest) (*proto.PullRequestAlertsResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(
			attribute.String("gh.turboscan.tool_name", req.Tool),
			attribute.String("gh.pull_request.base_ref", string(req.BaseRefBytes)),
			attribute.String("gh.pull_request.head_sha", req.HeadCommitOid),
			attribute.String("gh.pull_request.merge_sha", req.MergeCommitOid),
		),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.turboscan.tool", req.Tool),
		kvp.ByteString("gh.pull_request.base_ref", req.BaseRefBytes),
		kvp.String("gh.pull_request.head_sha", req.HeadCommitOid),
		kvp.String("gh.pull_request.merge_sha", req.MergeCommitOid),
		kvp.Int("gh.turboscan.files_changed", len(req.FileChanges)),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("pr_alerts.repository_id")
	}
	repo := ts.RepositoryEID(req.RepositoryId)

	if req.Tool == "" {
		return nil, twerrors.RequiredArgumentError("pr_alerts.tool")
	}

	baseRef := string(req.BaseRefBytes)
	if !strings.HasPrefix(baseRef, "refs/heads") {
		return nil, twerrors.InvalidArgumentError("pr_alerts.base_ref_bytes", "must be a qualified ref")
	}

	if !validate.IsCommitOid(req.HeadCommitOid) {
		return nil, twerrors.InvalidArgumentError("pr_alerts.head_commit_oid", "must be a valid commit oid")
	}
	if req.MergeCommitOid != "" && !validate.IsCommitOid(req.MergeCommitOid) {
		return nil, twerrors.InvalidArgumentError("pr_alerts.merge_commit_oid", "must be a valid commit oid")
	}

	toolIDs, err := r.toolService.ToolsIDsWithRenames(ctx, ts.ToToolName(req.Tool))
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	if len(toolIDs) == 0 {
		appctx.Logger(ctx).Info("tool not found",
			kvp.String("gh.turboscan.tool", req.Tool),
		)
		return nil, o11y.RecordError(span, twerrors.NotFoundError("could not find tool"))
	}

	opts := &ts.PRAlertsOpts{
		HeadCommit:  ts.ToShaPtr(req.HeadCommitOid),
		MergeCommit: ts.ToShaPtr(req.MergeCommitOid),
		BaseRef:     baseRef,
		ToolIDs:     toolIDs,
		FileChanges: req.FileChanges,
	}

	prAlerts, err := r.prAlertsService.PullRequestAlerts(ctx, r.archiveService, repo, opts)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	limit := uint32(100) // TODO: Make this a constant somewhere?
	res, err := serizalizePullRequestAlerts(prAlerts, limit)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	return res, nil
}
