package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetRules(ctx context.Context, req *proto.RulesRequest) (*proto.RulesResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Strings("gh.turboscan.tools", req.Tools),
		kvp.String("gh.turboscan.search_query", req.SearchQuery),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	repo := ts.RepositoryEID(req.RepositoryId)
	ruleFilter := ts.RuleFilter{RepoID: repo, SearchQuery: req.SearchQuery}

	if len(req.Tools) > 0 {
		names := transforms.Map(req.Tools, ts.ToToolName)
		toolIDs, err := r.toolService.ToolIDs(ctx, &ts.ToolsFilter{CanonicalNames: names})
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
		if len(toolIDs) == 0 {
			return &proto.RulesResponse{Rules: []*proto.Rule{}}, nil
		}
		ruleFilter.ToolIDs = toolIDs
	}

	// attempt to use a replica for this endpoint if available
	ctx = gormext.WithTryReplica(ctx, true)
	tsRules, err := r.alertService.AlertsRules(ctx, ruleFilter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	// Deduplicate rules based on SarifIdentifier.
	values := make(map[string]ts.Rule, len(tsRules))
	for _, v := range tsRules {
		values[v.SarifIdentifier] = v
	}
	tsRules = make([]ts.Rule, 0, len(values))
	for _, v := range values {
		tsRules = append(tsRules, v)
	}

	rules, err := serializeRules(tsRules)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return &proto.RulesResponse{Rules: rules}, nil
}
