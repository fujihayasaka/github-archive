package geyser

import (
	"fmt"
	"strings"
	"testing"

	"github.com/pkg/errors"
)

// GeyserParseError indicates that an error occurred while parsing the query string
type GeyserParseError struct {
	Err error
}

func (e *GeyserParseError) Error() string {
	return e.Err.Error()
}

// Retryable determines whether it makes sense to retry this error
func (e *GeyserParseError) Retryable() bool {
	return false
}

// Reportable determines whether it makes sense to report this error
func (e *GeyserParseError) Reportable() bool {
	return false
}

// ParsedQuery represents an arbitrarily nested query structure. There are two possibilities, either a ParsedQuery is a
// query group (in which case len(SubQueries)>0) XOR this is a leaf query (in which case len(Value)>0). ClauseType
// represents whether the clause is a Must, Should, or MustNot query. And Field is the name of that field (Field typically
// corresponds to the Elasticsearch fields rather than the GitHub syntax qualifiers).
type ParsedQuery struct {
	Field      Field
	Value      string
	ClauseType ClauseType
	SubQueries []*ParsedQuery
	IsPhrase   bool // doesn't matter to the semantics of the query, only tracked to re-serialize the query to string
}

// Clone returns a shallow clone of the provided Parsed Query
func Clone(parsedQuery *ParsedQuery) *ParsedQuery {
	return &ParsedQuery{
		Field:      parsedQuery.Field,
		Value:      parsedQuery.Value,
		ClauseType: parsedQuery.ClauseType,
		SubQueries: parsedQuery.SubQueries,
		IsPhrase:   parsedQuery.IsPhrase,
	}
}

// String returns the ParsedQuery serialized in lucene-like syntax
func (pq *ParsedQuery) String() string {
	str, _ := pq.string(Unspecified)
	return str
}

// TestString returns the ParsedQuery serialized in lucene-like syntax, but also fails the test if there is a validation error
func (pq *ParsedQuery) TestString(t *testing.T) string {
	str, err := pq.string(Unspecified)
	if err != nil {
		t.Fatal(err)
	}
	return str
}

func (pq *ParsedQuery) string(inheritedField Field) (string, error) {
	if pq.Value == "" && len(pq.SubQueries) == 0 {
		return "", errors.New("invalid query: both parsedQuery.Value and parsedQuery.SubQueries are empty")
	}
	if pq.Value != "" && len(pq.SubQueries) > 0 {
		return "", errors.New("invalid query: both parsedQuery.Value and parsedQuery.SubQueries are populated")
	}
	queryStr := ""
	switch {
	case len(pq.SubQueries) > 0:
		subQStrs := []string{}
		for _, subQ := range pq.SubQueries {
			sugQstr, err := subQ.string(pq.Field)
			if err != nil {
				return "", err
			}
			subQStrs = append(subQStrs, sugQstr)
		}
		queryStr = fmt.Sprintf("( %s )", strings.Join(subQStrs, " "))
	case pq.Value != "":
		if pq.IsPhrase {
			escapedPhrase := strings.Replace(pq.Value, `\`, `\\`, -1)
			escapedPhrase = strings.Replace(escapedPhrase, `"`, `\"`, -1)
			queryStr = fmt.Sprintf(`"%s"`, escapedPhrase)
		} else {
			queryStr = pq.Value
		}
	default:
		queryStr = "()"
	}

	// If inheritedField is present, then the field is already specified in an above group, so we don't have to print it again
	// but all clauses inside a fielded group must have the same field - so we're double checking that that's the case
	if inheritedField != Unspecified && inheritedField != pq.Field {
		// this panic should only occur in development when we've broken something; we have lots of tests around this
		return "", errors.Errorf("field `%s` is inconsistent with inherited field `%s`", pq.Field, inheritedField)
	}

	if inheritedField == Unspecified && pq.Field != Unspecified {
		queryStr = fmt.Sprintf("%s:%s", pq.Field, queryStr)
	}
	switch pq.ClauseType {
	case Must:
		queryStr = fmt.Sprintf("+%s", queryStr)
	case Filter:
		queryStr = fmt.Sprintf("#%s", queryStr)
	case MustNot:
		queryStr = fmt.Sprintf("-%s", queryStr)
	case Should:
		// nothing required
	default:
		return "", errors.Errorf("unknown clause type %s", pq.ClauseType)
	}
	return queryStr, nil
}

// Walk a ParsedQuery tree applying the walkFunc to each found query node. If any node causes
// the walkFunc to return an error, the walk is terminated with that error.
func (pq *ParsedQuery) Walk(walkFunc func(*ParsedQuery) error) error {
	next := []*ParsedQuery{pq}
	for len(next) > 0 {
		curr := next[0]
		next = next[1:]
		next = append(next, curr.SubQueries...)
		if err := walkFunc(curr); err != nil {
			return err
		}
	}
	return nil
}
