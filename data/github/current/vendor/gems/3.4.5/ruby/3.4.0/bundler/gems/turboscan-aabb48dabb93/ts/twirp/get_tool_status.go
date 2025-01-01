package twirp

import (
	"context"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"golang.org/x/exp/slices"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	tssarif "github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetToolStatus(ctx context.Context, req *proto.ToolStatusRequest) (*proto.ToolStatusResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	var cancelFunc context.CancelFunc
	ctx, cancelFunc = context.WithTimeout(ctx, 8*time.Second)
	defer cancelFunc()

	// attempt to use a replica for this endpoint if available
	ctx = gormext.WithTryReplica(ctx, true)

	appctx.Logger(ctx).Info("request received")

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	if len(req.Ref) == 0 {
		return nil, twerrors.RequiredArgumentError("ref")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	filter := ts.LatestAnalysisFilter{Ref: req.Ref}
	analyses, err := r.alertService.LatestAnalysesForRef(ctx, repoID, filter, r.withProcessedSARIFs)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	var status []*proto.ToolStatus

	defer func() {
		appctx.Logger(ctx).WithFields(
			kvp.ByteString("gh.git.ref", req.Ref),
			kvp.Uint64s("gh.turboscan.analysis_ids", transforms.Map(analyses, func(a *ts.LatestAnalysis) uint64 { return uint64(a.ID) })),
			kvp.Uint64s("gh.turboscan.tool_status_ids", transforms.FilterMap(analyses, func(a *ts.LatestAnalysis) (uint64, bool) {
				if a.AnalysisExtractedFiles != nil {
					return uint64(a.AnalysisExtractedFiles.ID), true
				}
				return 0, false
			})),
			kvp.Strings("gh.turboscan.tools", transforms.Map(status, func(s *proto.ToolStatus) string { return s.Name })),
		).Info("responded to get_tool_status")
	}()

	grouped := transforms.GroupBy(analyses, func(a *ts.LatestAnalysis) string {
		tool := a.ToolVersion.Tool
		return tool.CanonicalName.String()
	})
	out := make([]*proto.ToolStatus, 0, len(grouped))

	for tool, analyses := range grouped {
		ts := &proto.ToolStatus{
			Name:       tool,
			Categories: make([]*proto.CategoryStatus, 0, len(analyses)),
		}

		for _, a := range analyses {
			var cat *proto.CategoryStatus
			if a.ArchivalDataUrl != "" {
				cat, err = r.categoryStatusFromSarif(ctx, a)
				if err != nil {
					return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
				}
			} else {
				cat = serializeCategoryStatus(a)
			}
			ts.Categories = append(ts.Categories, cat)
		}
		out = append(out, ts)
	}
	slices.SortFunc(out, func(a, b *proto.ToolStatus) int {
		return strings.Compare(a.Name, b.Name)
	})
	return &proto.ToolStatusResponse{Tools: out}, nil
}

func (r *ResultsResolver) categoryStatusFromSarif(ctx context.Context, a *ts.LatestAnalysis) (*proto.CategoryStatus, error) {
	sarifStr, err := r.archivalStore.Download(ctx, a.ArchivalDataUrl)
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error("failed to download processed sarif for analysis",
			a.RepositoryID.AsKVP(), a.ID.AsKVP(),
		)
		appctx.Stats(ctx).Counter("tool.status.error", stats.Tags{"reason": "sarif"}, 1)
		return nil, err
	}
	sarif, err := tssarif.Decode(sarifStr.Bytes())
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error("failed to decode processed sarif for analysis",
			a.RepositoryID.AsKVP(), a.ID.AsKVP(),
		)
		appctx.Stats(ctx).Counter("tool.status.error", stats.Tags{"reason": "sarif"}, 1)
		return nil, err
	}
	if len(sarif.Runs) != 1 {
		appctx.Logger(ctx).Error("unexpected number of runs for the processed sarif",
			a.RepositoryID.AsKVP(), a.ID.AsKVP(), kvp.String("gh.turboscan.archival_data_url", a.ArchivalDataUrl))
		appctx.Stats(ctx).Counter("tool.status.error", stats.Tags{"reason": "expected_runs"}, 1)
		return nil, ErrTooManyRuns
	}
	run := sarif.Runs[0]
	extensions := []*proto.RuleOrigin{}
	for _, ext := range run.Tool.Extensions {
		version := ext.SemanticVersion
		if version == "" {
			version = ext.Version
		}
		extensions = append(extensions, &proto.RuleOrigin{
			Name:    ext.Name,
			Version: version,
		})
	}
	if len(a.AnalysisQuerySuites) == 0 {
		// we only want to use the SARIF if we couldn't load the query suites from the DB
		_, a.AnalysisQuerySuites = tssarif.GetCodeQLConfig(run)
	}

	return &proto.CategoryStatus{
		WorkflowRunId:          uint64(a.WorkflowRunID),
		AnalysisStatus:         a.Status(),
		CommitOid:              a.CommitOid.String(),
		UpdatedAt:              serializeTime(&a.CreatedAt),
		Category:               a.Category.String(),
		ToolVersion:            a.ToolVersion.GetVersion(),
		Extensions:             extensions,
		Messages:               serializeAnalysisMessages(&a.Analysis),
		CreatedAt:              serializeTime(a.MinCreatedAt),
		AnalysisId:             uint64(a.ID),
		IsOutdated:             a.IsOutdated,
		DefaultQueriesDisabled: a.DefaultQueriesDisabled != nil && *a.DefaultQueriesDisabled,
		QuerySuites:            transforms.Map(a.AnalysisQuerySuites, serializeQuerySuites),
		HasMostRecent:          a.HasMostRecent,
		ConfigurationHash:      a.ConfigurationHash(),
		ConfigurationGroup: &proto.ConfigurationGroup{
			DeliveryOrigin: serializeDeliveryOrigin(a.DeliveryOrigin),
			WorkflowPath:   a.WorkflowPath.Bytes(),
		},
	}, nil
}
