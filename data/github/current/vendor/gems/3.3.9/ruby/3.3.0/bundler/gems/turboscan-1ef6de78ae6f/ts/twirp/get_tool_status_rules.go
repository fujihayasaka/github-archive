package twirp

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
	tssarif "github.com/github/turboscan/ts/sarif"
)

func (r *ResultsResolver) GetToolStatusRules(ctx context.Context, req *proto.ToolStatusRulesRequest) (*proto.ToolStatusRulesResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	var cancelFunc context.CancelFunc
	ctx, cancelFunc = context.WithTimeout(ctx, 8*time.Second)
	defer cancelFunc()

	// attempt to use a replica for this endpoint if available
	ctx = gormext.WithTryReplica(ctx, true)

	appctx.Logger(ctx).Info("request received",
		ts.Ref(req.Ref).AsKVP(),
		ts.ToToolName(req.Tool).AsKVP(),
		kvp.String("gh.turboscan.analysis_ids", fmt.Sprint(req.AnalysisIds)),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	repoID := ts.RepositoryEID(req.RepositoryId)

	if len(req.Ref) == 0 {
		return nil, twerrors.RequiredArgumentError("ref")
	}

	if req.Tool == "" {
		return nil, twerrors.RequiredArgumentError("tool")
	}

	if len(req.AnalysisIds) == 0 {
		return nil, twerrors.RequiredArgumentError("analysis_ids")
	}

	toolIDs, err := r.toolService.ToolsIDsWithRenames(ctx, ts.ToToolName(req.Tool))
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	filter := ts.LatestAnalysisFilter{
		Ref:         req.Ref,
		ToolIDs:     toolIDs,
		AnalysisIDs: transforms.Map(req.AnalysisIds, func(id uint64) ts.AnalysisID { return ts.AnalysisID(id) }),
	}

	analyses, err := r.alertService.LatestAnalysesForRef(ctx, repoID, filter, false)
	if err != nil {
		return nil, err
	}

	output := &proto.ToolStatusRulesResponse{
		Categories: map[string]*proto.ToolStatusRulesResponse_CategoryRules{},
	}
	for _, analysis := range analyses {
		var rules *proto.ToolStatusRulesResponse_CategoryRules
		if analysis.ArchivalDataUrl != "" {
			rules, err = r.ruleCountsFromSarif(ctx, analysis)
		} else {
			rules, err = r.ruleCountsFromDb(ctx, analysis)
		}
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
		output.Categories[analysis.Category.String()] = rules
	}
	return output, nil
}

var ErrNoProcessedSarif = errors.New("no processed sarif found")
var ErrTooManyRuns = errors.New("too many runs in the processed sarif")
var ErrRequiredAnalysisID = errors.New("the analysis ID is a required argument")

func (r *ResultsResolver) ruleCountsFromSarif(ctx context.Context, analysis *ts.LatestAnalysis) (*proto.ToolStatusRulesResponse_CategoryRules, error) {
	sarifStr, err := r.archivalStore.Download(ctx, analysis.ArchivalDataUrl)
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error("failed to download processed sarif for analysis",
			analysis.RepositoryID.AsKVP(), analysis.ID.AsKVP(),
		)
		appctx.Stats(ctx).Counter("tool.status.error", stats.Tags{"reason": "sarif"}, 1)
		return nil, err
	}
	sarif, err := tssarif.Decode(sarifStr.Bytes())
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error("failed to decode processed sarif for analysis",
			analysis.RepositoryID.AsKVP(), analysis.ID.AsKVP(),
		)
		appctx.Stats(ctx).Counter("tool.status.error", stats.Tags{"reason": "sarif"}, 1)
		return nil, err
	}
	if len(sarif.Runs) != 1 {
		appctx.Logger(ctx).Error("unexpected number of runs for the processed sarif",
			analysis.RepositoryID.AsKVP(), analysis.ID.AsKVP(), kvp.String("gh.turboscan.archival_data_url", analysis.ArchivalDataUrl))
		appctx.Stats(ctx).Counter("tool.status.error", stats.Tags{"reason": "expected_runs"}, 1)
		return nil, ErrTooManyRuns
	}
	run := sarif.Runs[0]
	ruleCounts := map[string]uint64{}
	for _, result := range run.Results {
		ruleCounts[result.RuleId]++
	}
	origins := []*proto.ToolStatusRulesResponse_CategoryRules_RuleOrigins{}
	driverRules := make([]*proto.ToolStatusRulesResponse_CategoryRules_Rule, len(run.Tool.Driver.Rules))
	for i, rule := range run.Tool.Driver.Rules {
		driverRules[i] = &proto.ToolStatusRulesResponse_CategoryRules_Rule{
			SarifIdentifier: rule.Id,
			Results:         ruleCounts[rule.Id],
		}
	}
	if len(driverRules) > 0 {
		version := run.Tool.Driver.SemanticVersion
		if version == "" {
			version = run.Tool.Driver.Version
		}
		origins = append(origins, &proto.ToolStatusRulesResponse_CategoryRules_RuleOrigins{
			Origin: &proto.RuleOrigin{
				Name:    run.Tool.Driver.Name,
				Version: version,
			},
			Rules: driverRules,
		})
	}
	for _, extension := range run.Tool.Extensions {
		rules := make([]*proto.ToolStatusRulesResponse_CategoryRules_Rule, len(extension.Rules))
		for ri, rule := range extension.Rules {
			rules[ri] = &proto.ToolStatusRulesResponse_CategoryRules_Rule{
				SarifIdentifier: rule.Id,
				Results:         ruleCounts[rule.Id],
			}
		}
		if len(rules) > 0 {
			version := extension.SemanticVersion
			if version == "" {
				version = extension.Version
			}
			origins = append(origins, &proto.ToolStatusRulesResponse_CategoryRules_RuleOrigins{
				Origin: &proto.RuleOrigin{
					Name:    extension.Name,
					Version: version,
				},
				Rules: rules,
			})
		}
	}
	return &proto.ToolStatusRulesResponse_CategoryRules{
		Origins: origins,
	}, nil
}

func (r *ResultsResolver) ruleCountsFromDb(ctx context.Context, analysis *ts.LatestAnalysis) (*proto.ToolStatusRulesResponse_CategoryRules, error) {
	counts, err := r.alertService.AnalysisRulesCounts(ctx, analysis.RepositoryID, analysis.AnalysisRules)
	if err != nil {
		return nil, err
	}
	return serializeToolStatusCategoryRules(analysis, counts), nil
}
