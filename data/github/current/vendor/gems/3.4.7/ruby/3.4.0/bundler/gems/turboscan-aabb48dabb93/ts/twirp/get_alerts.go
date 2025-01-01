package twirp

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/tstypes"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetAlerts(ctx context.Context, req *proto.AlertsRequest) (*proto.AlertsResponse, error) {
	ctx, span := o11y.StartSpan(ctx, o11y.WithRepoIDFromRequest(req))
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.turboscan.severities", fmt.Sprint(req.Severities)),
		kvp.String("gh.turboscan.excluded_severities", fmt.Sprint(req.ExcludedSeverities)),
		kvp.String("gh.turboscan.rule_sarif_identifiers", fmt.Sprint(req.RuleSarifIdentifiers)),
		kvp.String("gh.turboscan.excluded_rule_ids", fmt.Sprint(req.ExcludedRuleIds)),
		kvp.Uint64("gh.turboscan.limit", uint64(req.Limit)),
		kvp.Uint64("gh.turboscan.numeric_page", uint64(req.NumericPage)),
		kvp.Bool("gh.turboscan.resolved_only", req.ResolvedOnly),
		kvp.String("gh.turboscan.sort_order", req.SortOrder.String()),
		kvp.ByteStrings("gh.turboscan.ref_names", req.RefNamesBytes),
		kvp.String("gh.turboscan.rule_tags", strings.Join(req.RuleTags, ",")),
		kvp.String("gh.turboscan.excluded_tools", fmt.Sprint(req.ExcludedTools)),
		kvp.String("gh.turboscan.tools", fmt.Sprint(req.Tools)),
		kvp.String("gh.turboscan.resolutions", fmt.Sprint(req.Resolutions)),
		kvp.String("gh.turboscan.excluded_resolutions", fmt.Sprint(req.ExcludedResolutions)),
		kvp.String("gh.turboscan.state", req.State.String()),
		kvp.String("gh.turboscan.classification", req.Classification.String()),
		kvp.String("gh.turboscan.file_paths", fmt.Sprint(req.FilePaths)),
		kvp.String("gh.turboscan.language_file_paths", fmt.Sprint(req.LanguageFilePaths)),
		kvp.String("gh.turboscan.search_query", req.SearchQuery),
		kvp.String("gh.turboscan.cursor", fmt.Sprint(req.Cursor)),
	)

	if req.RepositoryId == 0 {
		return nil, twerrors.RequiredArgumentError("repository_id")
	}

	repositoryID := ts.RepositoryEID(req.RepositoryId)

	severities := req.Severities
	excludedSeverities := req.ExcludedSeverities

	resolutions, err := tstypes.ResolutionsFilterFromProto(req.Resolutions)
	if err != nil {
		return nil, twerrors.InvalidArgumentError("resolutions", "")
	}

	excludedResolutions, err := tstypes.ResolutionsFilterFromProto(req.ExcludedResolutions)
	if err != nil {
		return nil, twerrors.InvalidArgumentError("excluded resolutions", "")
	}

	response := &proto.AlertsResponse{}

	// This method should return true for AnalysisExists iff there is an analysis
	// for the specified refs (for any tool).
	// This is because it is being used for the blankslate page (see https://github.com/github/code-scanning/issues/6054).
	analysisFilterForRefs := ts.AnalysisFilter{
		RepositoryID:    repositoryID,
		Refs:            req.RefNamesBytes,
		State:           ts.AnalysisStateFilterMostRecent,
		IncludeOutdated: true,
	}

	response.AnalysisExists, err = r.alertService.AnalysisExists(ctx, analysisFilterForRefs)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	// No need to fetch alerts if we found no analysis.
	if !response.AnalysisExists {
		return response, nil
	}

	reqTools := transforms.Map(req.Tools, ts.ToToolName)
	var toolIDs []ts.ToolID
	if len(req.Tools) > 0 || len(req.ToolGuids) > 0 {
		toolIDs, err = r.toolService.ToolIDs(ctx, &ts.ToolsFilter{CanonicalNames: reqTools, GUIDs: req.ToolGuids})
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
		if len(toolIDs) == 0 {
			return response, nil
		}
	}

	reqExclTools := transforms.Map(req.ExcludedTools, ts.ToToolName)
	var excludedToolIDs []ts.ToolID
	if len(req.ExcludedTools) > 0 {
		excludedToolIDs, err = r.toolService.ToolIDs(ctx, &ts.ToolsFilter{CanonicalNames: reqExclTools})
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
	}

	ruleSarifIds := req.RuleSarifIdentifiers

	if req.SearchQuery != "" || len(req.RuleTags) > 0 || len(req.ExcludedRuleTags) > 0 {
		searchFilter := ts.SearchFilter{
			QueryString:          req.SearchQuery,
			RuleSarifIDs:         ruleSarifIds,
			RuleTags:             req.RuleTags,
			ExcludedRuleTags:     req.ExcludedRuleTags,
			ExcludedRuleSarifIDs: req.ExcludedRuleIds,
		}
		var searchResults []string
		searchResults, response.SearchStatus = r.applyRuleSearch(ctx, repositoryID, searchFilter)
		// We want to fail gracefully if ES returns an error, so we only use the
		// search results to override `ruleSarifIds` when response status is OK
		if response.SearchStatus == proto.SearchStatus_STATUS_OK {
			if len(searchResults) == 0 {
				// Bail out early if we found no search results.
				return response, nil
			}
			ruleSarifIds = searchResults
		} else if response.SearchStatus == proto.SearchStatus_STATUS_INVALID_QUERY {
			// Bail out early if the query is invalid
			// We want to make the invalid query status invisible to the exterior
			// so we return an empty result list
			response.SearchStatus = proto.SearchStatus_STATUS_OK // TODO: is this intended?
			return response, nil
		}
	}

	filter := createAlertFilter(
		severities,
		excludedSeverities,
		req.ResolvedOnly,
		resolutions,
		req.State,
		req.Classification,
		ruleSarifIds,
		req.ExcludedRuleIds,
		excludedResolutions,
		req.FilePaths,
		req.LanguageFilePaths,
		req.Numbers,
	)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	pagination := tstypes.CreatePaginationInfo(req.Limit, req.NumericPage)
	options := &ts.FindOptions{
		Pagination: &pagination,
		Preloads: []string{
			"Rule",
			"Rule.Tags",
			"Rule.Tool",
			"PhysicalAlerts",
			"PhysicalAlerts.Analysis",
			"PhysicalAlerts.Analysis.Tool",
			"PhysicalAlerts.Analysis.ToolVersion",
			"PhysicalAlerts.LastSeenAnalysis",
		},
		SortBy: alert.SortBy(req.SortOrder),
	}

	analysisFilter := ts.AnalysisFilter{
		RepositoryID:    repositoryID,
		Refs:            req.RefNamesBytes,
		ToolIDs:         toolIDs,
		ExcludedToolIDs: excludedToolIDs,
		State:           ts.AnalysisStateFilterMostRecent,
		IncludeOutdated: true,
	}

	// Fetch alerts, and 2 x counts in parallel
	g, gCtx := errgroup.WithContext(ctx)

	g.Go(func() error {
		var logicalAlerts []*ts.LogicalAlert
		if req.Cursor != nil {
			options.Pagination.Cursor = &ts.SerializedCursor{
				String:     req.Cursor.Value,
				Descending: req.Cursor.Descending,
			}
			searchResult, e := r.alertService.AlertsWithCursor(gCtx, repositoryID, *filter, analysisFilter, req.SortOrder, options)
			if e != nil {
				return o11y.RecordError(span, twerrors.InternalErrorWith(e))
			}
			logicalAlerts = searchResult.Results
			response.PrevCursor = searchResult.PrevCursor
			response.NextCursor = searchResult.NextCursor
		} else {
			var e error
			logicalAlerts, e = r.alertService.Alerts(gCtx, repositoryID, *filter, analysisFilter, options)
			if e != nil {
				return o11y.RecordError(span, twerrors.InternalErrorWith(e))
			}
		}

		for _, la := range logicalAlerts {
			// Check that we have everything needed otherwises log an error
			// See: https://github.com/github/code-scanning/issues/2305
			if la.Rule.Tool == nil {
				return o11y.RecordError(span, twerrors.InternalError("failed to load results"))
			}
			result, e := serializeResult(*la)
			if e != nil {
				return o11y.RecordError(span, twerrors.InternalErrorWith(e))
			}
			response.Results = append(response.Results, result)
		}

		return nil
	})

	g.Go(func() error {
		openFilter := *filter
		openFilter.State = alertStateFromResolvedOnly(false)

		var e error
		response.OpenCount, e = r.alertService.Count(gCtx, repositoryID, openFilter, analysisFilter)
		if e != nil {
			return o11y.RecordError(span, twerrors.InternalErrorWith(e))
		}
		return nil
	})

	g.Go(func() error {
		resolvedFilter := *filter
		resolvedFilter.State = alertStateFromResolvedOnly(true)

		var e error
		response.ResolvedCount, e = r.alertService.Count(gCtx, repositoryID, resolvedFilter, analysisFilter)
		if e != nil {
			return o11y.RecordError(span, twerrors.InternalErrorWith(e))
		}
		return nil
	})

	// Wait on all queries
	if err := g.Wait(); err != nil {
		return nil, err
	}

	// We can skip an extra Counts query if we already have the data we care about
	switch filter.State {
	case proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN:
		response.TotalCount = response.OpenCount
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED:
		response.TotalCount = response.ResolvedCount
	case proto.AlertStateFilter_ALERT_STATE_FILTER_ALL,
		proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_FIXED,
		proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_RESOLVED,
		proto.AlertStateFilter_ALERT_STATE_FILTER_NONE:
		response.TotalCount, err = r.alertService.Count(ctx, repositoryID, *filter, analysisFilter)
		if err != nil {
			return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
		}
	}

	return response, nil
}

func createAlertFilter(
	severities []proto.Severity,
	excludedSeverities []proto.Severity,
	resolvedOnly bool,
	resolutions []*ts.AlertResolution,
	state proto.AlertStateFilter,
	classification proto.AlertClassificationFilter,
	sarifIdentifiers []string,
	excludedSarifIdentifiers []string,
	excludedResolutions []*ts.AlertResolution,
	filePaths []string,
	languageFilePaths []string,
	numbers []uint32,
) *ts.AlertFilter {
	filter := &ts.AlertFilter{}

	filter.SeverityLevels = severities
	filter.ExcludedSeverityLevels = excludedSeverities

	// If it is defined, then the state filter takes priority over the
	// resolvedOnly filter
	if state == proto.AlertStateFilter_ALERT_STATE_FILTER_NONE {
		filter.State = alertStateFromResolvedOnly(resolvedOnly)
	} else {
		filter.State = state
	}

	// If resolution is nil, we still want to assign it
	// nil resolution = "any resolution, including not resolved"
	// resolution of 0 = "not resolved"
	filter.Resolutions = resolutions
	filter.ExcludedResolutions = excludedResolutions

	filter.Classification = classification

	filter.SarifIdentifiers = sarifIdentifiers
	filter.ExcludedSarifIdentifiers = excludedSarifIdentifiers

	filter.FilePaths = filePaths
	filter.LanguageFilePaths = languageFilePaths

	filter.Numbers = numbers

	return filter
}

// applyRuleSearch calls the search service with the given filter and returns the search results and status of the query.
func (r *ResultsResolver) applyRuleSearch(ctx context.Context, repositoryID ts.RepositoryEID, searchFilter ts.SearchFilter) ([]string, proto.SearchStatus) {
	if r.es == nil {
		return nil, proto.SearchStatus_STATUS_NOT_CONFIGURED
	}
	sarifIds, err := r.es.SearchRule(ctx, repositoryID, searchFilter)
	switch {
	case errors.Is(err, ts.ErrInvalidQuerySyntax):
		return nil, proto.SearchStatus_STATUS_INVALID_QUERY
	case err != nil:
		appctx.Logger(ctx).WithError(err).Error("error searching ElasticSearch",
			repositoryID.AsKVP(),
			kvp.String("gh.turboscan.search_query", searchFilter.QueryString),
			kvp.String("gh.turboscan.rule_sarif_identifiers", fmt.Sprint(searchFilter.RuleSarifIDs)),
			kvp.String("gh.turboscan.rule_tags", strings.Join(searchFilter.RuleTags, ",")),
		)
		return nil, proto.SearchStatus_STATUS_INTERNAL_ERROR
	default:
		return sarifIds, proto.SearchStatus_STATUS_OK
	}
}
