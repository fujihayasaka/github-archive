package twirp

import (
	"context"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/mysql/pr_alerts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func (r *ResultsResolver) PullRequestIntroducedAlerts(ctx context.Context, req *proto.PullRequestIntroducedAlertsRequest) (*proto.PullRequestIntroducedAlertsResponse, error) {
	ctx, s := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(
			attribute.String("gh.turboscan.tool_name", req.Tool),
			attribute.Int64("gh.pull_request.pr_number", int64(req.PrNumber)),
		),
	)
	defer s.End()

	// attempt to use a replica for this endpoint if available
	ctx = gormext.WithTryReplica(ctx, true)

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.turboscan.tool", req.Tool),
		kvp.ByteString("gh.pull_request.base_ref", req.BaseRefBytes),
		kvp.String("gh.pull_request.head_sha", req.HeadCommitOid),
		kvp.String("gh.pull_request.merge_sha", req.MergeCommitOid),
		kvp.Uint32("gh.pull_request.number", req.PrNumber),
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

	toolIDs, err := r.toolService.ToolsIDsWithRenames(ctx, ts.ToToolName(req.Tool))
	if err != nil {
		return nil, o11y.RecordError(s, twerrors.InternalErrorWith(err))
	}
	if len(toolIDs) == 0 {
		appctx.Logger(ctx).Info("tool not found",
			ts.RepositoryEID(req.RepositoryId).AsKVP(),
			kvp.String("gh.turboscan.tool", req.Tool),
		)
		return nil, o11y.RecordError(s, twerrors.NotFoundError("could not find tool"))
	}

	opts := &ts.PRAlertsOpts{
		BaseRef:     baseRef,
		ToolIDs:     toolIDs,
		FileChanges: req.FileChanges,
		PRNumber:    req.PrNumber,
	}

	physicalAlerts, err := r.prAlertsService.PullRequestIntroducedAlerts(ctx, r.archiveService, repo, opts)
	if err != nil {
		return nil, o11y.RecordError(s, twerrors.InternalErrorWith(err))
	}
	alerts := []*proto.AlertInPullRequest{}

	if len(physicalAlerts) > 0 {
		// All refs should be the same, as we pull them from the same analysis
		ref := physicalAlerts[0].PhysicalAlert.Analysis.Ref
		numbers := transforms.Map(physicalAlerts, func(a *pr_alerts.IntroducedAlert) uint32 { return a.PhysicalAlert.LogicalAlert.Number })

		// Load suggested fixes for the alerts
		sfas, err := r.sfService.FindSuggestedFixAlertsWithFixes(ctx, repo, numbers, ref)
		if err != nil {
			return nil, o11y.RecordError(s, twerrors.InternalErrorWith(err))
		}
		sfasM := make(map[uint32]*ts.SuggestedFixAlert)
		for _, sfa := range sfas {
			sfasM[sfa.LogicalAlertNumber] = sfa
		}
		for _, alert := range physicalAlerts {
			pa := alert.PhysicalAlert
			a := serializeAlertInPullRequest(pa, alert.IntroducedAt, alert.FixedAt)
			sfa, ok := sfasM[pa.LogicalAlert.Number]
			a.HasAutofix = ok
			a.AutofixAccepted = ok && sfa.WasSuggestionUsed()
			alerts = append(alerts, a)
		}
	}

	return &proto.PullRequestIntroducedAlertsResponse{
		Alerts:     alerts,
		TotalCount: uint64(len(physicalAlerts)),
	}, nil
}
