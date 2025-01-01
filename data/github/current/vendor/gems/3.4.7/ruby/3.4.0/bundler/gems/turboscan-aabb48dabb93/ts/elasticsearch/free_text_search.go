package elasticsearch

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/olivere/elastic"
	"github.com/pkg/errors"
)

// SearchRule executes a full text search and retrieves a unique set of rule SARIF identifiers
// Results are filtered by repoID.
func (e *Service) SearchRule(ctx context.Context, repoID ts.RepositoryEID, searchFilter ts.SearchFilter) ([]string, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "search-rule")()

	filters := elastic.NewBoolQuery().Must(elastic.NewTermQuery("repository_id", uint64(repoID)))
	if len(searchFilter.RuleSarifIDs) > 0 {
		sarifIdentifierToQuery := make([]interface{}, len(searchFilter.RuleSarifIDs))
		for i, sarifIdentifier := range searchFilter.RuleSarifIDs {
			sarifIdentifierToQuery[i] = sarifIdentifier
		}

		filters = filters.Must(elastic.NewTermsQuery("sarif_identifier", sarifIdentifierToQuery...))
	}
	if len(searchFilter.RuleTags) > 0 {
		for _, t := range searchFilter.RuleTags {
			filters = filters.Must(elastic.NewTermQuery("tags", t))
		}
	}

	if len(searchFilter.ExcludedRuleTags) > 0 {
		for _, t := range searchFilter.ExcludedRuleTags {
			filters = filters.MustNot(elastic.NewTermQuery("tags", t))
		}
	}

	if len(searchFilter.ExcludedRuleSarifIDs) > 0 {
		for _, t := range searchFilter.ExcludedRuleSarifIDs {
			filters = filters.MustNot(elastic.NewTermQuery("sarif_identifier", t))
		}
	}

	if searchFilter.QueryString != "" {
		filters = filters.Must(
			elastic.NewQueryStringQuery(searchFilter.QueryString).
				Field("short_description").
				Field("full_description").
				Field("help"),
		)
	}

	searchQuery := elastic.NewBoolQuery().Filter(filters)

	ruleSarifIdAgg := elastic.NewTermsAggregation().Field("sarif_identifier").Size(10000)

	search := e.es.Search().
		Index(orgLevelIndex.readAlias).
		Query(searchQuery).
		Aggregation("rule_sarif_id", ruleSarifIdAgg).
		Size(0). // we only care about the aggregations
		RestTotalHitsAsInt(true)

	searchResult, err := search.Do(ctx)

	if err != nil {
		if !e.isValidQueryString(ctx, orgLevelIndex, searchFilter.QueryString) {
			return nil, ts.ErrInvalidQuerySyntax
		}
		return nil, errors.Wrap(err, "failed to search for rules")
	}

	sarifIdentifiers := []string{}
	result, found := searchResult.Aggregations.Terms("rule_sarif_id")
	if !found {
		return sarifIdentifiers, nil
	}
	for _, bucket := range result.Buckets {
		sarifIdentifiers = append(sarifIdentifiers, bucket.Key.(string))
	}
	return sarifIdentifiers, nil
}
