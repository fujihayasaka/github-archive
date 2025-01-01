package elasticsearch

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/olivere/elastic"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
)

type AlertsSearchResult struct {
	AlertKeys  []ts.ESAlertKey
	Documents  []ts.SearchDocument
	PrevCursor string
	NextCursor string
}

var ErrESTimedOut = errors.New("ES query timed out")
var ErrMigrationOngoing = errors.New("ES migration in progress")

// SearchOrgAlerts uses the search index to return alerts for an entire organization.
func (e *Service) SearchOrgAlerts(
	ctx context.Context,
	filter *ts.SearchByOrgsFilter,
	pagination ts.Pagination,
	sort ts.SearchResultsSort) (AlertsSearchResult, error) {

	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "search-org-alerts")()

	result := AlertsSearchResult{
		AlertKeys: []ts.ESAlertKey{},
		Documents: []ts.SearchDocument{},
	}

	// We need to fetch an additional element to know whether there are more results.
	pagination.Limit += 1

	searchResults, err := e.searchOrgAlerts(ctx, filter, pagination, sort)
	if err != nil {
		return result, err
	}

	if len(searchResults) == 0 {
		return result, nil
	}

	hasPrev := pagination.Offset > 0 || pagination.Cursor != nil
	hasNext := len(searchResults) == int(pagination.Limit) // This means we fetched the original limit + 1
	if hasNext {
		// We fetched one extra element and need to remove it
		if pagination.Cursor != nil && pagination.Cursor.Descending {
			// The extra element is in the front
			searchResults = searchResults[1:]
		} else {
			// The extra element is in the back
			searchResults = searchResults[:len(searchResults)-1]
		}
	}
	if pagination.Cursor != nil && pagination.Cursor.Descending {
		// For descending cursors the meaning of previous and next is swapped
		hasPrev, hasNext = hasNext, hasPrev
	}

	for _, doc := range searchResults {
		lID := doc.AlertID
		pID, err := strconv.Atoi(doc.CanonicalID)
		if err != nil {
			return result, errors.Wrap(err, "failed to parse canonical ID")
		}
		repoID, err := strconv.Atoi(doc.RepositoryID)
		if err != nil {
			return result, errors.Wrap(err, "failed to parse repo ID")
		}

		result.AlertKeys = append(result.AlertKeys, ts.ESAlertKey{
			RepositoryID:      ts.RepositoryEID(repoID),
			LogicalAlertID:    ts.LogicalAlertID(lID),
			PhysicalAlertID:   ts.PhysicalAlertID(pID),
			IsFixed:           doc.FixedOnDefault,
			LastObservedFixAt: doc.FixedAt,
			LastStateChangeAt: doc.UpdatedAt,
		})
	}
	result.Documents = searchResults

	if hasPrev {
		first := searchResults[0]
		prev, err := buildCursor(first, sort.Fields)
		if err != nil {
			// Don't break the search if we can't build a cursor
			appctx.Logger(ctx).WithError(err).Error("failed to build cursor",
				kvp.Uint64("gh.turboscan.alert_id", first.AlertID),
				kvp.String("gh.turboscan.sort_fields", strings.Join(sort.Fields, ",")))
		}
		result.PrevCursor = prev
	}

	if hasNext {
		last := searchResults[len(searchResults)-1]
		next, err := buildCursor(last, sort.Fields)
		if err != nil {
			// Don't break the search if we can't build a cursor
			appctx.Logger(ctx).WithError(err).Error("failed to build cursor",
				kvp.Uint64("gh.turboscan.alert_id", last.AlertID),
				kvp.String("gh.turboscan.sort_fields", strings.Join(sort.Fields, ",")))
		}
		result.NextCursor = next
	}

	return result, nil
}

func (e *Service) searchOrgAlerts(ctx context.Context,
	filter *ts.SearchByOrgsFilter,
	pagination ts.Pagination,
	sort ts.SearchResultsSort) ([]ts.SearchDocument, error) {

	if !e.isValidPagination(ctx, pagination) {
		return nil, nil
	}

	// exclude potentially large fields from the search results, as they are not used
	// and can lead to significant memory usage
	source := elastic.NewFetchSourceContext(true).Exclude("help", "short_description", "full_description", "tags")
	searchQuery := e.es.Search().
		Index(orgLevelIndex.readAlias).
		Query(buildOrgAlertsQuery(filter)).
		From(int(pagination.Offset)).
		Size(int(pagination.Limit)).
		FetchSourceContext(source).
		RestTotalHitsAsInt(true)

	if pagination.Cursor != nil {
		cursorFields, err := extractCursorFields(sort.Fields, pagination.Cursor.String)
		if err != nil {
			// Cursor is invalid, return empty result
			appctx.Stats(ctx).Counter("es.invalid_query.count", stats.Tags{"reason": "cursor"}, 1)
			return nil, nil
		}
		searchQuery = searchQuery.SearchAfter(cursorFields...)
	}
	reverseSort := false
	if pagination.Cursor != nil && pagination.Cursor.Descending {
		reverseSort = true
	}
	sorters := buildSorters(sort, reverseSort)
	searchQuery = searchQuery.SortBy(sorters...)

	searchResult, err := searchQuery.Do(ctx)
	if err != nil {
		appctx.Logger(ctx).WithError(err).Info("Error when executing search query")
		if isIndexNotFoundError(err) {
			// Log and return no results.
			appctx.Logger(ctx).Info("Could not find index/alias for read", kvp.String("gh.turboscan.index", orgLevelIndex.readAlias))
			return nil, nil
		}
		// if the query syntax was invalid we just return the empty result set
		if !e.isValidQueryString(ctx, orgLevelIndex, filter.QueryString) {
			return nil, nil
		}
		return nil, errors.Wrap(err, "failed to search org alerts")
	}
	if searchResult.Hits == nil {
		return nil, nil
	}

	docs := []ts.SearchDocument{}
	for _, h := range searchResult.Hits.Hits {
		var doc ts.SearchDocument
		err := json.Unmarshal(*h.Source, &doc)
		if err != nil {
			return nil, errors.Wrap(err, "failed to unmarshall search results")
		}
		docs = append(docs, doc)
	}

	// If the results were fetched reversed, flip them back to the correct order
	if pagination.Cursor != nil && pagination.Cursor.Descending {
		for i, j := 0, len(docs)-1; i < j; i, j = i+1, j-1 {
			docs[i], docs[j] = docs[j], docs[i]
		}
	}
	return docs, nil
}

func (e *Service) CountOrgAlerts(ctx context.Context, filter *ts.SearchByOrgsFilter) (int64, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "count-org-alerts")()

	searchQuery := buildOrgAlertsQuery(filter)

	count, err := e.es.Count().
		Index(orgLevelIndex.readAlias).
		Query(searchQuery).
		Do(ctx)

	if err != nil {
		appctx.Logger(ctx).WithError(err).Info("Error when executing search query")
		if isIndexNotFoundError(err) {
			// Log and return no results.
			appctx.Logger(ctx).Info("Could not find index/alias for read", kvp.String("gh.turboscan.index", orgLevelIndex.readAlias))
			return 0, nil
		}
		// if the query syntax was invalid we just return the empty result set
		if !e.isValidQueryString(ctx, orgLevelIndex, filter.QueryString) {
			return 0, nil
		}
		return 0, errors.Wrap(err, "failed to count org alerts")
	}

	return count, nil
}

// CountOrgAlertsByRepositoryID will return alert counts aggregated by repository id.
// Results for filters with large numbers of repositories will be truncated.
// Use CountOrgAlerts for accurate global counts.
func (e *Service) CountOrgAlertsByRepositoryID(ctx context.Context, filter *ts.SearchByOrgsFilter) (counts map[ts.RepositoryEID]int64, total int64, err error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "count-org-alerts-by-repository-id")()

	items, err := e.aggQuery(ctx, filter, "repository_id")
	if err != nil {
		return nil, 0, errors.Wrap(err, "failed to count alerts")
	}

	counts = make(map[ts.RepositoryEID]int64, len(items))
	for _, bucket := range items {
		repoID, parseErr := strconv.ParseUint(bucket.Key.(string), 10, 64)
		if parseErr != nil {
			return nil, 0, errors.Wrapf(parseErr, "failed to convert repository ID %v to uint", bucket.Key)
		}
		counts[ts.RepositoryEID(repoID)] = bucket.DocCount
		total += bucket.DocCount
	}

	return
}

func (e *Service) CountOrgAlertsByCampaignID(ctx context.Context, filter *ts.SearchByOrgsFilter) (counts map[ts.SecurityCampaignEID]int64, err error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "count-org-alerts-by-campaign-id")()

	items, err := e.aggQuery(ctx, filter, "security_campaign_id")
	if err != nil {
		return nil, errors.Wrap(err, "failed to count alerts")
	}

	counts = make(map[ts.SecurityCampaignEID]int64, len(items))
	for _, bucket := range items {
		campaignID, parseErr := strconv.ParseUint(bucket.Key.(string), 10, 64)
		if parseErr != nil {
			return nil, errors.Wrapf(parseErr, "failed to convert campaignID %v to uint", bucket.Key)
		}
		counts[ts.SecurityCampaignEID(campaignID)] = bucket.DocCount
	}

	return
}

func (e *Service) SearchOrgToolNames(ctx context.Context, filter *ts.SearchByOrgsFilter) ([]*proto.ToolDescription, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "search-org-tool-names")()

	items, err := e.aggQuery(ctx, filter, "tool")
	if err != nil {
		return nil, errors.Wrap(err, "failed to search for tools")
	}
	tools := []*proto.ToolDescription{}
	for _, bucket := range items {
		// To avoid DB calls we return ToolDescriptions with only Name defined
		tools = append(tools, &proto.ToolDescription{
			Name:       bucket.Key.(string),
			AlertCount: uint64(bucket.DocCount),
		})
	}
	return tools, nil
}

func (e *Service) SearchOrgRepositoryIDs(ctx context.Context, filter *ts.SearchByOrgsFilter) ([]*proto.RepositoryIDsResponse_Repository, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "search-org-repository-ids")()

	items, err := e.aggQuery(ctx, filter, "repository_id")
	if err != nil {
		return nil, errors.Wrap(err, "failed to search for repository_ids")
	}
	repos := []*proto.RepositoryIDsResponse_Repository{}
	for _, bucket := range items {
		repoIDstring, ok := bucket.Key.(string)
		// This check is needed to satisfy the linter
		if !ok {
			return nil, errors.New("failed to fetch repo_id from document")
		}
		id, err := strconv.ParseUint(repoIDstring, 10, 64)
		if err != nil {
			return nil, errors.Wrap(err, "failed to convert repo_id to integer")
		}

		repo := &proto.RepositoryIDsResponse_Repository{
			RepositoryId: id,
			AlertCount:   uint64(bucket.DocCount),
		}

		repos = append(repos, repo)
	}
	return repos, nil
}

func (e *Service) SearchOrgRules(ctx context.Context, filter *ts.SearchByOrgsFilter) ([]*proto.OrgRule, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "search-org-rules")()

	// For rules we group by sarif-identifier. But because there could be several rules
	// for different repos with the same sarif identifier we have to somewhat arbitrarily
	// pick a description to use.
	// We have chosen to pick the description of the alert that was most recently updated.

	// This is implemented using a "top_hits" sub aggregation sorted on "updated_at"
	// picking only a single result for the top hit
	searchQuery := buildOrgAlertsQuery(filter)
	sourceContext := elastic.NewFetchSourceContext(true).Include("short_description", "tags")
	subAgg := elastic.NewTopHitsAggregation().Size(1).Sort("updated_at", false).FetchSourceContext(sourceContext)
	agg := elastic.NewTermsAggregation().
		Field("sarif_identifier").Size(2000).SubAggregation("top_hit", subAgg)

	search := e.es.Search().
		Index(orgLevelIndex.readAlias).
		Query(searchQuery).
		Aggregation("sarif_identifier", agg).
		Size(0). // we only care about the aggregations at the outer aggregation
		RestTotalHitsAsInt(true)

	searchResult, err := search.Do(ctx)
	if err != nil {
		if !e.isValidQueryString(ctx, orgLevelIndex, filter.QueryString) {
			return nil, nil
		}
		return nil, errors.Wrap(err, "failed to search for rules")
	}

	result, found := searchResult.Aggregations.Terms("sarif_identifier")
	if !found {
		return nil, nil
	}
	rules := []*proto.OrgRule{}
	for _, item := range result.Buckets {
		sarifIdentifier, ok := item.Key.(string)
		// This check is needed to satisfy the linter
		if !ok {
			return nil, errors.New("failed to fetch sarif_identifier from document")
		}
		topHits, hitsFound := item.TopHits("top_hit")
		if !hitsFound || topHits.Hits == nil {
			continue
		}
		for _, h := range topHits.Hits.Hits {
			var doc ts.SearchDocument
			err := json.Unmarshal(*h.Source, &doc)
			if err != nil {
				return nil, err
			}
			rules = append(rules, &proto.OrgRule{
				SarifIdentifier:  sarifIdentifier,
				ShortDescription: doc.ShortDescription,
				Tags:             doc.Tags,
				AlertCount:       uint64(item.DocCount),
			})
		}
	}

	return rules, nil
}

func (e *Service) SearchOrgRuleTags(ctx context.Context, filter *ts.SearchByOrgsFilter) ([]*proto.OrgRuleTag, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "search-org-rule-tags")()

	items, err := e.aggQuery(ctx, filter, "tags")
	if err != nil {
		return nil, errors.Wrap(err, "failed to search for tags")
	}
	var ruleTags []*proto.OrgRuleTag
	for _, bucket := range items {
		tag, ok := bucket.Key.(string)
		if !ok {
			return nil, errors.New("failed to fetch tags from document")
		}

		ruleTags = append(ruleTags, &proto.OrgRuleTag{
			Tag:        tag,
			AlertCount: uint64(bucket.DocCount),
		})
	}
	return ruleTags, nil
}

func (e *Service) SearchOrgSeverities(ctx context.Context, filter *ts.SearchByOrgsFilter) ([]*proto.SeveritiesForOrgResponse_SeverityItem, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "search-org-severities")()

	items, err := e.aggQuery(ctx, filter, "severity")
	if err != nil {
		return nil, errors.Wrap(err, "failed to search for severity")
	}
	tools := []*proto.SeveritiesForOrgResponse_SeverityItem{}
	for _, bucket := range items {
		severity, ok := bucket.Key.(string)
		// This check is needed to satisfy the linter
		if !ok {
			return nil, errors.New("failed to fetch sarif_identifier from document")
		}
		severityValue := proto.Severity_NO_SEVERITY
		if len(severity) > 0 {
			severityValue = proto.Severity(proto.Severity_value["SEVERITY_"+severity])
		}
		tools = append(tools, &proto.SeveritiesForOrgResponse_SeverityItem{
			Severity:   severityValue,
			AlertCount: uint64(bucket.DocCount),
		})
	}
	return tools, nil
}

func (e *Service) aggQuery(ctx context.Context, filter *ts.SearchByOrgsFilter, field string) ([]*elastic.AggregationBucketKeyItem, error) {
	searchQuery := buildOrgAlertsQuery(filter)

	agg := elastic.NewTermsAggregation().Field(field).Size(10000)

	search := e.es.Search().
		Index(orgLevelIndex.readAlias).
		Query(searchQuery).
		Aggregation(field, agg).
		Size(0). // we only care about the aggregations
		RestTotalHitsAsInt(true)

	searchResult, err := search.Do(ctx)

	if err != nil {
		appctx.Logger(ctx).WithError(err).Info("Error when executing search query")
		if isIndexNotFoundError(err) {
			// Log and return no results.
			appctx.Logger(ctx).Info("Could not find index/alias for read", kvp.String("gh.turboscan.index", orgLevelIndex.readAlias))
			return nil, nil
		}
		if !e.isValidQueryString(ctx, orgLevelIndex, filter.QueryString) {
			return nil, nil
		}
		return nil, err
	}

	result, found := searchResult.Aggregations.Terms(field)
	if !found {
		return nil, nil
	}
	return result.Buckets, nil
}

func buildOrgAlertsQuery(filter *ts.SearchByOrgsFilter) *elastic.BoolQuery {
	queryFilter := elastic.NewBoolQuery()

	// We must have a "fixed_on_default" field - otherwise the alert is not present on the default branch
	queryFilter = queryFilter.Must(elastic.NewExistsQuery("fixed_on_default"))

	if !filter.IncludeRepositoriesWithoutCodeScanningEnabled {
		// We must be in a repository that has code scanning enabled
		queryFilter = queryFilter.Must(elastic.NewTermQuery("code_scanning_enabled", true))
	}

	// We must only return alerts that are not marked as deleted
	queryFilter = queryFilter.Must(elastic.NewTermQuery("deleted", false))

	queryFilter = filterOwnerIDs(queryFilter, filter.OwnerIDs)

	queryFilter = filterRepositoryVisibility(queryFilter, filter.RepositoryVisibilities)

	queryFilter = filterRepositoryIDs(queryFilter, filter.RepositoryIDs)
	queryFilter = filterExcludedRepositoryIDs(queryFilter, filter.ExcludedRepositoryIDs)

	if filter.Resolution != nil {
		queryFilter = queryFilter.Must(elastic.NewTermQuery("resolution", filter.Resolution.String()))
	}

	if len(filter.Resolutions) > 0 {
		queryFilter = filterResolutions(queryFilter, filter.Resolutions)
	}
	queryFilter = filterExcludedResolutions(queryFilter, filter.ExcludedResolutions)

	queryFilter = filterState(queryFilter, filter.State)

	if len(filter.Severities) > 0 {
		queryFilter = filterSeverities(queryFilter, filter.Severities)
	}

	queryFilter = filterSeverity(queryFilter, filter.Severity)
	queryFilter = filterExcludedSeverities(queryFilter, filter.ExcludedSeverities)

	// This is ugly but will be way cleaner once we remove Tool/ToolGUID but
	// for nnow I need to do this so the linter doesn't yell at me for having
	// an if/else if/ else statement
	// It also insures that we are matching the behavior of the repo search
	switch {
	case filter.Tool != "":
		queryFilter = queryFilter.Must(elastic.NewTermQuery("tool.case_insensitive", filter.Tool))
	case len(filter.Tools) > 0:
		queryFilter = filterTools(queryFilter, filter.Tools)
	case filter.ToolGUID != "":
		queryFilter = queryFilter.Must(elastic.NewTermQuery("tool_guid", filter.ToolGUID))
	case len(filter.ToolGUIDs) > 0:
		queryFilter = filterToolGUIDs(queryFilter, filter.ToolGUIDs)
	}

	queryFilter = filterExcludedTools(queryFilter, filter.ExcludedTools)

	if filter.SarifIdentifier != "" {
		queryFilter = queryFilter.Must(elastic.NewTermQuery("sarif_identifier.case_insensitive", filter.SarifIdentifier))
	} else if len(filter.SarifIdentifiers) > 0 {
		queryFilter = filterSarifIdentifiers(queryFilter, filter.SarifIdentifiers)
	}

	queryFilter = filterExcludedSarifIdentifiers(queryFilter, filter.ExcludedSarifIdentifiers)

	if len(filter.Tags) > 0 {
		queryFilter = filterTags(queryFilter, filter.Tags)
	}
	queryFilter = filterExcludedTags(queryFilter, filter.ExcludedTags)

	if filter.QueryString != "" {
		queryFilter = queryFilter.Must(
			elastic.NewQueryStringQuery(filter.QueryString).
				Field("sarif_identifier").
				Field("rule_name").
				Field("short_description").
				Field("full_description").
				Field("help"),
		)
	}

	queryFilter = filterLogicalAlertIDs(queryFilter, filter.LogicalAlertIDs)

	queryFilter = filterRepoNumbers(queryFilter, filter.RepoNumbers)

	queryFilter = filterClassification(queryFilter, filter.Classification)

	queryFilter = filterAlertLinks(queryFilter, filter.AlertLinks)

	queryFilter = filterAutofixes(queryFilter, filter.Autofixes, false)

	queryFilter = filterAutofixes(queryFilter, filter.ExcludedAutofixes, true)

	queryFilter = filterSecurityCampaignIDs(queryFilter, filter.SecurityCampaignIDs)

	return elastic.NewBoolQuery().Filter(queryFilter)
}

func getSeverityQueryValue(severity proto.Severity) string {
	return strings.TrimPrefix(strings.ToUpper(severity.String()), "SEVERITY_")
}

func filterOwnerIDs(query *elastic.BoolQuery, ownerIDs []ts.OwnerEID) *elastic.BoolQuery {
	if len(ownerIDs) == 0 {
		return query
	}

	interfaceIDs := make([]interface{}, len(ownerIDs))
	for i, id := range ownerIDs {
		interfaceIDs[i] = id
	}

	return query.Must(elastic.NewTermsQuery("owner_id", interfaceIDs...))
}

func filterRepositoryVisibility(query *elastic.BoolQuery, repositoryVisibilities []string) *elastic.BoolQuery {
	if len(repositoryVisibilities) == 0 {
		return query
	}

	repoVisibilitiesArr := make([]interface{}, len(repositoryVisibilities))
	for i, visibility := range repositoryVisibilities {
		repoVisibilitiesArr[i] = visibility
	}

	return query.Must(elastic.NewTermsQuery("visibility", repoVisibilitiesArr...))
}

func filterRepositoryIDs(query *elastic.BoolQuery, repositoryIDs []ts.RepositoryEID) *elastic.BoolQuery {
	if len(repositoryIDs) == 0 {
		return query
	}

	repoIDs := make([]interface{}, len(repositoryIDs))
	for i, id := range repositoryIDs {
		repoIDs[i] = uint64(id)
	}
	return query.Must(elastic.NewTermsQuery("repository_id", repoIDs...))
}

func filterExcludedRepositoryIDs(query *elastic.BoolQuery, excludedRepositoryIDs []ts.RepositoryEID) *elastic.BoolQuery {
	if len(excludedRepositoryIDs) == 0 {
		return query
	}

	repoIDsToExclude := make([]interface{}, len(excludedRepositoryIDs))
	for i, id := range excludedRepositoryIDs {
		repoIDsToExclude[i] = uint64(id)
	}
	return query.MustNot(elastic.NewTermsQuery("repository_id", repoIDsToExclude...))
}

func filterSecurityCampaignIDs(query *elastic.BoolQuery, securityCampaignIDs []ts.SecurityCampaignEID) *elastic.BoolQuery {
	if len(securityCampaignIDs) == 0 {
		return query
	}

	scIDs := make([]interface{}, len(securityCampaignIDs))
	for i, id := range securityCampaignIDs {
		scIDs[i] = uint64(id)
	}
	return query.Must(elastic.NewTermsQuery("security_campaign_id", scIDs...))
}

func filterSeverity(query *elastic.BoolQuery, severity proto.Severity) *elastic.BoolQuery {
	if severity == proto.Severity_NO_SEVERITY {
		return query
	}
	severityString := getSeverityQueryValue(severity)
	return query.Must(elastic.NewTermQuery("severity", severityString))
}

func filterSeverities(query *elastic.BoolQuery, severities []proto.Severity) *elastic.BoolQuery {
	if len(severities) == 0 {
		return query
	}

	severityStrings := make([]interface{}, 0)
	for _, severity := range severities {
		if severity != proto.Severity_NO_SEVERITY {
			severityString := getSeverityQueryValue(severity)
			severityStrings = append(severityStrings, severityString)
		}
	}

	if len(severityStrings) == 0 {
		return query
	}

	return query.Must(elastic.NewTermsQuery("severity", severityStrings...))
}

func filterExcludedSeverities(query *elastic.BoolQuery, severitiesToExclude []proto.Severity) *elastic.BoolQuery {
	if len(severitiesToExclude) == 0 {
		return query
	}

	severityStrings := make([]interface{}, 0)
	for _, severity := range severitiesToExclude {
		if severity != proto.Severity_NO_SEVERITY {
			severityString := getSeverityQueryValue(severity)
			severityStrings = append(severityStrings, severityString)
		}
	}

	if len(severityStrings) == 0 {
		return query
	}

	return query.MustNot(elastic.NewTermsQuery("severity", severityStrings...))
}

func filterResolutions(query *elastic.BoolQuery, resolutions []*ts.AlertResolution) *elastic.BoolQuery {
	if len(resolutions) == 0 {
		return query
	}

	resolutionStrings := make([]interface{}, 0)
	for _, resolution := range resolutions {
		resolutionStrings = append(resolutionStrings, resolution.String())
	}

	return query.Must(elastic.NewTermsQuery("resolution", resolutionStrings...))
}

func filterExcludedResolutions(query *elastic.BoolQuery, resolutionsToExclude []*ts.AlertResolution) *elastic.BoolQuery {
	if len(resolutionsToExclude) == 0 {
		return query
	}

	resolutionStrings := make([]interface{}, 0)
	for _, resolution := range resolutionsToExclude {
		resolutionStrings = append(resolutionStrings, resolution.String())
	}

	return query.MustNot(elastic.NewTermsQuery("resolution", resolutionStrings...))
}

func filterTools(query *elastic.BoolQuery, tools []string) *elastic.BoolQuery {
	toolsToQuery := make([]interface{}, 0)
	for _, tool := range tools {
		if tool != "" {
			toolsToQuery = append(toolsToQuery, tool)
		}
	}

	if len(toolsToQuery) == 0 {
		return query
	}

	return query.Must(elastic.NewTermsQuery("tool.case_insensitive", toolsToQuery...))
}

func filterExcludedTools(query *elastic.BoolQuery, tools []string) *elastic.BoolQuery {
	toolsToQuery := make([]interface{}, 0)
	for _, tool := range tools {
		if tool != "" {
			toolsToQuery = append(toolsToQuery, tool)
		}
	}

	if len(toolsToQuery) == 0 {
		return query
	}

	return query.MustNot(elastic.NewTermsQuery("tool.case_insensitive", toolsToQuery...))
}

func filterToolGUIDs(query *elastic.BoolQuery, toolGUIDs []string) *elastic.BoolQuery {
	toolsToQuery := make([]interface{}, 0)
	for _, tool := range toolGUIDs {
		if tool != "" {
			toolsToQuery = append(toolsToQuery, tool)
		}
	}

	if len(toolsToQuery) == 0 {
		return query
	}

	return query.Must(elastic.NewTermsQuery("tool_guid", toolsToQuery...))
}

func filterSarifIdentifiers(query *elastic.BoolQuery, sarifIdentifiers []string) *elastic.BoolQuery {
	sarifIdentifierToQuery := make([]interface{}, 0)
	for _, sarifIdentifier := range sarifIdentifiers {
		if sarifIdentifier != "" {
			sarifIdentifierToQuery = append(sarifIdentifierToQuery, sarifIdentifier)
		}
	}

	if len(sarifIdentifierToQuery) == 0 {
		return query
	}

	return query.Must(elastic.NewTermsQuery("sarif_identifier.case_insensitive", sarifIdentifierToQuery...))
}

func filterExcludedSarifIdentifiers(query *elastic.BoolQuery, excludedSarifIdentifiers []string) *elastic.BoolQuery {
	if len(excludedSarifIdentifiers) == 0 {
		return query
	}

	sarifIdentifierToExclude := make([]interface{}, len(excludedSarifIdentifiers))
	for i, sarifIdentifier := range excludedSarifIdentifiers {
		sarifIdentifierToExclude[i] = sarifIdentifier
	}
	return query.MustNot(elastic.NewTermsQuery("sarif_identifier.case_insensitive", sarifIdentifierToExclude...))
}

func filterTags(query *elastic.BoolQuery, tags []string) *elastic.BoolQuery {
	tagToQuery := make([]interface{}, 0)
	for _, tag := range tags {
		if tag != "" {
			tagToQuery = append(tagToQuery, tag)
		}
	}

	if len(tagToQuery) == 0 {
		return query
	}

	return query.Must(elastic.NewTermsQuery("tags", tagToQuery...))
}

func filterExcludedTags(query *elastic.BoolQuery, excludedTags []string) *elastic.BoolQuery {
	if len(excludedTags) == 0 {
		return query
	}

	tagToExclude := make([]interface{}, 0)
	for _, tag := range excludedTags {
		tagToExclude = append(tagToExclude, tag)
	}

	return query.MustNot(elastic.NewTermsQuery("tags", tagToExclude...))
}

func filterLogicalAlertIDs(query *elastic.BoolQuery, logicalAlertIDs []ts.LogicalAlertID) *elastic.BoolQuery {
	if len(logicalAlertIDs) == 0 {
		return query
	}

	alertIDsToInclude := make([]interface{}, len(logicalAlertIDs))
	for i, alertID := range logicalAlertIDs {
		alertIDsToInclude[i] = alertID
	}
	return query.Must(elastic.NewTermsQuery("alert_id", alertIDsToInclude...))
}

func filterRepoNumbers(query *elastic.BoolQuery, repoNumbers []ts.RepoNumber) *elastic.BoolQuery {
	if len(repoNumbers) == 0 {
		return query
	}

	queries := []elastic.Query{}
	for _, repoNumber := range repoNumbers {
		queries = append(queries, elastic.NewBoolQuery().
			Must(elastic.NewTermQuery("repository_id", repoNumber.RepositoryID),
				elastic.NewTermQuery("number", repoNumber.Number)))
	}
	return query.Must(elastic.NewBoolQuery().Should(queries...))
}

func filterClassification(query *elastic.BoolQuery, classification proto.AlertClassificationFilter) *elastic.BoolQuery {
	switch classification {
	case proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_UNCLASSIFIED:
		query = query.MustNot(elastic.NewExistsQuery("classification"))
	case proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_ANY_CLASSIFICATION:
		query = query.Must(elastic.NewExistsQuery("classification"))
	case proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_NO_FILTER:
		// pass
	}
	return query
}

func filterAlertLinks(query *elastic.BoolQuery, alertLinks proto.AlertLinksFilter) *elastic.BoolQuery {
	switch alertLinks {
	case proto.AlertLinksFilter_ALERT_LINKS_FILTER_NO_LINKS:
		query = query.MustNot(elastic.NewExistsQuery("has_links"))
	case proto.AlertLinksFilter_ALERT_LINKS_FILTER_ANY_LINKS:
		query = query.Must(elastic.NewExistsQuery("has_links"))
	case proto.AlertLinksFilter_ALERT_LINKS_FILTER_NO_FILTER:
		// pass
	}
	return query
}

func filterAutofixes(query *elastic.BoolQuery, autofixes []proto.AutofixFilter, exclude bool) *elastic.BoolQuery {
	autofixQueries := make([]elastic.Query, 0)
	for _, af := range autofixes {
		q := queryAutofix(af)
		if q != nil {
			autofixQueries = append(autofixQueries, queryAutofix(af))
		}
	}

	if len(autofixQueries) == 0 {
		return query
	}

	if exclude {
		return query.MustNot(autofixQueries...)
	} else {
		return query.Must(autofixQueries...)
	}
}

func queryAutofix(autofix proto.AutofixFilter) elastic.Query {
	switch autofix {
	case proto.AutofixFilter_AUTOFIX_FILTER_SUPPORTED:
		return elastic.NewTermsQuery("autofix_eligible", true)
	case proto.AutofixFilter_AUTOFIX_FILTER_GENERATED:
		validStates := []interface{}{}
		for _, s := range ts.SuggestedFixAlertStateValidStates {
			validStates = append(validStates, s.DBString())
		}
		return elastic.NewTermsQuery("autofix_state", validStates...)
	case proto.AutofixFilter_AUTOFIX_FILTER_NO_FILTER:
		// pass
	}
	return nil
}

func filterState(query *elastic.BoolQuery, state proto.AlertStateFilter) *elastic.BoolQuery {
	switch state {
	case proto.AlertStateFilter_ALERT_STATE_FILTER_NONE, proto.AlertStateFilter_ALERT_STATE_FILTER_ALL:
		// Nothing to do
	case proto.AlertStateFilter_ALERT_STATE_FILTER_OPEN:
		query = query.
			Must(elastic.NewTermQuery("resolved", false)).
			Must(elastic.NewTermQuery("fixed_on_default", false))
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED:
		shouldQuery := elastic.NewBoolQuery().Should(
			elastic.NewTermQuery("resolved", true),
			elastic.NewTermQuery("fixed_on_default", true),
		)
		query = query.Must(shouldQuery)
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_RESOLVED:
		query = query.Must(elastic.NewTermQuery("resolved", true))
	case proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED_FIXED:
		query = query.Must(elastic.NewTermQuery("fixed_on_default", true))
	}
	return query
}

// buildSorters creates the ElasticSearch sorter objects
// In case of descending cursor pagination, we need to reverse the original sort order.
func buildSorters(sort ts.SearchResultsSort, reversed bool) []elastic.Sorter {
	sorters := []elastic.Sorter{}
	ascending := sort.Ascending
	if reversed {
		ascending = !ascending
	}

	for _, f := range sort.Fields {
		fieldSort := elastic.NewFieldSort(f)
		if ascending {
			fieldSort = fieldSort.Asc()
		} else {
			fieldSort = fieldSort.Desc()
		}
		sorters = append(sorters, fieldSort)
	}
	return sorters
}

// UpdateRepositoryMetadata updates ownership and code scanning status for all alert documents belonging to the given repository.
func (e *Service) UpdateRepositoryMetadata(ctx context.Context, repository ts.Repository) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "update-repo-metadata")()

	updateScript := elastic.NewScript(`
		ctx._source.owner_id = params.owner_id;
		ctx._source.visibility = params.visibility;
		ctx._source.code_scanning_enabled = params.code_scanning_enabled`).
		Param("owner_id", fmt.Sprint(repository.OwnerID)).
		Param("visibility", repository.Visibility.String).
		Param("code_scanning_enabled", repository.CodeScanningEnabled)
	query := elastic.NewTermQuery("repository_id", repository.RepositoryID)

	updateCmd := e.es.UpdateByQuery().
		Index(orgLevelIndex.writeAlias).
		Query(query).
		Script(updateScript).
		ProceedOnVersionConflict()

	resp, err := updateCmd.Do(ctx)
	if err != nil {
		return errors.Wrap(err, "failed to update repository metadata")
	}
	appctx.With(ctx, kvp.Int64("gh.turboscan.es_updated", resp.Updated))
	appctx.With(ctx, kvp.Int64("gh.turboscan.es_conflicts", resp.VersionConflicts))

	// Mirror command in upgrade scenarios
	updateCmdMirrorRequest := &updateByQuery{
		query:     query,
		script:    updateScript,
		conflicts: "proceed",
	}
	e.mirrorOperation(ctx, orgLevelIndex, Operation{Name: "UpdateRepositoryMetadata", UpdateCmd: updateCmdMirrorRequest})

	return nil
}

// UpdateAlerts updates the specified fields for all documents corresponding to the provided logical alert IDs
func (e *Service) UpdateAlerts(ctx context.Context,
	repoID ts.RepositoryEID,
	logicalAlertIDs []ts.LogicalAlertID, fields map[string]interface{}) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "update-alerts")()

	updates := []string{}
	for field := range fields {
		updates = append(updates, fmt.Sprintf("ctx._source.%s = params.%s", field, field))
	}
	script := elastic.NewScript(strings.Join(updates, ";"))
	for field, value := range fields {
		script = script.Param(field, value)
	}
	alertIDs := make([]interface{}, len(logicalAlertIDs))
	for i, id := range logicalAlertIDs {
		alertIDs[i] = uint64(id)
	}
	query := elastic.NewTermsQuery("alert_id", alertIDs...)
	updateCmd := e.es.UpdateByQuery().
		Index(orgLevelIndex.writeAlias).
		Query(query).
		Script(script).
		ProceedOnVersionConflict()

	_, err := updateCmd.Do(ctx)
	if err != nil {
		return errors.Wrap(err, "failed to update alerts field")
	}

	// Mirror command in upgrade scenarios
	updateCmdMirrorRequest := &updateByQuery{
		query:     query,
		script:    script,
		conflicts: "proceed",
	}
	e.mirrorOperation(ctx, orgLevelIndex, Operation{Name: "UpdateAlerts", UpdateCmd: updateCmdMirrorRequest})

	return nil
}

// AddCampaignEIDToAlerts adds the specified security campaign ID
// to all documents corresponding to the provided logical alert IDs
func (e *Service) AddCampaignEIDToAlerts(ctx context.Context,
	logicalAlertIDs []ts.LogicalAlertID,
	securityCampaignID ts.SecurityCampaignEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "update-alerts-add-to-field")()

	field := "security_campaign_id"
	updateStmt := fmt.Sprintf("if (ctx._source.containsKey('%s')) {ctx._source.%s.add(params.%s)} else {ctx._source.%s = [params.%s]}", field, field, field, field, field)
	script := elastic.NewScript(updateStmt)
	script.Param(field, fmt.Sprint(securityCampaignID))

	alertIDs := make([]interface{}, len(logicalAlertIDs))
	for i, id := range logicalAlertIDs {
		alertIDs[i] = uint64(id)
	}
	query := elastic.NewTermsQuery("alert_id", alertIDs...)
	updateCmd := e.es.UpdateByQuery().
		Index(orgLevelIndex.writeAlias).
		Query(query).
		Script(script).
		ProceedOnVersionConflict()

	_, err := updateCmd.Do(ctx)
	if err != nil {
		return errors.Wrap(err, "failed to update alerts and adding to field")
	}

	// Mirror command in upgrade scenarios
	updateCmdMirrorRequest := &updateByQuery{
		query:     query,
		script:    script,
		conflicts: "proceed",
	}
	e.mirrorOperation(ctx, orgLevelIndex, Operation{Name: "UpdateAlertsAddToField", UpdateCmd: updateCmdMirrorRequest})

	return nil
}

// DeleteByRepo deletes all ES documents for the specified repo, using the specified batchSize.
func (e *Service) DeleteByRepo(ctx context.Context, repoID ts.RepositoryEID, timeoutMillis int) (int64, error) {
	return e.DeleteByRepos(ctx, []ts.RepositoryEID{repoID}, timeoutMillis)
}

// DeleteByRepos deletes all ES documents for the specified repos.
func (e *Service) DeleteByRepos(ctx context.Context, repoIDs []ts.RepositoryEID, timeoutMillis int) (int64, error) {

	// If a migration is required or if we have a migration in progress,
	// then to make things safer we do not attempt any deletions.
	migrationRequired, err := e.MigrationRequired(ctx, ts.Index_OrgLevel)
	if err != nil {
		return 0, err
	}
	if migrationRequired {
		appctx.Logger(ctx).Info("Ongoing migration - stopping execution")
		return 0, ErrMigrationOngoing
	}

	interfaceRepoIDs := make([]interface{}, len(repoIDs))
	for i, repoID := range repoIDs {
		interfaceRepoIDs[i] = repoID
	}

	deleteCmd := e.es.DeleteByQuery().
		Index(orgLevelIndex.writeAlias).
		Query(elastic.NewTermsQuery("repository_id", interfaceRepoIDs...)).
		TimeoutInMillis(timeoutMillis).
		ProceedOnVersionConflict()

	response, err := deleteCmd.Do(ctx)
	if err != nil {
		return response.Deleted, errors.Wrap(err, "failed to delete repository objects")
	}
	if len(response.Failures) > 0 {
		return response.Deleted, errors.New("failures while deleting repository objects")
	}
	if response.TimedOut {
		appctx.Logger(ctx).Info("Deadline exceeded - stopping execution")
		return response.Deleted, ErrESTimedOut
	}

	return response.Deleted, nil
}

func isIndexNotFoundError(err error) bool {
	var elasticError *elastic.Error
	ok := errors.As(err, &elasticError)
	return ok && elasticError.Details != nil && elasticError.Details.Type == "index_not_found_exception"
}

// UpdateCanonicalIDs does a bulk update of the canonical_id field for the alerts specified in the alertIDmap.
// This is an optimization that relies on the canonical_id being the only thing that changes for fixed alerts.
// The ID is updated so that it doesnt point to old physical alerts that are later garbage collected.
// The updates are done in batches of 1000.
func (e *Service) UpdateCanonicalIDs(ctx context.Context, alertIDmap map[ts.LogicalAlertID]ts.PhysicalAlertID, batchSize int) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "update-canonical-ids")()

	bulkRequests := []elastic.BulkableRequest{}
	step := 0
	for la, pa := range alertIDmap {
		step += 1
		// Ideally we would have liked to look at the created_at field for the physical alerts
		// to determine which one should be canonical. However this information is not available in ES.
		// So we accept that we might be updating the canonical_id where we shouldnt have to. This is done
		// to prevent the canonical_id from pointing to a physical alert that is later garbage collected.
		// See https://github.com/github/code-scanning/issues/15548.
		stmt := "if (ctx._source.containsKey('fixed_on_default')) { ctx._source.canonical_id = params.new_id }"
		updateScript := elastic.NewScript(stmt).Param("new_id", fmt.Sprint(pa))
		req := elastic.NewBulkUpdateRequest().Id(fmt.Sprint(la)).Script(updateScript)
		bulkRequests = append(bulkRequests, req)

		if step%batchSize == 0 || step == len(alertIDmap) {
			bulk := e.es.Bulk().Index(orgLevelIndex.writeAlias)
			bulk.Add(bulkRequests...)
			resp, err := bulk.Do(ctx)
			if err != nil {
				return errors.Wrap(err, "failed to update canonical ids")
			}
			if len(resp.Failed()) > 0 {
				// This operation is expected to fail when we're performing an index migration, since the new
				// index might not yet contain all alerts.
				// This doesn't matter though, since the migration would reprocess all alert information and
				// the computed canonical IDs would be correct.
				indexMigration, err := e.MigrationRequired(ctx, ts.Index_OrgLevel)
				if err != nil || !indexMigration {
					// If we're not in a migration scenario, something went wrong and we should report the error.
					appctx.Logger(ctx).Error("failed to update canonical ids",
						kvp.Int("gh.turboscan.failed.count", len(resp.Failed())),
						kvp.Int("gh.turboscan.total.count", len(alertIDmap)),
						kvp.String("gh.turboscan.error", resp.Failed()[0].Error.Reason))
					return errors.New("failed to update canonical ids")
				}
			}
			// Mirror command in upgrade scenarios
			e.mirrorOperation(ctx, orgLevelIndex, Operation{Name: "UpdateCanonicalIDs", BulkRequests: bulkRequests})
			bulkRequests = []elastic.BulkableRequest{}
		}
	}
	return nil
}
