package twirp

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/turboscan/ts/mysql/pr_alerts"
	"github.com/pkg/errors"

	"golang.org/x/exp/maps"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"
	"github.com/github/turboscan/ts/validate"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func (r *ResultsResolver) EvalRefUpdateRules(ctx context.Context, req *proto.EvalRefUpdateRulesRequest) (*proto.EvalRefUpdateRulesResponse, error) {
	ctx, span := o11y.StartSpan(ctx,
		o11y.WithRepoIDFromRequest(req),
		trace.WithAttributes(
			attribute.String("gh.pull_request.base_ref", string(req.BaseRefBytes)),
			attribute.String("gh.pull_request.head_sha", req.HeadCommitOid),
			attribute.String("gh.pull_request.merge_sha", req.MergeCommitOid),
			attribute.Bool("gh.turboscan.is_dependabot", req.IsDependabot),
		),
	)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.ByteString("gh.pull_request.base_ref", req.BaseRefBytes),
		kvp.String("gh.pull_request.head_sha", req.HeadCommitOid),
		kvp.String("gh.pull_request.merge_sha", req.MergeCommitOid),
		kvp.Int("gh.turboscan.files_changed", len(req.FileChanges)),
		kvp.Bool("gh.turboscan.is_dependabot", req.IsDependabot),
	)

	// Check parameters

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("eval_ref_update_rules.repository_id")
	}
	repo := ts.RepositoryEID(req.RepositoryId)

	baseRef := string(req.BaseRefBytes)
	if !strings.HasPrefix(baseRef, "refs/heads") {
		return nil, twerrors.InvalidArgumentError("eval_ref_update_rules.base_ref_bytes", "must be a qualified ref")
	}

	if !validate.IsCommitOid(req.HeadCommitOid) {
		return nil, twerrors.InvalidArgumentError("eval_ref_update_rules.head_commit_oid", "must be a valid commit oid")
	}
	if req.MergeCommitOid != "" && !validate.IsCommitOid(req.MergeCommitOid) {
		return nil, twerrors.InvalidArgumentError("eval_ref_update_rules.merge_commit_oid", "must be a valid commit oid")
	}

	if len(req.RuleConfigs) == 0 {
		return nil, twerrors.RequiredArgumentError("eval_ref_update_rules.rule_configs")
	}

	// Get the data
	var usingCodeQL bool

	// Look up ids for all tools
	toolIDsByName := make(map[string][]ts.ToolID)
	for _, ruleConfig := range req.RuleConfigs {
		for _, toolConfig := range ruleConfig.ToolConfigs {
			if _, ok := toolIDsByName[toolConfig.Name]; !ok {
				toolName := ts.ToToolName(toolConfig.Name)
				usingCodeQL = usingCodeQL || ts.IsCodeQL(toolName)
				ids, err := r.toolService.ToolsIDsWithRenames(ctx, toolName)
				if err != nil {
					return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
				}
				if len(ids) == 0 {
					appctx.Logger(ctx).Info("tool not found",
						ts.RepositoryEID(req.RepositoryId).AsKVP(),
						kvp.String("gh.turboscan.tool", toolConfig.Name),
					)
				}
				toolIDsByName[toolConfig.Name] = ids
			}
		}
	}

	// Prefer the merge commit if it is available by putting it at the front of the list
	afterCommitOids := make([]ts.Sha, 0, 2)
	if req.MergeCommitOid != "" && req.MergeCommitOid != req.HeadCommitOid {
		afterCommitOids = append(afterCommitOids, ts.ToSha(req.MergeCommitOid))
	}
	afterCommitOids = append(afterCommitOids, ts.ToSha(req.HeadCommitOid))

	opts := &ts.PRAlertsOpts{
		AfterCommits: afterCommitOids,
		BaseRef:      baseRef,
		ToolIDs:      transforms.Unique(transforms.Flatten(maps.Values(toolIDsByName))),
		FileChanges:  req.FileChanges,
	}

	var codeQLOptional bool
	// no need to look this up if we do not appear to be using CodeQL
	if usingCodeQL {
		var err error
		codeQLOptional, err = r.statusService.IsCodeQLCheckOptional(ctx, ts.RepositoryEID(req.RepositoryId), req.IsDependabot)
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
	}

	toolAlertCounts, missingAnalyses, err := r.prAlertsService.PullRequestAlertsSummary(ctx, r.archiveService, repo, opts)
	if errors.Is(err, pr_alerts.ErrNoAnalyses) {
		if !codeQLOptional {
			return &proto.EvalRefUpdateRulesResponse{
				Results: []*proto.EvalRefUpdateRulesResponse_EvalResult{
					{FailureMessage: "Waiting for Code Scanning results. Code Scanning may not be configured for the target branch."},
				},
			}, nil
		}
	} else if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	// Index missing analyses
	missingAnalysesByTool := transforms.GroupBy(missingAnalyses, func(a ts.Analysis) ts.ToolID {
		return a.ToolID
	})

	// Now evaluate
	results := transforms.Map(req.RuleConfigs, func(ruleConfig *proto.EvalRefUpdateRulesRequest_RuleConfig) *proto.EvalRefUpdateRulesResponse_EvalResult {
		for _, toolConfig := range ruleConfig.ToolConfigs {
			if codeQLOptional && ts.IsCodeQL(ts.ToToolName(toolConfig.Name)) {
				continue
			}

			if result := evalTool(toolConfig, toolIDsByName[toolConfig.Name], toolAlertCounts, missingAnalysesByTool, afterCommitOids); result != nil {
				return result
			}
		}
		return &proto.EvalRefUpdateRulesResponse_EvalResult{
			Passed: true,
		}
	})

	// log results
	for _, result := range results {
		if result != nil {
			appctx.Logger(ctx).Info("rule evaluated",
				ts.RepositoryEID(req.RepositoryId).AsKVP(),
				kvp.Bool("gh.turboscan.passed", result.Passed),
				kvp.String("gh.turboscan.failure_message", result.FailureMessage),
			)
		}
	}

	return &proto.EvalRefUpdateRulesResponse{
		Results: results,
	}, nil
}

func evalTool(toolConfig *proto.EvalRefUpdateRulesRequest_ToolConfig, toolIDs []ts.ToolID, toolAlertCounts ts.ToolAlertCounts,
	missingAnalysesByTool map[ts.ToolID][]ts.Analysis, commits []ts.Sha) *proto.EvalRefUpdateRulesResponse_EvalResult {

	var hasResults bool
	var blockingAlertCount int
	var blockingSecurityAlertCount int
	var missingCategoriesCount int

	for _, toolID := range toolIDs {

		// Check for missing categories
		if missingAnalyses, ok := missingAnalysesByTool[toolID]; ok {
			missingCategoriesCount += len(transforms.MapUnique(missingAnalyses, func(a ts.Analysis) ts.Category {
				return a.Category
			}))
		}

		// Check for alerts
		if counts, ok := toolAlertCounts[toolID]; ok {
			hasResults = true

			switch toolConfig.AlertsThreshold {
			case proto.EvalRefUpdateRulesRequest_SEVERITY_NONE:
				// Count nothing
			case proto.EvalRefUpdateRulesRequest_SEVERITY_ALL:
				blockingAlertCount += counts.BySeverity[ts.SeverityLevelNote] + counts.BySeverity[ts.SeverityLevelWarning] + counts.BySeverity[ts.SeverityLevelError]
			case proto.EvalRefUpdateRulesRequest_SEVERITY_ERRORS_AND_WARNINGS:
				blockingAlertCount += counts.BySeverity[ts.SeverityLevelWarning] + counts.BySeverity[ts.SeverityLevelError]
			case proto.EvalRefUpdateRulesRequest_SEVERITY_ERRORS:
				blockingAlertCount += counts.BySeverity[ts.SeverityLevelError]
			}

			switch toolConfig.SecurityAlertsThreshold {
			case proto.EvalRefUpdateRulesRequest_SECURITY_SEVERITY_NONE:
				// Count nothing
			case proto.EvalRefUpdateRulesRequest_SECURITY_SEVERITY_ALL:
				blockingSecurityAlertCount += counts.BySecuritySeverity[proto.SecuritySeverity_LOW] + counts.BySecuritySeverity[proto.SecuritySeverity_MEDIUM] + counts.BySecuritySeverity[proto.SecuritySeverity_HIGH] + counts.BySecuritySeverity[proto.SecuritySeverity_CRITICAL]
			case proto.EvalRefUpdateRulesRequest_SECURITY_SEVERITY_MEDIUM_OR_HIGHER:
				blockingSecurityAlertCount += counts.BySecuritySeverity[proto.SecuritySeverity_MEDIUM] + counts.BySecuritySeverity[proto.SecuritySeverity_HIGH] + counts.BySecuritySeverity[proto.SecuritySeverity_CRITICAL]
			case proto.EvalRefUpdateRulesRequest_SECURITY_SEVERITY_HIGH_OR_HIGHER:
				blockingSecurityAlertCount += counts.BySecuritySeverity[proto.SecuritySeverity_HIGH] + counts.BySecuritySeverity[proto.SecuritySeverity_CRITICAL]
			case proto.EvalRefUpdateRulesRequest_SECURITY_SEVERITY_CRITICAL:
				blockingSecurityAlertCount += counts.BySecuritySeverity[proto.SecuritySeverity_CRITICAL]
			}
		}
	}

	if !hasResults {
		commitText := "commit"
		if len(commits) != 1 {
			commitText += "s"
		}
		return failureResult("Code scanning is waiting for results from %s for the %s %s.", toolConfig.Name, commitText, strings.Join(transforms.MapUnique(commits, ts.Sha.Short), " or "))
	}

	if missingCategoriesCount > 0 {
		var plural string
		if missingCategoriesCount > 1 {
			plural = "s"
		}
		return failureResult("Code scanning is still expecting %d result%s from %s for %s.", missingCategoriesCount, plural, toolConfig.Name, strings.Join(transforms.MapUnique(commits, ts.Sha.Short), " or "))
	}

	if blockingAlertCount > 0 {
		var plural string
		if blockingAlertCount > 1 {
			plural = "s"
		}
		return failureResult("%s has detected %d alert%s blocking this code from being merged.", toolConfig.Name, blockingAlertCount, plural)
	}

	if blockingSecurityAlertCount > 0 {
		var plural string
		if blockingSecurityAlertCount > 1 {
			plural = "s"
		}
		return failureResult("%s has detected %d security relevant alert%s blocking this code from being merged.", toolConfig.Name, blockingSecurityAlertCount, plural)
	}

	return nil
}

func failureResult(format string, args ...interface{}) *proto.EvalRefUpdateRulesResponse_EvalResult {
	return &proto.EvalRefUpdateRulesResponse_EvalResult{
		Passed:         false,
		FailureMessage: fmt.Sprintf(format, args...),
	}
}
