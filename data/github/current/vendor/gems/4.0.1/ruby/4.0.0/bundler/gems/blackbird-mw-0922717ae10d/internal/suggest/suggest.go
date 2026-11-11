package suggest

import (
	"context"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"

	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/parser"
	"github.com/github/blackbird-mw/internal/search"
)

type SuggestionKind string

const (
	QuerySuggestion  SuggestionKind = "query"
	PathSuggestion   SuggestionKind = "path"
	SymbolSuggestion SuggestionKind = "symbol"
)

type Suggestion struct {
	Kind          SuggestionKind
	RepositoryNWO string
	Query         string
	Path          string
	LanguageID    uint32
	Language      string
	CommitSHA     string
	RepositoryID  uint32
	LineNumber    uint32
	Symbol        *pb.Symbol
}

func Suggest(ctx context.Context, query *parser.Query, original string, cursorPosition uint32, searchIndex search.Index, actor *models.Actor) []Suggestion {
	// Step 1: Determine if any nodes still have unresolved language/repo/org names, and suggest completions for the first one
	if node := findFirstUnresolvedQualifierNode(query); node != nil {
		return suggestUnknownQualifier(ctx, original, node, searchIndex, actor)
	}

	// Step 2: Figure out which node is under the cursor, and try to suggest for that node
	node := parser.FindQueryUnderCursor(query, cursorPosition)
	if node == nil {
		return nil
	}

	switch node.Kind {
	case parser.TextQuery:
		// TODO(colinwm): suggest repositories based on textquery content
		return nil
	}

	return nil
}

// Try to enforce some diversity between suggestion kinds, if possible
func RerankSuggestions(suggestions []Suggestion, suggestionLimit int) []Suggestion {
	if len(suggestions) == 0 {
		return suggestions
	}

	kinds := map[SuggestionKind]int{}
	for _, suggestion := range suggestions {
		if _, ok := kinds[suggestion.Kind]; !ok {
			kinds[suggestion.Kind] = 1
		} else {
			kinds[suggestion.Kind]++
		}
	}

	limitPerKind := suggestionLimit / len(kinds)
	extra := suggestionLimit
	limits := map[SuggestionKind]int{}
	for kind, num := range kinds {
		if num > limitPerKind {
			extra -= limitPerKind
		} else {
			extra -= num
		}

		limits[kind] = limitPerKind
	}

	output := []Suggestion{}
	for _, suggestion := range suggestions {
		if limits[suggestion.Kind] == 0 {
			if extra == 0 {
				continue
			} else {
				extra--
			}

		} else {
			limits[suggestion.Kind]--
		}

		output = append(output, suggestion)
	}
	return output
}
