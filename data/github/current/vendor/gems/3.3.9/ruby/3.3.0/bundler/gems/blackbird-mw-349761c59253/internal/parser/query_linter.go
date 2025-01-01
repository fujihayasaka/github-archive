package parser

import (
	"context"
	"fmt"
	"regexp"
	"strings"
	"unicode"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/experiments"
)

type ErrorType int

// Constants for query error types. These map to the Protocol Buffer enum
// ErrorType. We don't use the Protocol Buffer type directly because that makes
// changing the values more difficult.
const (
	ErrorTypeParsingFatal ErrorType = iota
	ErrorTypeParsingWarning
	ErrorTypeMissingInaccessibleRepoOrg // The specified repo or user/org couldn't be searched. Requires InaccessibleRepoOrgNWO be set.
	ErrorTypeCodeEmbeddingsUnavailable  // The specified repo or user/org couldn't be with code embeddings. Requires InaccessibleRepoOrgNWO be set.
	ErrorTypeDocsEmbeddingsUnavailable  // The specified repo or user/org couldn't be with doc embeddings. Requires InaccessibleRepoOrgNWO be set.
)

type Range struct {
	Start uint32
	End   uint32
}

// QueryError reports an error for a range of the input query string. Maps to
// the Protocol Buffer QueryError type.
type QueryError struct {
	// The message to be displayed to the user; usually displayed as-is, but the
	// client can change what is displayed based on the ErrorType.
	Message string
	// Byte ranges indicating the start and end of the error in the input.
	Ranges []Range
	// An optional suggestion for fixing the problem.
	Suggestion string
	// The NWO of a repo or name of an user/org that could not be searched. Only valid for certain error types.
	InaccessibleRepoOrgNWO string
	// The classification of the error.
	Type ErrorType
}

func LintQuery(ctx context.Context, original string, userQuery *Query, combinedQuery *Query) ([]*QueryError, bool) {
	errors := []*QueryError{}

	// TODO(colinwm): implement more lint rules, such as:
	//  - detection of regex characters (e.g. $ or *)  in text nodes
	//  - suggestions for misspelled qualifiers

	// Fatal
	invalidRegularExpression(original, userQuery, &errors)
	validateSemanticSearch(ctx, combinedQuery, &errors)

	satisfactionErrors := []*QueryError{}
	satisfiable := checkSatisfiability(userQuery, &satisfactionErrors)

	for _, err := range satisfactionErrors {
		// If overall query is satisfiable, downgrade each satisfaction error to a warning.
		if satisfiable {
			err.Type = ErrorTypeParsingWarning
		}
		errors = append(errors, err)
	}

	// Warnings
	possibleBooleanOperator(original, userQuery, &errors)
	possibleUnrecognizedQualifier(original, userQuery, &errors)
	unrecognizedIsValue(original, userQuery, &errors)
	nonPrintingCharacters(original, &errors)

	// Don't trigger this if there are other errors, since it's lower priority
	if len(errors) == 0 {
		possibleLiteralRegularExpression(original, userQuery, &errors)
	}

	return errors, satisfiable
}

func nonPrintingCharacters(original string, errors *[]*QueryError) {
	ranges := []Range{}
	for pos, ch := range original {
		if !unicode.IsPrint(ch) {
			ranges = append(ranges, Range{uint32(pos), uint32(pos + 1)})
		}
	}

	if len(ranges) == 0 {
		return
	}

	mapped := strings.Map(func(ch rune) rune {
		if unicode.IsPrint(ch) {
			return ch
		}
		return -1
	}, original)

	*errors = append(*errors, &QueryError{
		Message:    "Query contains non-printing unicode characters",
		Ranges:     ranges,
		Suggestion: mapped,
		Type:       ErrorTypeParsingWarning,
	})
}

func possibleBooleanOperator(original string, query *Query, errors *[]*QueryError) {
	for idx, subquery := range query.Subqueries {
		if subquery.Kind == TextQuery {
			// If the user quoted it, they must not mean it to be an operator
			if subquery.IsQuoted {
				continue
			}

			value := strings.ToLower(subquery.Value)
			if value == "and" || value == "or" || value == "not" {

				suggestion := ""

				// If there's a subquery following this one, then we
				// can just rewrite this in uppercase (e.g. AND) and it should work
				if idx < len(query.Subqueries)-1 {
					suggestion = original[:subquery.Start] + strings.ToUpper(subquery.Value) + original[subquery.End:]
				}

				*errors = append(*errors, &QueryError{
					Message:    "Possible boolean operator used as a search term",
					Ranges:     []Range{{subquery.Start, subquery.End}},
					Suggestion: suggestion,
					Type:       ErrorTypeParsingWarning,
				})
			}
		} else {
			possibleBooleanOperator(original, subquery, errors)
		}
	}
}

// Detect any literals which might actually be regular expressions
func possibleLiteralRegularExpression(original string, query *Query, errors *[]*QueryError) {
	if query.Kind == TextQuery {
		if query.IsQuoted {
			return
		}

		possibleRegex := false
		for _, signal := range []string{".*", "\\w", "\\d", "$", "^", "]?", "]+"} {
			if strings.Contains(query.Value, signal) {
				possibleRegex = true
				break
			}
		}

		// Check whether it actually parses as a regex
		if possibleRegex {
			_, err := regexp.Compile(query.Value)
			if err == nil {
				inner := query.Value
				inner = strings.TrimPrefix(inner, "/")
				inner = strings.TrimSuffix(inner, "/")

				suggestion := original[:query.Start] + "/" + strings.Replace(inner, "/", "\\/", -1) + "/" + original[query.End:]

				*errors = append(*errors, &QueryError{
					Message:    "Searching for this literally, regular expressions must be surrounded by slashes.",
					Ranges:     []Range{{query.Start, query.End}},
					Type:       ErrorTypeParsingWarning,
					Suggestion: suggestion,
				})
			}
		}
	}

	for _, subquery := range query.Subqueries {
		possibleLiteralRegularExpression(original, subquery, errors)
	}
}

func invalidRegularExpression(original string, query *Query, errors *[]*QueryError) {
	if query.Kind == RegexQuery {
		r, err := regexp.Compile(query.Value)
		if err != nil {
			*errors = append(*errors, &QueryError{
				Message: "Invalid regular expression",
				Ranges:  []Range{{query.Start, query.End}},
				Type:    ErrorTypeParsingFatal,
			})
			return
		}

		// Valid regular expression. But does it match the empty string?
		if matched := r.MatchString(""); matched {
			*errors = append(*errors, &QueryError{
				Message: "Regular expression would match all documents",
				Ranges:  []Range{{query.Start, query.End}},
				Type:    ErrorTypeParsingFatal,
			})
		}

	}

	for _, subquery := range query.Subqueries {
		invalidRegularExpression(original, subquery, errors)
	}
}

func possibleUnrecognizedQualifier(original string, query *Query, errors *[]*QueryError) {
	if query.Kind == TextQuery {
		// If the user quoted it, they must not mean it to be an operator
		if query.IsQuoted {
			return
		}

		// Search for a colon
		idx := strings.Index(query.Value, ":")

		// If the colon is not present, or at the start or end of the term, it's
		// not an accidental qualifier
		if idx == -1 || idx == 0 || idx == len(query.Value)-1 {
			return
		}

		// If the string contains multiple colons, it's not an accidental qualifier
		if strings.Contains(query.Value[idx+1:], ":") {
			return
		}

		// Check if the qualifier is a known alias
		switch query.Value[:idx] {
		case "extension", "ext":
			suggestion := ""
			// Can't provide a suggestion for regex queries
			value := query.Value[idx+1:]
			if !strings.HasPrefix(value, "/") || !strings.HasSuffix(value, "/") {
				value = strings.TrimPrefix(value, "*")
				value = strings.TrimPrefix(value, ".")
				suggestion = original[:query.Start] + fmt.Sprintf("path:*.%s", value) + original[query.End:]
			}

			*errors = append(*errors, &QueryError{
				Message:    "Unrecognized qualifier. Looking for a file extension? Try using the path qualifier",
				Ranges:     []Range{{query.Start, query.End}},
				Suggestion: suggestion,
				Type:       ErrorTypeParsingWarning,
			})
		case "file", "filename":
			suggestion := ""
			// Can't provide a suggestion for regex queries
			value := query.Value[idx+1:]
			if !strings.HasPrefix(value, "/") || !strings.HasSuffix(value, "/") {
				suggestion = original[:query.Start] + fmt.Sprintf("path:**/%s", value) + original[query.End:]
			}

			*errors = append(*errors, &QueryError{
				Message:    "Unrecognized qualifier. Looking for a filename? Try using the path qualifier",
				Ranges:     []Range{{query.Start, query.End}},
				Suggestion: suggestion,
				Type:       ErrorTypeParsingWarning,
			})
		case "http", "https":
			// No need to do anything! That's a URL!
			break
		default:
			*errors = append(*errors, &QueryError{
				Message: "Possible unrecognized qualifier, searching for this term literally",
				Ranges:  []Range{{query.Start, query.End}},
				Type:    ErrorTypeParsingWarning,
			})
		}
	}

	for _, subquery := range query.Subqueries {
		possibleUnrecognizedQualifier(original, subquery, errors)
	}
}

func unrecognizedIsValue(original string, query *Query, errors *[]*QueryError) {
	if query.Kind == QualifierQuery && query.QualifierKind == IsQualifier {
		if query.Trait().ValidForIs() {
			return
		}

		*errors = append(*errors, &QueryError{
			Message: "Unrecognized is: qualifier value, searching for this term literally",
			Ranges:  []Range{{query.Start, query.End}},
			Type:    ErrorTypeParsingWarning,
		})
	}

	for _, subquery := range query.Subqueries {
		unrecognizedIsValue(original, subquery, errors)
	}
}

func containsEmbeddingSearch(query *Query) *Query {
	if query.Kind == QualifierQuery && query.QualifierKind == EmbeddingQualifier {
		return query
	}

	for _, subquery := range query.Subqueries {
		if q := containsEmbeddingSearch(subquery); q != nil {
			return q
		}
	}
	return nil
}

func validateSemanticSearch(ctx context.Context, query *Query, errors *[]*QueryError) {
	q := containsEmbeddingSearch(query)
	if q == nil {
		return
	}

	everything := newSatisfactionMatrix(query)
	sat := getTermSatisfiability(query, everything, &[]*QueryError{})
	if !sat.IsScopedToReposOrOwners() {
		logging.Error(ctx, "invalid semantic search query!", kvp.String("reason", "not_repo_owner_scoped"))
		statting.Counter(ctx, "semantic_query.validity", 1, stats.Tags{"valid": "false", "reason": "not_repo_owner_scoped"})
		*errors = append(*errors, &QueryError{
			Message: "Semantic searches must be scoped to an organization or repository",
			Ranges:  []Range{{q.Start, q.End}},
			Type:    ErrorTypeParsingFatal,
		})
		return
	}

	if invalid := noOtherQualifiersWithPrompt(query, errors); invalid != nil {
		// TODO: For now this is an informative metric, unless you include the
		// `all_semantic_search_lints` experiment.  Once we see the actual
		// incidence rate of this pattern we can gracefully migrate all callers
		// away from the pattern and start enforcing it.
		//
		// (This is controlled by an experiment so that our test cases can
		// validate what the error will be when we do start enforcing it, and so
		// that staff can test the error behavior in production.)
		logging.Error(ctx, "invalid semantic search query!", kvp.String("reason", "contains_extra_qualifiers"))
		statting.Counter(ctx, "semantic_query.validity", 1, stats.Tags{"valid": "false", "reason": "contains_extra_qualifiers"})
		if experiments.IsExperimentEnabled(ctx, experiments.AllSemanticSearchLints) {
			*errors = append(*errors, &QueryError{
				Message: "Semantic searches must not include any qualifiers other than repo and owner",
				Ranges:  []Range{{invalid.Start, invalid.End}},
				Type:    ErrorTypeParsingFatal,
			})
		}
		return
	}

	statting.Counter(ctx, "semantic_query.validity", 1, stats.Tags{"valid": "true"})
}

func isQualifierValidInEmbeddingQuery(query *Query) bool {
	// We do not include `prompt`, `repo`, or `owner` because linting happens
	// after we have already rewritten those into `embedding`, `repo_id`, etc.
	if query.QualifierKind == EmbeddingQualifier || query.QualifierKind == RepoIDQualifier || query.QualifierKind == OwnerIDQualifier {
		return true
	}

	if query.IsDefaultBranchTrait() || query.IsPublicRepoTrait() {
		return true
	}

	return false
}

func noOtherQualifiersWithPrompt(query *Query, errors *[]*QueryError) *Query {
	// We've already checked above that this query is an embedding query. We
	// only need to verify that it contains no other qualifiers besides
	// `repo_id` and `owner_id`.
	if query.Kind == QualifierQuery && !isQualifierValidInEmbeddingQuery(query) {
		return query
	}

	for _, subquery := range query.Subqueries {
		if q := noOtherQualifiersWithPrompt(subquery, errors); q != nil {
			return q
		}
	}

	return nil
}
