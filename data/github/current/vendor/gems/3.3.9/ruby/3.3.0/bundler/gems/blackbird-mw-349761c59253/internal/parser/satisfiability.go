package parser

import (
	"fmt"
	"strings"
)

type state int

const (
	MatchesAll  state = 0
	MatchesSome state = 1
	MatchesNone state = 2
)

// The satisfactionMatrix is keyed by qualifier values, e.g. language, repo and orgs. When a query
// is constructed, we extract all mentioned languages, repos, and orgs (as well
// as one for each category representing all other values). The satisfactionMatrix has an entry for
// each one which represents whether the query is matches ALL documents in that category (MatchesAll),
// a SUBSET of documents in that category (MatchesSome) or matches NONE of the documents in that
// category (MatchesNone).
// All of the keys in the satsifactionMatrix are treated independently, and not all terms/qualifiers
// are represented, only categorical ones. So this is only an approximate measure of satisfiability.
type satisfactionMatrix map[string]state

func (s state) union(other state) state {
	if s > other {
		return other
	}
	return s
}

func (s state) intersection(other state) state {
	if s > other {
		return s
	}
	return other
}

func (s state) invert() state {
	switch s {
	case MatchesAll:
		return MatchesNone
	case MatchesNone:
		return MatchesAll
	default:
		return MatchesSome
	}
}

func union(a satisfactionMatrix, b satisfactionMatrix) satisfactionMatrix {
	out := satisfactionMatrix{}
	for k, v := range a {
		out[k] = v
	}
	for k, v := range b {
		out[k] = out[k].union(v)
	}
	return out
}

func intersection(a satisfactionMatrix, b satisfactionMatrix) satisfactionMatrix {
	out := satisfactionMatrix{}
	for k, v := range a {
		if _, ok := b[k]; ok {
			out[k] = v.intersection(b[k])
		}
	}
	return out
}

func invert(a satisfactionMatrix) satisfactionMatrix {
	out := satisfactionMatrix{}
	for k, v := range a {
		out[k] = v.invert()
	}
	return out
}

func setAll(a satisfactionMatrix, s state) satisfactionMatrix {
	out := satisfactionMatrix{}
	for k := range a {
		out[k] = s
	}
	return out
}

func restrict(a satisfactionMatrix, query *Query) satisfactionMatrix {
	categories := getQualifierCategories(query)
	if len(categories) == 0 {
		return a
	}

	out := satisfactionMatrix{}
	for k := range a {
		out[k] = MatchesSome
		for _, category := range categories {
			if strings.HasPrefix(k, category) {
				out[k] = MatchesNone
			}
		}
	}

	for key, state := range getQualifierKeys(query) {
		out[key] = state
	}

	return out
}

func IsSatisfiable(query *Query) bool {
	return checkSatisfiability(query, &[]*QueryError{})
}

func (s satisfactionMatrix) Satisfiable() bool {
	satisfiable := map[string]bool{
		"language": false,
		"repo":     false,
		"owner":    false,
	}
	for k, v := range s {
		if v == MatchesAll || v == MatchesSome {
			for category := range satisfiable {
				if strings.HasPrefix(k, category) {
					satisfiable[category] = true
				}
			}
		}
	}

	for _, v := range satisfiable {
		if !v {
			return false
		}
	}
	return true
}

func (s satisfactionMatrix) IsScopedToReposOrOwners() bool {
	// return true only if the query is scoped to a specific set of repos or orgs
	return s["repo:other"] == MatchesNone || s["owner:other"] == MatchesNone
}

func getQualifierCategories(query *Query) []string {
	if query.Kind == QualifierQuery {
		switch query.QualifierKind {
		case LanguageIDQualifier:
			return []string{"language"}
		case RepoIDQualifier:
			out := []string{"repo"}
			if query.MetadataOwnerID != 0 {
				out = append(out, "owner")
			}
			return out
		case OwnerIDQualifier:
			return []string{"owner"}
		}
	}

	return []string{}
}

func getQualifierKeys(query *Query) map[string]state {
	if query.Kind == QualifierQuery {
		switch query.QualifierKind {
		case LanguageIDQualifier:
			return map[string]state{
				fmt.Sprintf("language:%v", query.IntValues): MatchesAll,
			}
		case RepoIDQualifier:
			out := map[string]state{}
			for _, v := range query.IntValues {
				out[fmt.Sprintf("repo:%d", v)] = MatchesAll
			}
			if query.MetadataOwnerID != 0 {
				out[fmt.Sprintf("owner:%d", query.MetadataOwnerID)] = MatchesSome
			}
			return out
		case OwnerIDQualifier:
			out := map[string]state{}
			for _, v := range query.IntValues {
				out[fmt.Sprintf("owner:%d", v)] = MatchesAll
			}
			return out
		}
	}

	return map[string]state{}
}

// Creates a new satisfaction matrix with all fields set to true
func newSatisfactionMatrix(query *Query) satisfactionMatrix {
	out := satisfactionMatrix{
		"language:other": MatchesSome,
		"repo:other":     MatchesSome,
		"owner:other":    MatchesSome,
	}
	setupSatisfactionMatrix(query, out)
	return out
}

func setupSatisfactionMatrix(query *Query, matrix satisfactionMatrix) {
	for key := range getQualifierKeys(query) {
		matrix[key] = MatchesSome
	}

	for _, subquery := range query.Subqueries {
		setupSatisfactionMatrix(subquery, matrix)
	}
}

func checkSatisfiability(query *Query, errors *[]*QueryError) bool {
	everything := newSatisfactionMatrix(query)
	sat := getTermSatisfiability(query, everything, errors)
	return sat.Satisfiable()
}

func getTermSatisfiability(query *Query, everything satisfactionMatrix, errors *[]*QueryError) satisfactionMatrix {
	output := everything
	if query.Kind == OrQuery {
		for i, subquery := range query.Subqueries {
			sat := getTermSatisfiability(subquery, everything, errors)
			if i == 0 {
				output = sat
			} else {
				output = union(output, sat)
			}
		}
	} else if query.Kind == AndQuery {
		individuallySatisfiable := true
		for i, subquery := range query.Subqueries {
			sat := getTermSatisfiability(subquery, everything, errors)

			if !sat.Satisfiable() {
				individuallySatisfiable = false
			}

			if i == 0 {
				output = sat
			} else {
				output = intersection(output, sat)
			}
		}

		if !output.Satisfiable() && individuallySatisfiable {
			*errors = append(*errors, &QueryError{
				Message: "condition is unsatisfiable",
				Type:    ErrorTypeParsingFatal,
				Ranges: []Range{
					{query.Start, query.End},
				},
			})
		}
	} else if query.Kind == QueryGroup {
		return getTermSatisfiability(query.Subqueries[0], everything, errors)
	} else if query.Kind == NotQuery {
		sat := getTermSatisfiability(query.Subqueries[0], everything, errors)
		output = invert(sat)
	} else if query.Kind == EverythingQuery {
		output = setAll(output, MatchesAll)
	} else if query.Kind == NothingQuery {
		output = setAll(output, MatchesNone)
	} else {
		output = restrict(output, query)
	}

	return output
}
