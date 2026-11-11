package suggest

import (
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
)

func convertKindToProto(input SuggestionKind) pb.SuggestionKind {
	switch input {
	case QuerySuggestion:
		return pb.SuggestionKind_SUGGESTION_KIND_QUERY
	case PathSuggestion:
		return pb.SuggestionKind_SUGGESTION_KIND_PATH
	case SymbolSuggestion:
		return pb.SuggestionKind_SUGGESTION_KIND_SYMBOL
	default:
		return pb.SuggestionKind_SUGGESTION_KIND_UNKNOWN
	}
}

func ConvertToProto(input []Suggestion) []*pb.Suggestion {
	output := make([]*pb.Suggestion, len(input))
	for idx, s := range input {
		kind := convertKindToProto(s.Kind)
		if kind == pb.SuggestionKind_SUGGESTION_KIND_UNKNOWN {
			continue
		}

		output[idx] = &pb.Suggestion{
			Query:         s.Query,
			Kind:          kind,
			Path:          s.Path,
			RepositoryNwo: s.RepositoryNWO,
			RepositoryId:  s.RepositoryID,
			LanguageId:    s.LanguageID,
			CommitSha:     s.CommitSHA,
			LineNumber:    s.LineNumber,
			Symbol:        s.Symbol,
		}
	}

	return output
}
