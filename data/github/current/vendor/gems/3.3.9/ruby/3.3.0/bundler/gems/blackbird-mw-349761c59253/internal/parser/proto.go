package parser

import (
	"fmt"
	"math"
	"regexp"

	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
)

// Text queries in the middleware AST representation should be considered as an OR
// over content and paths within blackbird.
func ConvertText(input *Query) *querypb.Query {
	if input.Kind == RegexQuery {
		// Unqualified regular expressions should just search content
		return &querypb.Query{
			Kind: querypb.QueryKind_QUERY_KIND_OR,
			Subqueries: []*querypb.Query{
				{
					Domain:      querypb.Domain_DOMAIN_CONTENT,
					Kind:        querypb.QueryKind_QUERY_KIND_REGEX,
					ValueString: input.Value,
				},
			},
			AstScore: input.ASTScore,
		}
	}

	// Other unqualified queries should match content, symbols, or paths
	return &querypb.Query{
		Kind: querypb.QueryKind_QUERY_KIND_OR,
		Subqueries: []*querypb.Query{
			{
				Domain:      querypb.Domain_DOMAIN_PATH,
				Kind:        querypb.QueryKind_QUERY_KIND_SUBSTRING,
				ValueString: input.Value,
			},
			{
				Domain:      querypb.Domain_DOMAIN_CONTENT,
				Kind:        querypb.QueryKind_QUERY_KIND_SUBSTRING,
				ValueString: input.Value,
			},
			{
				Domain:      querypb.Domain_DOMAIN_SYMBOLS,
				Kind:        querypb.QueryKind_QUERY_KIND_SUBSTRING,
				ValueString: input.Value,
			},
		},
		AstScore: input.ASTScore,
	}
}

func ConvertToProto(input *Query) *querypb.Query {
	var subqueries []*querypb.Query

	for _, subquery := range input.Subqueries {
		subqueries = append(subqueries, ConvertToProto(subquery))
	}

	domain := querypb.Domain_DOMAIN_UNSPECIFIED
	kind := querypb.QueryKind_QUERY_KIND_UNSPECIFIED
	var valueInt []int32
	var valueFloat []float32
	valueString := input.Value

	switch input.Kind {
	case TextQuery, RegexQuery:
		return ConvertText(input)
	case AndQuery:
		kind = querypb.QueryKind_QUERY_KIND_AND
	case OrQuery:
		kind = querypb.QueryKind_QUERY_KIND_OR
	case NotQuery:
		kind = querypb.QueryKind_QUERY_KIND_NOT
	case EverythingQuery:
		kind = querypb.QueryKind_QUERY_KIND_EVERYTHING
	case QueryGroup:
		// Groups are not represented within proto AST format
		return ConvertToProto(input.Subqueries[0])
	case QualifierQuery:
		kind = querypb.QueryKind_QUERY_KIND_QUALIFIER

		// Qualifier queries don't contain subqueries in proto AST format
		subqueries = nil

		switch input.QualifierKind {
		case PathQualifier:
			domain = querypb.Domain_DOMAIN_PATH
			valueString = input.Subqueries[0].Value
			if input.Subqueries[0].Kind == TextQuery {
				kind = querypb.QueryKind_QUERY_KIND_SUBSTRING
			} else {
				kind = querypb.QueryKind_QUERY_KIND_REGEX
			}
		case ContentQualifier:
			domain = querypb.Domain_DOMAIN_CONTENT
			valueString = input.Subqueries[0].Value
			if input.Subqueries[0].Kind == TextQuery {
				kind = querypb.QueryKind_QUERY_KIND_SUBSTRING
			} else {
				kind = querypb.QueryKind_QUERY_KIND_REGEX
			}
		case LanguageIDQualifier:
			domain = querypb.Domain_DOMAIN_LANGUAGE_ID
			for _, v := range input.IntValues {
				if v > math.MaxInt32 {
					panic(fmt.Sprintf("language ID %d is too large", v))
				}
				valueInt = append(valueInt, int32(v))
			}
		case RepoIDQualifier:
			domain = querypb.Domain_DOMAIN_REPO_ID
			for _, v := range input.IntValues {
				if v > math.MaxInt32 {
					panic(fmt.Sprintf("repo ID %d is too large", v))
				}
				valueInt = append(valueInt, int32(v))
			}
		case OwnerIDQualifier:
			domain = querypb.Domain_DOMAIN_OWNER_ID
			for _, v := range input.IntValues {
				if v > math.MaxInt32 {
					panic(fmt.Sprintf("owner ID %d is too large", v))
				}
				valueInt = append(valueInt, int32(v))
			}
		case TraitQualifier:
			domain = querypb.Domain_DOMAIN_TRAIT
			valueString = input.Subqueries[0].Value
		case SymbolQualifier:
			domain = querypb.Domain_DOMAIN_SYMBOLS
			valueString = input.Subqueries[0].Value
			if input.Subqueries[0].Kind == TextQuery {
				kind = querypb.QueryKind_QUERY_KIND_SUBSTRING
			} else {
				kind = querypb.QueryKind_QUERY_KIND_REGEX
			}
		case SymbolRefQualifier:
			domain = querypb.Domain_DOMAIN_SYMBOL_REFS
			kind = querypb.QueryKind_QUERY_KIND_QUALIFIER
			valueString = input.Subqueries[0].Value
		case SizeQualifier:
			domain = querypb.Domain_DOMAIN_DOC_SIZE
			valueString = fmt.Sprintf("%d..%d", input.Subqueries[0].LowerBound, input.Subqueries[0].UpperBound)
		case RepoQualifier:
			domain = querypb.Domain_DOMAIN_NWO
			kind = querypb.QueryKind_QUERY_KIND_REGEX

			valueString = input.Subqueries[0].Value
			// If the query is a text query, then we should rewrite it as a regular
			// expression matching only the repo name component of the NWO.
			if input.Subqueries[0].Kind == TextQuery {
				valueString = "/" + regexp.QuoteMeta(valueString) + "$"
			}
		case EmbeddingQualifier:
			domain = querypb.Domain_DOMAIN_DENSE
			valueFloat = input.Embedding
			valueInt = append(valueInt, int32(input.IntValues[0]))
		case BM25Qualifier:
			domain = querypb.Domain_DOMAIN_BM25
			valueString = input.Value
		}
	}

	return &querypb.Query{
		Kind:            kind,
		Domain:          domain,
		Subqueries:      subqueries,
		ValueInt:        valueInt,
		ValueString:     valueString,
		DivorToScore:    input.DivorToScore,
		DivorToRetrieve: input.DivorToRetrieve,
		AstScore:        input.ASTScore,
		ValueFloat:      valueFloat,
	}
}

func ConvertQueryErrorToProto(errors []*QueryError) []*pb.QueryError {
	output := make([]*pb.QueryError, len(errors))
	for idx, err := range errors {
		ranges := []*pb.ErrorRange{}
		for _, r := range err.Ranges {
			ranges = append(ranges, &pb.ErrorRange{Start: r.Start, End: r.End})
		}

		var errType pb.ErrorType
		switch err.Type {
		case ErrorTypeParsingFatal:
			errType = pb.ErrorType_ERROR_TYPE_QUERY_PARSING_FATAL
		case ErrorTypeMissingInaccessibleRepoOrg:
			errType = pb.ErrorType_ERROR_TYPE_MISSING_INACCESSIBLE_REPO_ORG
			if len(err.InaccessibleRepoOrgNWO) == 0 {
				panic("ErrorTypeMissingInaccessibleRepoOrg requires InaccessibleRepoOrgNWO")
			}
		case ErrorTypeDocsEmbeddingsUnavailable:
			errType = pb.ErrorType_ERROR_TYPE_DOCS_EMBEDDINGS_UNAVAILABLE
			if len(err.InaccessibleRepoOrgNWO) == 0 {
				panic("ErrorTypeDocsEmbeddingsUnavailable requires InaccessibleRepoOrgNWO")
			}
		case ErrorTypeCodeEmbeddingsUnavailable:
			errType = pb.ErrorType_ERROR_TYPE_CODE_EMBEDDINGS_UNAVAILABLE
			if len(err.InaccessibleRepoOrgNWO) == 0 {
				panic("ErrorTypeCodeEmbeddingsUnavailable requires InaccessibleRepoOrgNWO")
			}
		default:
			errType = pb.ErrorType_ERROR_TYPE_QUERY_PARSING_WARNING
		}

		output[idx] = &pb.QueryError{
			Type:                            errType,
			Message:                         err.Message,
			Ranges:                          ranges,
			Suggestion:                      err.Suggestion,
			MissingOrInaccessibleRepoOrgNwo: err.InaccessibleRepoOrgNWO,
		}
	}

	return output
}
