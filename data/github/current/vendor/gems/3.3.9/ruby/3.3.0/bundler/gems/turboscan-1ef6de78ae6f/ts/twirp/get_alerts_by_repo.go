package twirp

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/tstypes"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetAlertsByRepo(ctx context.Context, req *proto.AlertsByRepoRequest) (*proto.AlertsByRepoResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.Uint32("gh.turboscan.limit", req.Limit),
		kvp.Uint32("gh.turboscan.numeric_page", req.NumericPage),
		kvp.String("gh.turboscan.sort_order", req.SortOrder.String()),
		kvp.String("gh.turboscan.state", req.State.String()),
		kvp.Strings("gh.turboscan.tools", req.Tools),
		kvp.Strings("gh.turboscan.excluded_tools", req.ExcludedTools),
		kvp.Strings("gh.turboscan.tool_guids", req.ToolGuids),
		kvp.Strings("gh.turboscan.excluded_tools", req.ExcludedTools),
		kvp.String("gh.turboscan.severities", fmt.Sprint(req.Severities)),
		kvp.String("gh.turboscan.excluded_severities", fmt.Sprint(req.ExcludedSeverities)),
		kvp.String("gh.turboscan.before_cursor", req.BeforeCursor),
		kvp.String("gh.turboscan.after_cursor", req.AfterCursor),
		kvp.String("gh.turboscan.search_query", req.SearchQuery),
		kvp.Strings("gh.turboscan.rule_sarif_identifiers", req.RuleSarifIdentifiers),
		kvp.Strings("gh.turboscan.excluded_sarif_identifiers", req.ExcludedRuleSarifIdentifiers),
		kvp.Strings("gh.turboscan.rule_tags", req.RuleTags),
		kvp.String("gh.turboscan.resolutions", fmt.Sprint(req.Resolutions)),
		kvp.Uint64s("gh.turboscan.excluded_repositories", req.ExcludedRepositoryIds),
		kvp.String("gh.turboscan.excluded_resolutions", fmt.Sprint(req.ExcludedResolutions)),
		kvp.String("gh.repo.visibility", fmt.Sprint(req.RepositoryVisibilities)),
		kvp.String("gh.turboscan.repo_numbers", fmt.Sprint(req.RepoNumbers)),
		kvp.String("gh.turboscan.autofix_filter", fmt.Sprint(req.Autofix)),
		kvp.String("gh.turboscan.security_campaign_ids", fmt.Sprint(req.SecurityCampaignIds)),
	)

	if len(req.OwnerIds) == 0 {
		return nil, o11y.RecordError(span, twerrors.RequiredArgumentError("owner_ids"))
	}

	ownerIds := req.OwnerIds

	// TODO update proto to leverage shared filter message
	alertsFilter := &proto.AlertsFilter{
		State:                        req.State,
		Tools:                        req.Tools,
		ToolGuids:                    req.ToolGuids,
		ExcludedTools:                req.ExcludedTools,
		RuleSarifIdentifiers:         req.RuleSarifIdentifiers,
		ExcludedRuleSarifIdentifiers: req.ExcludedRuleSarifIdentifiers,
		RuleTags:                     req.RuleTags,
		ExcludedRuleTags:             req.ExcludedRuleTags,
		Severities:                   req.Severities,
		ExcludedSeverities:           req.ExcludedSeverities,
		SearchQuery:                  req.SearchQuery,
		ExcludedResolutions:          req.ExcludedResolutions,
		RepositoryVisibilities:       req.RepositoryVisibilities,
		Resolutions:                  req.Resolutions,
		Classification:               req.Classification,
		AlertLinks:                   req.AlertLinks,
		Autofix:                      req.Autofix,
		Autofixes:                    req.Autofixes,
		ExcludedAutofixes:            req.ExcludedAutofixes,
		SecurityCampaignIds:          req.SecurityCampaignIds,
	}

	filter, err := tstypes.CreateSearchByOrgsFilter(ownerIds, req.RepositoryIds, req.ExcludedRepositoryIds, alertsFilter)
	if err != nil {
		return nil, o11y.RecordError(span, err)
	}

	filter.RepoNumbers = []ts.RepoNumber{}
	for _, rn := range req.RepoNumbers {
		filter.RepoNumbers = append(filter.RepoNumbers, ts.RepoNumber{
			RepositoryID: ts.RepositoryEID(rn.RepositoryId),
			Number:       rn.Number,
		})
	}

	sort := ts.SearchSortFromProto(req.SortOrder)
	pagination, err := tstypes.CreateHybridPaginationInfo(req.Limit, req.NumericPage, req.BeforeCursor, req.AfterCursor)
	if err != nil {
		return nil, o11y.RecordError(span, err)
	}

	searchResult, err := r.es.SearchOrgAlerts(ctx, filter, pagination, sort)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}
	results := []*proto.RepoResult{}
	logicalAlerts, err := r.alertService.GetAlertsByKeys(ctx, searchResult.AlertKeys)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	for _, la := range logicalAlerts {
		// Check that we have everything needed otherwises log an error
		// See: https://github.com/github/code-scanning/issues/2305
		if la.Rule.Tool == nil {
			return nil, o11y.RecordError(span, twerrors.InternalError("failed to load results"))
		}
		result, e := serializeResult(*la)
		if e != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(e))
		}

		logSeverityStats(ctx, *la)

		rr := &proto.RepoResult{
			Result:       result,
			RepositoryId: uint64(la.RepositoryID),
		}
		results = append(results, rr)
	}

	// For now we just fetch the counts sequentially
	filter.State = proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN
	openCount, err := r.es.CountOrgAlerts(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	filter.State = proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED
	resolvedCount, err := r.es.CountOrgAlerts(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	filter.State = proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN
	filter.AlertLinks = proto.AlertLinksFilter_ALERT_LINKS_FILTER_ANY_LINKS
	openLinksCount, err := r.es.CountOrgAlerts(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return &proto.AlertsByRepoResponse{
		Results:            results,
		OpenCount:          uint64(openCount),
		ResolvedCount:      uint64(resolvedCount),
		OpenWithLinksCount: uint64(openLinksCount),
		PrevCursor:         searchResult.PrevCursor,
		NextCursor:         searchResult.NextCursor,
	}, nil
}
