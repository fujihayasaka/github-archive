package suggest

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/parser"
	"github.com/github/blackbird-mw/internal/search"
)

// NOTE: Must be sorted in order to allow for binary search
var popularLanguageNames = []string{
	"ada",
	"c",
	"c#",
	"cpp",
	"crystal",
	"csharp",
	"dart",
	"fortran",
	"go",
	"hack",
	"haskell",
	"java",
	"javascript",
	"julia",
	"kotlin",
	"lua",
	"matlab",
	"objc",
	"perl",
	"php",
	"protobuf",
	"python",
	"ruby",
	"rust",
	"scala",
	"scheme",
	"shell",
	"sql",
	"swift",
	"typescript",
}

// Before running this function, we try to convert all unresolved qualifiers
// (e.g. language:python) into resolved, id-based qualifiers (e.g.
// language_id:371) or snapshot lookup traits (e.g. trait:nwo_github). Any
// remaining unresolved qualifiers are invalid. This function tries to find the
// first unresolved qualifier.
func findFirstUnresolvedQualifierNode(query *parser.Query) *parser.Query {
	if query.Kind == parser.NothingQuery && query.OriginalQuery != nil {
		return findFirstUnresolvedQualifierNode(query.OriginalQuery)
	}

	if query.Kind == parser.QualifierQuery {
		if query.QualifierKind == parser.LanguageQualifier ||
			query.QualifierKind == parser.OwnerQualifier ||
			query.Trait().RequiresResolution() {
			return query
		}
	}

	for _, subquery := range query.Subqueries {
		if node := findFirstUnresolvedQualifierNode(subquery); node != nil {
			return node
		}
	}

	return nil
}

func suggestUnknownQualifier(ctx context.Context, original string, query *parser.Query, searchIndex search.Index, actor *models.Actor) []Suggestion {
	output := []Suggestion{}

	if query.Kind == parser.NothingQuery && query.OriginalQuery != nil {
		return suggestUnknownQualifier(ctx, original, query.OriginalQuery, searchIndex, actor)
	}

	switch {
	case query.QualifierKind == parser.LanguageQualifier:
		languages := suggestPrefix(popularLanguageNames, query.Value)
		for _, lang := range languages {
			output = append(output, Suggestion{
				Kind:  QuerySuggestion,
				Query: fmt.Sprintf("%slanguage:%s%s", original[:query.Start], lang, original[query.End:]),
			})
		}
	case query.IsOwnerLoginTrait() || query.QualifierKind == parser.OwnerQualifier:
		owners, err := actor.FetchOwnerSuggetions(func(ids []int64) ([]*models.Owner, error) {
			return searchIndex.GetOwners(ctx, ids)
		})
		if err != nil {
			logging.Error(ctx, "failed to get owner suggestions", kvp.Err(err))
			break
		}

		val := query.Value
		if query.IsOwnerLoginTrait() {
			val = query.Trait().Text()
		}

		for _, owner := range owners {
			if strings.HasPrefix(owner.OwnerLogin, val) {
				s := Suggestion{
					Kind:  QuerySuggestion,
					Query: fmt.Sprintf("%sowner:%s%s", original[:query.Start], owner.OwnerLogin, original[query.End:]),
				}
				output = append(output, s)
			}
		}
	}

	return output
}
