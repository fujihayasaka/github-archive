package parser

import (
	"context"
	"fmt"
	"regexp"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/parser/geyser"
)

func parseGeyserQueryNoRestrictions(text string) (*Query, error) {
	geyserQuery, err := geyser.ParseQuery(text)
	if err != nil {
		return nil, err
	}

	query, err := convertGeyserQuery(geyserQuery)
	if err != nil {
		return nil, err
	}

	// Geyser search didn't support searching archived repos
	SimplifyQuery(query)

	return query, nil
}

// These tests are adapted from:
//
// https://github.com/github/geyser/blob/af047473b2c6ff0f47dec456da359f04472ba968/search/transport/search_request_test.go
// https://github.com/github/geyser/blob/af047473b2c6ff0f47dec456da359f04472ba968/search/transport/syntax/githubv0/query_parser_test.go
//
// TODO: Implement simplification to throw away no-term searches:
//
//	Except with filename searches, you must always include at least one
//	search term when searching source code. For example, searching for
//	language:javascript is not valid, while amazing language:javascript is.
//
// TODO: Does code search return an error when it determine query is invalid? Should we do a Geyser linter for this?
func Test_ParseGeyserQuery(t *testing.T) {
	var tests = []struct {
		in    string
		out   *Query
		error string
	}{
		{
			in:  `foo "bar baz" language_id:303`,
			out: And(Content("foo"), Content("bar baz"), LanguageID(303)),
		},
		{
			in:    `"`,
			error: "parse error near Quote",
		},
		{
			in:  "foo",
			out: Content("foo"),
		},
		{
			in:  `foo "bar("`,
			out: And(Content("foo"), Content("bar(")),
		},
		{
			in:  `foo "bar baz"`,
			out: And(Content("foo"), Content("bar baz")),
		},
		{
			// TODO: This should be disallowed because there is no text term
			in:  `language_id:777 -language_id:666`,
			out: And(LanguageID(777), Not(LanguageID(666))),
		},
		{
			in:  `foo bar language_id:777 language_id:778 -language_id:666 -language_id:667`,
			out: And(Content("foo"), Content("bar"), LanguageID(777, 778), Not(LanguageID(666, 667))),
		},
		{
			in:  `foo notaqualifier:foo`,
			out: And(Content("foo"), Content("notaqualifier:foo")),
		},
		{
			// TODO: I believe this type of query (with no positive terms) is impossible in Geyser. Simplify to Nothing().
			in:  `-foo`,
			out: Not(Content("foo")),
		},
		{
			// TODO: I believe this type of query (with no positive terms) is impossible in Geyser. Simplify to Nothing().
			in:  `NOT foo`,
			out: Not(Content("foo")),
		},
		{
			in:  `-foo -path:bar`,
			out: And(Not(Content("foo")), Not(PathRegex("^bar/"))),
		},
		{
			in:  `-foo -bar baz -path:bar`,
			out: And(Content("baz"), Not(Or(Content("foo"), Content("bar"))), Not(PathRegex("^bar/"))),
		},
		{
			// Using the path: qualifier limits your search to this directory
			// (from the root) or below.
			in:  `foo path:/yabba/dabba/doo/`,
			out: And(Content("foo"), PathRegex("^yabba/dabba/doo/")),
		},
		{
			// This is a test for the special case of restricting the search to
			// the root of the repository.
			in:  `foo path:/`,
			out: And(Content("foo"), PathRegex("^[^/]+$")),
		},
		{
			// Geyser ignored fork:true, and searched forks by default. To fix a
			// user complaint and match the documentation, this is changed to
			// work like fork:only.
			in:  `foo fork:true`,
			out: And(Content("foo"), ForkRepo()),
		},
		{
			// fork:only restricts your search to forks.
			in:  `foo fork:only`,
			out: And(Content("foo"), ForkRepo()),
		},
		{
			in:    `foo fork:spoon`,
			error: "value for `fork` qualifier must be one of `true` or `only`",
		},
		{
			in:    `foo fork:true fork:only`,
			error: "`fork` qualifier can only be used once",
		},
		{
			in:    `foo in:path in:file`,
			error: "`in` qualifier can only be used once",
		},
		{
			in:  `filename:stuff`,
			out: PathRegex("[^/]*stuff[^/]*$"),
		},
		{
			in:  `foo extension:.js`,
			out: And(Content("foo"), PathRegex(`\.js$`)),
		},
		{
			in:  `foo extension:js`,
			out: And(Content("foo"), PathRegex(`\.js$`)),
		},
		{
			in:  `foo repo_id:3`,
			out: And(Content("foo"), RepoID(3)),
		},
		{
			in:  `foo user_id:3`,
			out: And(Content("foo"), OwnerID(3)),
		},
		{
			in:  `foo org_id:3`,
			out: And(Content("foo"), OwnerID(3)),
		},
		{
			in:  `foo repo_id:3 org_id:4 user_id:5`,
			out: And(Content("foo"), RepoID(3), OwnerID(4, 5)),
		},
		{
			in:  `foo sort:indexed-asc bar`, // sort: is dropped by the parser
			out: And(Content("foo"), Content("bar")),
		},
		{
			in:  `foo size:*..1000`,
			out: And(Content("foo"), MakeQualifier(SizeQualifier, NumericRange(NoLowerBound, 1001))),
		},
		{
			in:  `foo size:>=1024`,
			out: And(Content("foo"), MakeQualifier(SizeQualifier, NumericRange(1024, NoUpperBound))),
		},
		{
			in:  "repo:github/blackbird",
			out: Repo("github/blackbird"),
		},
		{
			in:  "user:colinwm",
			out: Owner("colinwm"),
		},
		{
			in:  "org:github",
			out: Owner("github"),
		},
		{
			in:  "language:python",
			out: Language("python"),
		},
	}

	for _, test := range tests {
		t.Run(test.in, func(t *testing.T) {
			query, err := parseGeyserQueryNoRestrictions(test.in)
			if test.error == "" {
				require.NoError(t, err)
				require.Equal(t, Serialize(test.out), Serialize(query))
			} else {
				require.Error(t, err)
				require.ErrorContains(t, err, test.error)
			}
		})
	}
}

func Test_ParseGeyserQueryRegexEscaping(t *testing.T) {
	containsSpecial := `^.*+/{0,2}|"'[]()?$`
	quoted := regexp.QuoteMeta(containsSpecial)

	// content doesn't allow regexes, so these are not escaped
	t.Run("content: is not escaped", func(t *testing.T) {
		requireGeyserParseNoRestrictions(t, Content(containsSpecial), containsSpecial)
	})

	t.Run("path: filter is escaped", func(t *testing.T) {
		query := fmt.Sprintf("path:%s", containsSpecial)
		requireGeyserParseNoRestrictions(t, PathRegex("^"+quoted+"/"), query)
	})

	t.Run("filename: is escaped", func(t *testing.T) {
		query := fmt.Sprintf("filename:%s", containsSpecial)
		requireGeyserParseNoRestrictions(t, PathRegex("[^/]*"+quoted+"[^/]*$"), query)
	})

	t.Run("extension: is escaped", func(t *testing.T) {
		query := fmt.Sprintf("extension:%s", containsSpecial)
		requireGeyserParseNoRestrictions(t, PathRegex(`\.`+quoted+"$"), query)
	})
}

// Legacy code search groups terms with AND and repeatable qualifiers with OR,
// unlike Blackbird which uses AND for everything by default.
//
// # Examples
//
// Legacy: extension:go extension:rs
// Blackbird: path:*.go OR path:*.rs
//
// Legacy: abc xyz extension:rs extension:go
// Blackbird: abc AND xyz AND (path:*.rs OR path:*.go)
func Test_ParseGeyserQueryGrouping(t *testing.T) {
	var tests = []struct {
		name string
		in   string
		out  *Query
	}{
		{
			name: "content terms are AND'ed",
			in:   `test "multiple terms" together`,
			out:  And(Content("test"), Content("multiple terms"), Content("together")),
		},
		{
			name: "extension qualifiers are OR'ed",
			in:   "extension:rb extension:go extension:rs",
			out:  Or(PathRegex(`\.rb$`), PathRegex(`\.go$`), PathRegex(`\.rs$`)),
		},
		{
			name: "repo qualifiers are OR'ed",
			in:   "repo:github/blackbird repo:github/blackbird-mw repo:github/blackbird-fe",
			out:  Or(Repo("github/blackbird"), Repo("github/blackbird-mw"), Repo("github/blackbird-fe")),
		},
		{
			name: "repo_id qualifiers are OR'ed",
			in:   "repo_id:1 repo_id:2 repo_id:3",
			out:  RepoID(1, 2, 3),
		},
		{
			name: "language_id qualifiers are OR'ed",
			in:   "language_id:1 language_id:2 language_id:3",
			out:  LanguageID(1, 2, 3),
		},
		{
			name: "language qualifiers are OR'ed",
			in:   "language:python language:ruby language:rust",
			out:  Or(Language("python"), Language("ruby"), Language("rust")),
		},
		{
			name: "org_id/user_id qualifiers are OR'ed",
			in:   "user_id:1 user_id:2 org_id:3 org_id:4",
			out:  OwnerID(1, 2, 3, 4),
		},
		{
			name: "org_id/user_id qualifiers are OR'ed",
			in:   "user_id:1 user_id:2 org_id:3 org_id:4",
			out:  OwnerID(1, 2, 3, 4),
		},
		{
			name: "org/user qualifiers are OR'ed",
			in:   "user:a user:b org:c",
			out:  Or(Owner("a"), Owner("b"), Owner("c")),
		},
		{
			name: "filename qualifiers are OR'ed",
			in:   "filename:a filename:b filename:c",
			out:  Or(PathRegex(`[^/]*a[^/]*$`), PathRegex(`[^/]*b[^/]*$`), PathRegex(`[^/]*c[^/]*$`)),
		},
		{
			name: "path qualifiers are OR'ed",
			in:   "path:foo path:bar",
			out:  Or(PathRegex(`^foo/`), PathRegex(`^bar/`)),
		},
		{
			name: "multiple types of qualifiers are AND'ed",
			in:   "path:foo path:bar filename:fileA filename:fileB",
			out:  And(Or(PathRegex(`^foo/`), PathRegex(`^bar/`)), Or(PathRegex(`[^/]*fileA[^/]*$`), PathRegex(`[^/]*fileB[^/]*$`))),
		},
		{
			name: "multiple qualifiers with multiple terms",
			in:   "term1 term2 filename:file1 filename:file2 repo_id:1 repo_id:2 org_id:1",
			out: And(
				Content("term1"),
				Content("term2"),
				Or(PathRegex(`[^/]*file1[^/]*$`), PathRegex(`[^/]*file2[^/]*$`)),
				RepoID(1, 2),
				OwnerID(1),
			),
		},
		{
			name: "complex parse with multiple terms, qualifiers, negation",
			in:   "term1 NOT term2 -filename:file1 path:/ org_id:1 org_id:2",
			out: And(
				Content("term1"),
				PathRegex("^[^/]+$"),
				OwnerID(1, 2),
				Not(Content("term2")),
				Not(PathRegex(`[^/]*file1[^/]*$`)),
			),
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			requireGeyserParseNoRestrictions(t, test.out, test.in)
		})
	}
}

// The original ES code search used Elasticsearch's [query_string] parser, which
// allows operators and grouping, but also makes it REALLY hard to control what
// users are searching for. Geyser built a query parser to fully control the ES
// query generation. Originally, we planned to support AND/OR, but in the
// end, we dropped it.
//
// [query_string]: https://www.elastic.co/guide/en/elasticsearch/reference/5.6/query-dsl-query-string-query.html
func Test_ParseGeyserQueryWithBooleanOperators(t *testing.T) {
	// NOT is the only operator, equivalent to -
	requireGeyserParseNoRestrictions(t, And(Content("foo"), Content("baz"), Not(Content("bar"))), "foo NOT bar baz")
	requireGeyserParseNoRestrictions(t, And(Content("foo"), Content("baz"), Not(Content("bar"))), "foo -bar baz")

	// If you want to search for NOT you have to quote it
	requireGeyserParseNoRestrictions(t, And(Content("NOT"), Content("foo")), `"NOT" foo`)

	// AND and OR are included literally in the query
	expected := And(
		Content("foo"),
		Content("AND"),
		Content("bar"),
		Content("AND"),
		Content("AND"),
		Content("abc"),
		Content("OR"),
		Content("xyz"),
		Not(Content("baz")),
	)
	requireGeyserParseNoRestrictions(t, expected, "foo AND bar AND NOT baz AND abc OR xyz")

	// open parenthesis are a parse error at the beginning of a term
	query, err := parseGeyserQueryNoRestrictions("(foo AND bar) OR baz")
	require.Error(t, err)
	require.ErrorContains(t, err, "parse error near ForbiddenStartChar")
	require.Nil(t, query)

	// You can use parenthesis within the text, though
	requireGeyserParseNoRestrictions(t, And(Content("foo(bar"), Content("[]io.Reader)")), "foo(bar []io.Reader)")
}

func Test_ParseGeyserQueryWithRestrictions(t *testing.T) {
	// With restrictions applied, we should exclude fork and archived repos
	requireGeyserParse(t, And(Content("foo(bar"), Content("[]io.Reader)"), NonForkRepo(), NonArchivedRepo()), "foo(bar []io.Reader)")

	// When fork:true or fork:only is set, we should allow it
	requireGeyserParse(t, And(Content("foo(bar"), Content("[]io.Reader)"), ForkRepo(), NonArchivedRepo()), "foo(bar []io.Reader) fork:only")
	requireGeyserParse(t, And(Content("foo(bar"), Content("[]io.Reader)"), ForkRepo(), NonArchivedRepo()), "foo(bar []io.Reader) fork:true")
}

// The default legacy code search behavior is to search file contents. Users can
// change that globally for the entire query with `in:path` (to search only
// paths) or `in:file,path` (to match paths OR files). There is no way to
// require a match in a path AND a file.
//
// The search will not be exactly the same because ES also tokenized filenames
// on case change and code characters like `-`, `.`, and `_`, but it should be
// close enough.
func Test_ParseGeyserQueryPathSplit(t *testing.T) {
	var tests = []struct {
		name string
		in   string
		out  *Query
	}{
		{
			name: "in:path searches only path",
			in:   `term1 term2 in:path`,
			out:  And(Path("term1"), Path("term2")),
		},
		{
			name: "in:path can be used with path filter",
			in:   `term in:path path:bar`,
			out:  And(Path("term"), PathRegex("^bar/")),
		},
		{
			name: "in:file is a content search",
			in:   `term1 term2 in:file`,
			out:  And(Content("term1"), Content("term2")),
		},
		{
			name: "in:path,file searches content OR paths",
			in:   `term1 term2 in:path,file`,
			out:  Or(And(Path("term1"), Path("term2")), And(Content("term1"), Content("term2"))),
		},
		{
			name: "in:path,file can be used with path filter",
			in:   `term1 term2 in:path,file path:thing`,
			out:  And(Or(And(Path("term1"), Path("term2")), And(Content("term1"), Content("term2"))), PathRegex("^thing/")),
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			requireGeyserParseNoRestrictions(t, test.out, test.in)
		})
	}
}

func Test_queryContainsForkQualifier(t *testing.T) {
	q := ForkRepo()
	require.True(t, queryContainsForkQualifier(q))

	q = And(Content("hello"), ForkRepo())
	require.True(t, queryContainsForkQualifier(q))

	q, err := parseGeyserQueryNoRestrictions(`term1 term2 in:path,file path:thing fork:only`)
	require.NoError(t, err)
	require.True(t, queryContainsForkQualifier(q))

	q, err = parseGeyserQueryNoRestrictions(`term1 term2 in:path,file path:thing fork:true`)
	require.NoError(t, err)
	require.True(t, queryContainsForkQualifier(q))

	q = Content("hello")
	require.False(t, queryContainsForkQualifier(q))

	q, err = parseGeyserQueryNoRestrictions(`term1 term2 in:path,file path:thing`)
	require.NoError(t, err)
	require.False(t, queryContainsForkQualifier(q))
}

func Test_QueryContainsInvalidStuff(t *testing.T) {
	_, err := parseGeyserQueryNoRestrictions(`  in:file`)
	require.Error(t, err)
}

func requireGeyserParseNoRestrictions(t *testing.T, expected *Query, input string) {
	t.Helper()

	query, err := parseGeyserQueryNoRestrictions(input)
	require.NoError(t, err)

	require.Equal(t, Serialize(expected), Serialize(query))
}

func requireGeyserParse(t *testing.T, expected *Query, input string) {
	t.Helper()

	query, err := ParseGeyserQuery(context.Background(), input)
	require.NoError(t, err)

	require.Equal(t, Serialize(expected), Serialize(query))
}
