package suggest

import (
	"context"
	"strings"

	"github.com/github/blackbird-mw/internal/gitaccess"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
)

func ExtractSuggestionsFromSearch(ctx context.Context, response *pb.QueryResponse) []Suggestion {
	output := []Suggestion{}

	for _, doc := range response.Documents {
		if len(doc.Locations) == 0 {
			continue
		}

		lineNumber := uint32(0)
		if len(doc.ScoringInfo.Snippets) > 0 {
			if doc.ScoringInfo.Snippets[0].EndingLineNumber > doc.ScoringInfo.Snippets[0].StartingLineNumber {
				snippetSize := doc.ScoringInfo.Snippets[0].EndingLineNumber - doc.ScoringInfo.Snippets[0].StartingLineNumber
				lineNumber = doc.ScoringInfo.Snippets[0].StartingLineNumber + (snippetSize / 2)
			}
		}

		commitOID := gitaccess.NewObjectIDFromBytes(doc.Locations[0].CommitSha)

		for _, symbol := range doc.ScoringInfo.MatchedSymbols {
			// Annoying to have to do this: but we need to convert from byte offsets to line numbers, which means
			// counting the number of newlines in the content...
			// Note that the line number starts by convention at 1, so the line number is 1 + the number of newlines
			lineNumber := strings.Count(string(doc.Content[:symbol.IdentStart]), "\n") + 1

			output = append(output, Suggestion{
				Kind:          SymbolSuggestion,
				Path:          doc.Locations[0].Path,
				RepositoryNWO: doc.Locations[0].RepoNwo,
				RepositoryID:  doc.Locations[0].RepoId,
				LanguageID:    doc.LanguageId,
				CommitSHA:     commitOID.String(),
				LineNumber:    uint32(lineNumber),
				Symbol:        symbol,
			})
		}

		// Only emit a file suggestion if we didn't get a symbol match to avoid duplication
		if len(doc.ScoringInfo.MatchedSymbols) == 0 {
			output = append(output, Suggestion{
				Kind:          PathSuggestion,
				Path:          doc.Locations[0].Path,
				RepositoryNWO: doc.Locations[0].RepoNwo,
				RepositoryID:  doc.Locations[0].RepoId,
				LanguageID:    doc.LanguageId,
				CommitSHA:     commitOID.String(),
				LineNumber:    lineNumber,
			})
		}
	}
	return output
}
