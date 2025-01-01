package parser

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/types"
)

func expectParse(t *testing.T, input string, value *Query) {
	expectParseWithCtx(context.Background(), t, input, value)
}

func expectParseWithCtx(ctx context.Context, t *testing.T, input string, value *Query) {
	t.Helper()
	parsed, err := ParseQuery(ctx, input)
	require.Equal(t, nil, err)
	require.Equal(t, Serialize(value), Serialize(parsed))

}

func TestParseEmtpy(t *testing.T) {
	expectParse(t, "", Nothing())
	expectParse(t, "   ", Nothing())
}

func TestParseBasic(t *testing.T) {
	expectParse(t, "abcdef", Text("abcdef"))
}

func TestParseMultiLiteral(t *testing.T) {
	expectParse(t,
		`colin merkel "some more stuff"`,
		And(Text("colin"), Text("merkel"), Text("some more stuff")),
	)
}

func TestEscapedQuotes(t *testing.T) {
	expectParse(t,
		`"a quote: \""`,
		Text(`a quote: "`),
	)
	expectParse(t,
		`term "my quoted string" another`,
		And(Text("term"), Text("my quoted string"), Text("another")),
	)

	expectParse(t,
		`"\"test\""`,
		Text(`"test"`),
	)

	expectParse(t,
		`\"test\"`,
		Text(`"test"`),
	)
}

func TestEscapedBackslash(t *testing.T) {
	expectParse(t,
		`"c:\\test\\path"`,
		Text(`c:\test\path`),
	)

	expectParse(t,
		`a\\b\c`,
		Text(`a\b\c`),
	)

	expectParse(t,
		`\\\"`,
		Text(`\"`),
	)

	expectParse(t,
		`\\\`,
		Text(`\\`),
	)

	expectParse(t,
		`\\n`,
		Text(`\n`),
	)

	expectParse(t,
		`\"User\:\"`,
		Text(`"User\:"`),
	)

	expectParse(t,
		`"name = \"tensorflow\""`,
		Text(`name = "tensorflow"`),
	)

	expectParse(t,
		`"\\" "other string"`,
		And(Text("\\"), Text("other string")),
	)

	expectParse(t,
		`/\\/ /other regex/`,
		And(Regex(`\\`), Regex(`other regex`)),
	)
}

func Test_OpenParenBareTerm(t *testing.T) {
	expectParse(t,
		`repo:a/b ("entity_id",`,
		And(Repo("a/b"), Text(`("entity_id",`)),
	)
	expectParse(t,
		`("entity_id", repo:a/b`,
		And(Text(`("entity_id",`), Repo("a/b")),
	)
	expectParse(t,
		`("entity_id", `,
		Text(`("entity_id",`),
	)
}

func TestQualifiers(t *testing.T) {
	expectParse(t,
		"(trait:mytrait OR path:/.txt$/)",
		Group(Or(
			MakeQualifier(TraitQualifier, Text("mytrait")),
			MakeQualifier(PathQualifier, Regex(".txt$")),
		)),
	)
	expectParse(t,
		`path:/us?r/ language_id:41 foo`,
		And(
			MakeQualifier(PathQualifier, Regex("us?r")),
			LanguageID(41),
			Text("foo"),
		),
	)
	expectParse(t,
		"owner_id:5 OR user_id:6 OR org_id:7 OR language_id:12",
		Or(OwnerID(5), OwnerID(6), OwnerID(7), LanguageID(12)),
	)
	expectParse(t,
		"query repo_id:567",
		And(Text("query"), RepoID(567)),
	)
	expectParse(t,
		`query repo:"abcdef"`,
		And(Text("query"), Repo("abcdef")),
	)
	expectParse(t,
		`query repo:"github/abcdef"`,
		And(Text("query"), Repo("github/abcdef")),
	)

	expectParse(t, "repo_id:567 NOT (org_id:234 OR language_id:222)",
		And(RepoID(567), Not(Group(Or(OwnerID(234), LanguageID(222))))),
	)

	// Should convert to a symbol regex query
	expectParse(t, "def:QueryStream::new", Symbol(Regex("(^|\\.|::)QueryStream::new$")))

	// Check correct regex escaping
	expectParse(t, "def:$symbol::new", Symbol(Regex("(^|\\.|::)\\$symbol::new$")))

	// Non-regex symbol queries
	expectParse(t, "(symbol:abcd AND symbol:defg)", Group(And(Symbol(Text("abcd")), Symbol(Text("defg")))))
	expectParse(t, "symbol:\"abcd defg\"", Symbol(Text("abcd defg")))

	// Negaqualifier
	expectParse(t, "-symbol:\"abcd defg\"", Not(Symbol(Text("abcd defg"))))

	// Nega-negaqualifier
	expectParse(t, "NOT -symbol:\"abcd defg\"", Not(Not(Symbol(Text("abcd defg")))))

	// is qualifier with valid value
	expectParse(t, "is:archived", Is("archived"))
	expectParse(t, "NOT is:archived", Not(Is("archived")))
	expectParse(t, "-is:archived", Not(Is("archived")))
	expectParse(t, "is:generated", Is("generated"))
	expectParse(t, "is:vendored", Is("vendored"))

	// is qualifier with invalid value still parses, handled by LintQuery
	expectParse(t, "is:something", Is("something"))
}

func TestQuotedStringQualifier(t *testing.T) {
	// Quoted string language qualifier
	expectParse(t, `language:"Protocol Buffer"`, Language("Protocol Buffer"))

	// Quoted string path qualifier
	expectParse(t, `path:"My Path"`,
		MakeQualifier(PathQualifier, Text("My Path")),
	)
}

func TestNotQuery(t *testing.T) {
	expectParse(t, "NOT repo_id:567", Not(RepoID(567)))
	expectParse(t, "abc NOT repo_id:567", And(Text("abc"), Not(RepoID(567))))
}

func TestAndSequence(t *testing.T) {
	expectParse(t,
		"xyz AND abc AND repo_id:567",
		And(Text("xyz"), Text("abc"), RepoID(567)),
	)
}

func TestOrSequence(t *testing.T) {
	expectParse(t,
		"xyz OR abc OR repo_id:567",
		Or(Text("xyz"), Text("abc"), RepoID(567)),
	)
}

func TestSubExpression(t *testing.T) {
	expectParse(t,
		"(x AND y) AND (z AND zz)",
		And(Group(And(Text("x"), Text("y"))), Group(And(Text("z"), Text("zz")))),
	)
	expectParse(t,
		"x AND (y z)",
		And(Text("x"), Group(And(Text("y"), Text("z")))),
	)
	expectParse(t,
		"x AND (y AND NOT z)",
		And(Text("x"), Group(And(Text("y"), Not(Text("z"))))),
	)
	expectParse(t,
		"xyz AND (abc OR repo_id:567)",
		And(Text("xyz"), Group(Or(Text("abc"), RepoID(567)))),
	)
	expectParse(t,
		"xyz AND NOT (abc OR repo_id:567)",
		And(Text("xyz"), Not(Group(Or(Text("abc"), RepoID(567))))),
	)
	expectParse(t,
		"xyz AND abc OR repo_id:567",
		Or(And(Text("xyz"), Text("abc")), RepoID(567)),
	)
	expectParse(t,
		"x OR (y OR z)",
		Or(Text("x"), Group(Or(Text("y"), Text("z")))),
	)

	expectParse(t,
		`"(in parens)"`,
		Text("(in parens)"),
	)
}

func TestRepoIdExtraction(t *testing.T) {
	var tests = []struct {
		name     string
		query    string
		expected []types.RepoID
	}{
		{
			name:     "no repo IDs in query",
			query:    "foo bar baz",
			expected: []types.RepoID{},
		},
		{
			name:     "simple query",
			query:    "test repo_id:123",
			expected: []types.RepoID{123},
		},
		{
			// NOTE: The SQL query will optimize this away, but we might want to fix this
			name:     "duplicate repo IDs includes duplicates",
			query:    "test repo_id:123 repo_id:123",
			expected: []types.RepoID{123, 123},
		},
		{
			name:     "nested query with duplicates",
			query:    "test repo_id:123 OR (repo_id:123 OR repo_id:234) OR (test2 AND repo_id:12)",
			expected: []types.RepoID{123, 123, 234, 12},
		},
		{
			name:     "nested query with duplicates",
			query:    "test repo_id:123 OR (repo_id:123 OR repo_id:234) OR (test2 AND repo_id:12)",
			expected: []types.RepoID{123, 123, 234, 12},
		},
		{
			name:     "globally scoped query",
			query:    "repo_id:123 OR language:python",
			expected: []types.RepoID{},
		},
		{
			name:     "global query with accessible repos added",
			query:    "user_query AND (repo_id:123 OR repo_id:234 OR trait:public)",
			expected: []types.RepoID{},
		},
		{
			name:     "query with NOT",
			query:    "NOT repo_id:123",
			expected: []types.RepoID{},
		},
		{
			name:     "query with NOT and another repo",
			query:    "repo_id:234 AND NOT repo_id:123",
			expected: []types.RepoID{234},
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			parsed, _ := ParseQuery(context.Background(), test.query)
			require.ElementsMatch(t, test.expected, GetScopeRepoIDs(parsed))
		})
	}
}

func TestTrickyQuery(t *testing.T) {
	expectParse(
		t,
		"repo_id:15 AND (path:/x?z/ OR X)",
		And(RepoID(15), Group(Or(
			MakeQualifier(PathQualifier, Regex("x?z")),
			Text("X"),
		))),
	)

	expectParse(
		t,
		"(a) AND (b) AND /xyz/",
		And(
			Group(Text("a")),
			Group(Text("b")),
			Regex("xyz"),
		),
	)

	expectParse(
		t,
		"/(?i)^(thm{.*}|tryhackme{.*})",
		Text("/(?i)^(thm{.*}|tryhackme{.*})"),
	)
}

func TestSpuriousParens(t *testing.T) {
	expectParse(t,
		"my_function(a, b, c) OR Z",
		Or(Text("my_function(a, b, c)"), Text("Z")),
	)
	expectParse(t,
		"UnitConverter::OnValueKeyDown( repo_id:5",
		And(Text("UnitConverter::OnValueKeyDown("), RepoID(5)),
	)
}

func TestMoreParens(t *testing.T) {
	expectParse(t,
		"( hello )",
		Group(Text("hello")),
	)
	expectParse(t,
		"( lang:python OR lang:C++ )",
		Group(Or(Language("python"), Language("C++"))),
	)
}

func TestNegation(t *testing.T) {
	expectParse(t, "-fstack-protector-string", Text("-fstack-protector-string"))
	expectParse(t, "yum -y install git", And(Text("yum"), Text("-y"), Text("install"), Text("git")))
}

func TestWeirdOther(t *testing.T) {
	expectParse(t, "/a(a)/", Regex("a(a)"))
	expectParse(t, "path:/a(b)/", MakeQualifier(PathQualifier, Regex("a(b)")))
	expectParse(
		t,
		"handleChange: () => {} repo_id:4",
		And(
			Text("handleChange:"),
			Text("()"),
			Text("=>"),
			Text("{}"),
			RepoID(4),
		),
	)
	expectParse(
		t,
		"Router.currentPath () |> parseUrl",
		And(
			Text("Router.currentPath"),
			Text("()"),
			Text("|>"),
			Text("parseUrl"),
		),
	)
	expectParse(t, `"`, Text(`"`))
	expectParse(t, "foo // bar", And(Text("foo"), Text("//"), Text("bar")))
	expectParse(t, "foo //\" bar", And(Text("foo"), Text("//\""), Text("bar")))
	expectParse(t, "foo //bar", And(Text("foo"), Text("//bar")))
	expectParse(t, `foo "" bar`, And(Text("foo"), Text(""), Text("bar")))
	expectParse(t, "\"===UserScript===\"超星尔雅学习通网课助手", Text("\"===UserScript===\"超星尔雅学习通网课助手"))
	expectParse(
		t,
		"size:0 discord bot size:<0.01",
		And(Text("size:0"), Text("discord"), Text("bot"), Text("size:<0.01")),
	)
}

func TestUnbalancedParens(t *testing.T) {
	expectParse(t, "(a", Text("(a"))
	expectParse(t, "(/a)/", Text("(/a)/"))
	expectParse(t, "(/a)/", Text("(/a)/"))
	expectParse(t, "(X AND Y ", And(Text("(X"), Text("Y")))
}

func TestOperatorPrecedence(t *testing.T) {
	expectParse(t, "X AND Y OR Z", Or(And(Text("X"), Text("Y")), Text("Z")))
	expectParse(t, "X OR Y AND Z", Or(Text("X"), And(Text("Y"), Text("Z"))))

	expectParse(t, "X AND (Y OR Z)", And(Text("X"), Group(Or(Text("Y"), Text("Z")))))
	expectParse(t, "(X AND Y) OR Z", Or(Group(And(Text("X"), Text("Y"))), Text("Z")))
}

func TestPathRegex(t *testing.T) {
	expectParse(t, `path:/^crates\/query\/src/ zoekt`, And(MakeQualifier(PathQualifier, Regex("^crates/query/src")), Text("zoekt")))
}

func expectRange(t *testing.T, input string, expected string, query *Query) {
	t.Helper()
	indicator := strings.Repeat(" ", int(query.Start)) + strings.Repeat("^", int(query.End-query.Start))
	require.Equal(t, fmt.Sprintf("%s\n%s", input, expected), fmt.Sprintf("%s\n%s", input, indicator))
}

func Test_ComplexOrAndSequence(t *testing.T) {
	expectParse(t, "(a OR (b) OR y)",
		Group(
			Or(
				Text("a"),
				Group(Text("b")),
				Text("y"),
			),
		),
	)
	expectParse(t, "(a AND (b) AND y)",
		Group(
			And(
				Text("a"),
				Group(Text("b")),
				Text("y"),
			),
		),
	)

	expectParse(t, "(a AND (b) OR y)",
		Group(
			Or(
				And(
					Text("a"),
					Group(Text("b")),
				),
				Text("y"),
			),
		),
	)
}

func TestLanguageOrgRepoQualifiers(t *testing.T) {
	expectParse(t,
		"Y OR language:python OR Z",
		Or(Text("Y"), Language("python"), Text("Z")),
	)
	expectParse(t,
		"Y OR repo:github/github OR Z",
		Or(Text("Y"), Repo("github/github"), Text("Z")),
	)
	expectParse(t,
		"Y OR org:github OR Z",
		Or(Text("Y"), Owner("github"), Text("Z")),
	)
	expectParse(t,
		"Y OR owner:tpope OR Z",
		Or(Text("Y"), Owner("tpope"), Text("Z")),
	)
}

func TestWeirdRange(t *testing.T) {
	// Query contains unicode. The start/end positions should be in bytes
	query := "、Driver"
	parsed, err := ParseQuery(context.Background(), query)
	require.NoError(t, err)
	require.Equal(t, uint32(0), parsed.Start)
	require.Equal(t, uint32(9), parsed.End)
}

func TestRepoParsing(t *testing.T) {
	expectParse(t, "repo:/asdf.*/", MakeQualifier(RepoQualifier, Regex("asdf.*")))
}

func TestCorrectRangeExtraction(t *testing.T) {
	parsed, err := ParseQuery(context.Background(), "hello world")
	require.Equal(t, nil, err)

	expectRange(
		t,
		"hello world",
		"^^^^^",
		parsed.Subqueries[0],
	)

	expectRange(
		t,
		"hello world",
		"      ^^^^^",
		parsed.Subqueries[1],
	)

	expectRange(
		t,
		"hello world",
		"^^^^^^^^^^^",
		parsed,
	)
}

func TestCorrectRangeExtractionWithSubqueries(t *testing.T) {
	parsed, err := ParseQuery(context.Background(), "hello (world OR earth)")
	require.Equal(t, nil, err)

	expectRange(
		t,
		"hello (world OR earth)",
		"      ^^^^^^^^^^^^^^^^",
		parsed.Subqueries[1],
	)

	expectRange(
		t,
		"hello (world OR earth)",
		"       ^^^^^^^^^^^^^^",
		parsed.Subqueries[1].Subqueries[0],
	)

	expectRange(
		t,
		"hello (world OR earth)",
		"                ^^^^^",
		parsed.Subqueries[1].Subqueries[0].Subqueries[1],
	)
}

func TestRangeExtractionJoinedAnd(t *testing.T) {
	parsed, err := ParseQuery(context.Background(), "X AND Y AND Z")
	require.Equal(t, nil, err)

	expectRange(
		t,
		"X AND Y AND Z",
		"^^^^^^^^^^^^^",
		parsed,
	)

	expectRange(
		t,
		"X AND Y AND Z",
		"^",
		parsed.Subqueries[0],
	)
}

func TestRangeExtractionSubExpressionJoinedAnd(t *testing.T) {
	parsed, err := ParseQuery(context.Background(), "(X AND Y) AND (Z and ZZ)")
	require.Equal(t, nil, err)

	expectRange(
		t,
		"(X AND Y) AND (Z AND ZZ)",
		"^^^^^^^^^^^^^^^^^^^^^^^^",
		parsed,
	)

	expectRange(
		t,
		"(X AND Y) AND (Z AND ZZ)",
		"^^^^^^^^^",
		parsed.Subqueries[0],
	)

	expectRange(
		t,
		"(X AND Y) AND (Z AND ZZ)",
		"               ^",
		parsed.Subqueries[1].Subqueries[0].Subqueries[0],
	)
}

func TestRangeExtractionRegex(t *testing.T) {
	parsed, err := ParseQuery(context.Background(), `/regex$/ "quoted string"`)
	require.Equal(t, nil, err)

	expectRange(
		t,
		`/regex$/ "quoted string"`,
		"^^^^^^^^^^^^^^^^^^^^^^^^",
		parsed,
	)

	expectRange(
		t,
		`/regex$/ "quoted string"`,
		"^^^^^^^^",
		parsed.Subqueries[0],
	)

	expectRange(
		t,
		`/regex$/ "quoted string"`,
		"         ^^^^^^^^^^^^^^^",
		parsed.Subqueries[1],
	)
}

func TestRangeExtractionQualifiers(t *testing.T) {
	parsed, err := ParseQuery(context.Background(), `repo_id:5 org_id:6 path:/xyz/`)
	require.Equal(t, nil, err)

	expectRange(
		t,
		`repo_id:5 org_id:6 path:/xyz/`,
		"^^^^^^^^^^^^^^^^^^^^^^^^^^^^^",
		parsed,
	)

	expectRange(
		t,
		`repo_id:5 org_id:6 path:/xyz/`,
		"^^^^^^^^^",
		parsed.Subqueries[0],
	)

	expectRange(
		t,
		`repo_id:5 org_id:6 path:/xyz/`,
		"          ^^^^^^^^",
		parsed.Subqueries[1],
	)

	expectRange(
		t,
		`repo_id:5 org_id:6 path:/xyz/`,
		"                   ^^^^^^^^^^",
		parsed.Subqueries[2],
	)
}

func TestRangeExtractionExcessWhitespace(t *testing.T) {
	parsed, err := ParseQuery(context.Background(), "    Weird     Query     I    Made     ")
	require.Equal(t, nil, err)

	expectRange(
		t,
		"    Weird     Query     I    Made     ",
		"    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^",
		parsed,
	)

	expectRange(
		t,
		"    Weird     Query     I    Made     ",
		"              ^^^^^",
		parsed.Subqueries[1],
	)
}

func TestRangeNestedSubqueries(t *testing.T) {
	parsed, err := ParseQuery(context.Background(), "(query (subquery))")
	require.Equal(t, nil, err)

	expectRange(
		t,
		"(query (subquery))",
		"^^^^^^^^^^^^^^^^^^",
		parsed,
	)

	expectRange(
		t,
		"(query (subquery))",
		" ^^^^^",
		parsed.Subqueries[0].Subqueries[0],
	)

	expectRange(
		t,
		"(query (subquery))",
		"       ^^^^^^^^^^",
		parsed.Subqueries[0].Subqueries[1],
	)

	expectRange(
		t,
		"(query (subquery))",
		"        ^^^^^^^^",
		parsed.Subqueries[0].Subqueries[1].Subqueries[0],
	)
}

func TestRangeUnterminatedParentheses(t *testing.T) {
	expectParse(
		t,
		"(abc)) subquery(",
		And(Group(Text("abc")), Text(")"), Text("subquery(")),
	)

	parsed, err := ParseQuery(context.Background(), "(abc)) subquery(")
	require.Equal(t, nil, err)

	expectRange(
		t,
		"(abc)) subquery(",
		" ^^^",
		parsed.Subqueries[0].Subqueries[0],
	)

	expectParse(
		t,
		"(abc() subquery(",
		And(Group(Text("abc(")), Text("subquery(")),
	)

	parsed, err = ParseQuery(context.Background(), "(abc() subquery(")
	require.Equal(t, nil, err)

	expectRange(
		t,
		"(abc)) subquery(",
		" ^^^^",
		parsed.Subqueries[0].Subqueries[0],
	)
}

func TestRangeOperatorPrecedence(t *testing.T) {
	parsed, err := ParseQuery(context.Background(), "X AND Y OR Z")
	require.Equal(t, nil, err)

	expectRange(
		t,
		"X AND Y OR Z",
		"^^^^^^^^^^^^",
		parsed,
	)

	expectRange(
		t,
		"X AND Y OR Z",
		"^^^^^^^",
		parsed.Subqueries[0],
	)

	expectRange(
		t,
		"X AND Y OR Z",
		"           ^",
		parsed.Subqueries[1],
	)

	expectRange(
		t,
		"X AND Y OR Z",
		"      ^",
		parsed.Subqueries[0].Subqueries[1],
	)
}

func TestRangeLanguageOrgRepoQualifiers(t *testing.T) {
	parsed, err := ParseQuery(context.Background(), "Y OR language:python OR Z")
	require.Equal(t, nil, err)
	expectRange(t,
		"Y OR language:python OR Z",
		"     ^^^^^^^^^^^^^^^",
		parsed.Subqueries[1],
	)

	parsed, err = ParseQuery(context.Background(), "Y OR org:python OR Z")
	require.Equal(t, nil, err)
	expectRange(t,
		"Y OR org:python OR Z",
		"     ^^^^^^^^^^",
		parsed.Subqueries[1],
	)

	parsed, err = ParseQuery(context.Background(), "Y OR repo:github/github OR Z")
	require.Equal(t, nil, err)
	expectRange(t,
		"Y OR repo:github/github OR Z",
		"     ^^^^^^^^^^^^^^^^^^",
		parsed.Subqueries[1],
	)

	parsed, err = ParseQuery(context.Background(), "Y OR owner:colinwm OR testing")
	require.Equal(t, nil, err)
	expectRange(
		t,
		`Y OR owner:colinwm OR testing`,
		"     ^^^^^^^^^^^^^",
		parsed.Subqueries[1],
	)

	parsed, err = ParseQuery(context.Background(), "Y OR NOT owner:colinwm")
	require.Equal(t, nil, err)
	expectRange(
		t,
		`Y OR NOT owner:colinwm`,
		"     ^^^^^^^^^^^^^^^^^",
		parsed.Subqueries[1],
	)

	parsed, err = ParseQuery(context.Background(), "Y OR -owner:colinwm")
	require.Equal(t, nil, err)
	expectRange(
		t,
		`Y OR -owner:colinwm`,
		"     ^^^^^^^^^^^^^^",
		parsed.Subqueries[1],
	)
}

func TestScopeTextToPathDomain(t *testing.T) {
	query := And(MakeQualifier(PathQualifier, Text("already_path")), Text("asdf"), Text("zoekt"))

	// Map text queries into path queries, so that we don't search content when providing suggestions
	RewriteQueryForSuggestions(query)

	expected := And(
		MakeQualifier(PathQualifier, Text("already_path")),
		Or(
			MakeQualifier(PathQualifier, Text("asdf")),
			MakeQualifier(SymbolQualifier, Text("asdf")),
		),
		Or(
			MakeQualifier(PathQualifier, Text("zoekt")),
			MakeQualifier(SymbolQualifier, Text("zoekt")),
		),
	)

	require.Equal(t, Serialize(query), Serialize(expected))
}

func TestIsGloballyScoped(t *testing.T) {
	require.False(t, IsScoped(And(Text("a"), Text("b"))))
	require.True(t, IsScoped(And(RepoID(123), Text("b"))))
	require.True(t, IsScoped(Or(RepoID(123), RepoID(345))))
	require.False(t, IsScoped(Or(Text("abc"), RepoID(345))))
	require.True(t, IsScoped(Or(OwnerID(456), RepoID(345))))
}

func TestPathGlobs(t *testing.T) {
	expectParse(t,
		`path:*.js`,
		MakeQualifier(PathQualifier, Regex(`(^|/)[^/]*\.js$`)),
	)

	expectParse(t,
		`path:e?e`,
		MakeQualifier(PathQualifier, Regex(`(^|/)e.e$`)),
	)

	// ? within regex should not be treated as a glob
	expectParse(t,
		`path:/jsx?/`,
		MakeQualifier(PathQualifier, Regex(`jsx?`)),
	)
}

func TestRepoGlobs(t *testing.T) {
	expectParse(t,
		`repo:*-js`,
		MakeQualifier(RepoQualifier, Regex(`(^|/)[^/]*-js$`)),
	)

	// Quoting a glob-like value should mean it's not a glob
	expectParse(t,
		`repo:"*-js"`,
		MakeQualifier(RepoQualifier, Text("*-js")),
	)
}

func TestScopeQualifier(t *testing.T) {
	expectParse(t,
		`scope:@username`,
		MakeQualifier(ScopeQualifier, Text("@username")),
	)
	expectParse(t,
		`scope:special-name`,
		MakeQualifier(ScopeQualifier, Text("special-name")),
	)
	expectParse(t,
		`scope:"quoted scope name"`,
		MakeQualifier(ScopeQualifier, Text("quoted scope name")),
	)
	expectParse(t,
		`scope:orgname/reponame`,
		MakeQualifier(ScopeQualifier, Text("orgname/reponame")),
	)
	expectParse(t,
		`saved:abcdef`,
		MakeQualifier(ScopeQualifier, Text("abcdef")),
	)
}

func expectBounds(t *testing.T, condition string, lower, upper uint32) {
	actualLower, actualUpper, err := parseSizeQuery(condition)
	require.NoError(t, err)
	require.Equal(t, lower, actualLower)
	require.Equal(t, upper, actualUpper)
}

func TestFilesizeQualifier(t *testing.T) {
	expectBounds(t, ">1200", 1201, NoUpperBound)
	expectBounds(t, ">=1200", 1200, NoUpperBound)
	expectBounds(t, "1200..*", 1200, NoUpperBound)
	expectBounds(t, "<1200", NoLowerBound, 1200)
	expectBounds(t, "*..1200", NoLowerBound, 1201)
	expectBounds(t, "1000..1200", 1000, 1201)
}

func TestPromptQualifier(t *testing.T) {
	// Query is interpreted as regular text when experiment is not enabled.
	expectParseWithCtx(context.Background(), t,
		`prompt:"some prompt"`,
		Text(`prompt:"some prompt"`),
	)

	ctx := experiments.WithExperiment(context.Background(), experiments.PromptQualifier, experiments.Enabled)
	expectParseWithCtx(ctx, t,
		`prompt:"prompt with angle"@15`,
		Prompt("prompt with angle", 15),
	)
	// Test with a huge angle that we cannot fit should result in a default angle
	expectParseWithCtx(ctx, t,
		`prompt:"prompt with angle"@10000000000000000000`,
		Prompt("prompt with angle", UnspecifiedAngle),
	)

	expectParseWithCtx(ctx, t,
		`prompt:"some prompt"`,
		Prompt("some prompt", UnspecifiedAngle),
	)

	expectParseWithCtx(ctx, t,
		`prompt:"some prompt" repo:github/github`,
		And(Prompt("some prompt", UnspecifiedAngle), Repo("github/github")),
	)

	expectParseWithCtx(ctx, t,
		`prompt:"a prompt" other text`,
		And(Prompt("a prompt", UnspecifiedAngle), Text("other"), Text("text")),
	)
	expectParseWithCtx(ctx, t,
		`prompt:"a prompt"@blah`,
		And(Text(`prompt:"a`), Text(`prompt"@blah`)),
	)

	expectParseWithCtx(ctx, t,
		`prompt:"\"some escaped text\"" other text`,
		And(Prompt(`"some escaped text"`, UnspecifiedAngle), Text("other"), Text("text")),
	)

}

func TestRefQualifier(t *testing.T) {
	// Query is interpreted as text when experiment is not enabled.
	expectParseWithCtx(context.Background(), t,
		`ref:foo`,
		Text(`ref:foo`),
	)

	ctx := experiments.WithExperimentEnabled(context.Background(), experiments.RefQualifier)
	expectParseWithCtx(ctx, t, "(ref:abcd AND ref:defg)", Group(And(SymbolRef(Text("abcd")), SymbolRef(Text("defg")))))
	expectParseWithCtx(ctx, t, "ref:\"abcd defg\"", SymbolRef(Text("abcd defg")))
	expectParseWithCtx(ctx, t, "-ref:\"abcd defg\"", Not(SymbolRef(Text("abcd defg"))))
	expectParseWithCtx(ctx, t, "NOT -ref:\"abcd defg\"", Not(Not(SymbolRef(Text("abcd defg")))))
	expectParseWithCtx(ctx, t, "ref:QueryStream::new", SymbolRef(Text("QueryStream::new")))
}

func TestBM25Qualifier(t *testing.T) {
	// Query is interpreted as text when experiment is not enabled.
	expectParseWithCtx(context.Background(), t,
		`bm25:hello`,
		Text(`bm25:hello`),
	)

	ctx := experiments.WithExperimentEnabled(context.Background(), experiments.BM25Qualifier)
	expectParseWithCtx(ctx, t, "bm25:hello", BM25("hello"))
	expectParseWithCtx(ctx, t, `bm25:"hello world"`, BM25("hello world"))
}
