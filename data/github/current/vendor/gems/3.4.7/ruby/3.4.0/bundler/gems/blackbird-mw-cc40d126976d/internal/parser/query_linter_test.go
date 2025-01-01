package parser

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"

	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func renderErrors(original string, errors []*QueryError) string {
	if len(errors) == 0 {
		return ""
	}

	rendered := "\n"
	for _, err := range errors {
		indicated := ""

		position := uint32(0)
		for _, ind := range err.Ranges {
			indicated += strings.Repeat(" ", int(ind.Start-position)) + strings.Repeat("^", int(ind.End-ind.Start))
			position = ind.End
		}

		start := 0
		if len(err.Ranges) > 0 {
			start = int(err.Ranges[0].Start)
		}
		message := strings.Repeat(" ", start) + err.Message

		kind := "WARNING"
		if err.Type == ErrorTypeParsingFatal {
			kind = "FATAL"
		}

		rendered += fmt.Sprintf("%s:\n   %s\n   %s\n   %s\n", kind, original, indicated, message)

		if err.Suggestion != "" {
			rendered += fmt.Sprintf("\nsuggestion:\n   %s\n", err.Suggestion)
		}
	}
	return rendered
}

func expectWarn(t *testing.T, input string, warning string) {
	t.Run(input, func(t *testing.T) {
		parsed, err := ParseQuery(context.Background(), input)
		require.Equal(t, nil, err)

		errors, _ := LintQuery(context.Background(), input, parsed, parsed)
		require.Equal(t, warning, renderErrors(input, errors))
	})
}

func expectWarnWithRewrites(t *testing.T, input string, warning string, exps ...string) {
	t.Run(input, func(t *testing.T) {
		ctx := experiments.WithExperimentsEnabled(context.Background(), exps)

		actor := actorWithAccess(nil)

		parsed, err := ParseQuery(ctx, input)
		require.Equal(t, nil, err)

		repos := []*snapshotpb.SnapshotEntry{
			{
				Nwo:          "rails/rails",
				RepoId:       2,
				OwnerId:      200,
				IsRepoPublic: true,
				Experiments: map[string]string{
					experiments.EnableCodeEmbedding: "1",
				},
			},
			{
				Nwo:          "github/github",
				RepoId:       1,
				OwnerId:      100,
				IsRepoPublic: true,
			},
			{
				Nwo:          "github/blackbird",
				RepoId:       3,
				OwnerId:      100,
				IsRepoPublic: true,
				Experiments: map[string]string{
					experiments.EnableCodeEmbedding: "1",
				},
			},
		}
		index := helpers.SearchIndexWithSnapshots(t, repos...)

		copilot := helpers.CopilotClient(t)
		fakeEmbedding := []float32{0.1234, 0.24321, 0.2221}
		copilot.GetEmbeddingReturns(fakeEmbedding, nil)
		promptRewriter := NewEmbeddingsRewriter(copilot, routing.Text3SmallInference, 512)

		rewriteErrors, _, err := RewriteQuery(ctx, parsed, actor, nil /* tenant */, index, nil, promptRewriter)
		require.NoError(t, err)

		errors, _ := LintQuery(ctx, input, parsed, parsed)
		errors = append(errors, rewriteErrors...)

		require.Equal(t, warning, renderErrors(input, errors))
	})
}

func TestBooleanOperatorWarning(t *testing.T) {
	expectWarn(t,
		"x and y",
		`
WARNING:
   x and y
     ^^^
     Possible boolean operator used as a search term

suggestion:
   x AND y
`,
	)

	expectWarn(t,
		"x not y",
		`
WARNING:
   x not y
     ^^^
     Possible boolean operator used as a search term

suggestion:
   x NOT y
`,
	)

	expectWarn(t,
		`x "not" y`,
		"",
	)

	expectWarn(t,
		"A AND (B or C)",
		`
WARNING:
   A AND (B or C)
            ^^
            Possible boolean operator used as a search term

suggestion:
   A AND (B OR C)
`,
	)

	expectWarn(t,
		`x "not" y`,
		"",
	)
}

func TestInvalidRegularExpression(t *testing.T) {
	expectWarn(t,
		"/[/",
		`
FATAL:
   /[/
   ^^^
   Invalid regular expression
`,
	)

	expectWarn(t,
		"/*/",
		`
FATAL:
   /*/
   ^^^
   Invalid regular expression
`,
	)
}

func TestUnrecognizedQualifier(t *testing.T) {
	expectWarn(t,
		"X OR qualifier:6",
		`
WARNING:
   X OR qualifier:6
        ^^^^^^^^^^^
        Possible unrecognized qualifier, searching for this term literally
`,
	)

	// Since the qualifier is quoted, no warning is required
	expectWarn(t,
		`X OR "qualifier:6"`,
		``,
	)

	// This has two colons so it isn't an unrecognized qualifiers
	expectWarn(t,
		`QueryStream::new`,
		``,
	)

	// This ends in a colon, also no warning needed
	expectWarn(t,
		`QueryStream:`,
		``,
	)

	// This starts in a colon, also no warning needed
	expectWarn(t,
		`:initialize"`,
		``,
	)

	// This is quoted so it should not warn
	expectWarn(t,
		`"(a:b)"`,
		``,
	)

	// This is a URL, should have no warning
	expectWarn(t,
		`https://github.com/code-search`,
		``,
	)
}

func TestUnknownLanguage(t *testing.T) {
	expectWarnWithRewrites(t,
		"X OR lang:magic OR Y",
		`
FATAL:
   X OR lang:magic OR Y
        ^^^^^^^^^^
        Unknown language: "magic"
`,
	)
}

func TestEmbeddingsUnavailable(t *testing.T) {
	// github/github does not have embeddings
	expectWarnWithRewrites(t,
		`repo:github/github prompt:"asdf"`,
		`
WARNING:
   repo:github/github prompt:"asdf"
   ^^^^^^^^^^^^^^^^^^
   Embeddings unavailable for github/github
`,
		experiments.PromptQualifier,
	)

	// Rails repo has code embeddings
	expectWarnWithRewrites(t,
		`repo:rails/rails prompt:"asdf"`,
		``,
		experiments.PromptQualifier,
	)
}

func TestSatisfiability(t *testing.T) {
	expectWarn(t,
		"(language_id:3 AND language_id:4) AND Z",
		`
FATAL:
   (language_id:3 AND language_id:4) AND Z
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    condition is unsatisfiable
`,
	)

	// Same language ID in both branches is fine
	expectWarn(t,
		"language_id:3 AND language_id:3",
		"",
	)

	// RepoID and OrgID conditions in an OR should be fine
	expectWarn(t,
		"repo_id:3 OR org_id:3",
		"",
	)

	// Additional OR condition means it is satisfiable
	expectWarn(t,
		"language_id:3 AND language_id:4 OR Z",
		`
WARNING:
   language_id:3 AND language_id:4 OR Z
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   condition is unsatisfiable
`)

	// Complex case: Unsatisfiable OR condition
	expectWarn(t,
		"(language_id:3 OR language_id:3) AND (language_id:5 AND path:txt)",
		`
FATAL:
   (language_id:3 OR language_id:3) AND (language_id:5 AND path:txt)
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   condition is unsatisfiable
`,
	)

	// Complex case: Satisfiable OR condition
	expectWarn(t,
		"(language_id:3 OR language_id:5) AND (language_id:5 OR path:txt)",
		"",
	)

	// Complex case: Unsatisfiable OR condition
	expectWarn(t,
		"(language_id:3 OR language_id:4) AND (language_id:5 OR language_id:6)",
		`
FATAL:
   (language_id:3 OR language_id:4) AND (language_id:5 OR language_id:6)
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   condition is unsatisfiable
`,
	)

	// Complex case: NOT conditions
	expectWarn(t,
		"repo_id:5 AND NOT repo_id:5",
		`
FATAL:
   repo_id:5 AND NOT repo_id:5
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^
   condition is unsatisfiable
`,
	)

	// NOT condition on non-qualifier terms
	expectWarn(t,
		"NOT xyz",
		"",
	)

	// We don't evaluate satisfiability on query terms
	expectWarn(t,
		"xyz AND NOT xyz",
		"",
	)

	// Super complex case, AND, OR and NOT
	expectWarn(t,
		"language_id:5 AND NOT (language_id:5 OR language_id:6)",
		`
FATAL:
   language_id:5 AND NOT (language_id:5 OR language_id:6)
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   condition is unsatisfiable
`,
	)

	// Unclear org and repo overlap is ok
	expectWarn(t,
		"org_id:5 AND repo_id:6",
		"",
	)

	// Known to be unsatisfiable because org/repo don't overlap
	expectWarnWithRewrites(t,
		"org:rails AND repo:github/github",
		`
FATAL:
   org:rails AND repo:github/github
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   condition is unsatisfiable
`,
	)

	// Known to be satisfiable because org/repo do overlap
	expectWarnWithRewrites(t,
		"org:github AND repo:github/github",
		"",
	)

	// Known to be satisfiable even though org/repo do overlap
	expectWarnWithRewrites(t,
		"org:github AND NOT repo:github/github",
		"",
	)

	// Satisfiable, since X may not match all github content
	expectWarnWithRewrites(t,
		"NOT (X AND org:github) AND org:github",
		"",
	)

	// Simple NOT condition
	expectWarnWithRewrites(t,
		"NOT xyz",
		"",
	)

	expectWarnWithRewrites(t,
		"NOT (language_id:5 OR org:github) OR language_id:5",
		"",
	)

	// Unsatisfiable because org is excluded then required
	expectWarnWithRewrites(t,
		"(language_id:5 AND org:github) AND NOT org:github",
		`
FATAL:
   (language_id:5 AND org:github) AND NOT org:github
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   condition is unsatisfiable
`,
	)

	// Though this is trivially unsatisfiable, our algorithm does not
	// consider non-categorical qualifiers
	expectWarn(t,
		"path:X AND NOT path:X",
		"",
	)

	expectWarn(t,
		"NOT (language_id:1 AND language_id:2)",
		`
WARNING:
   NOT (language_id:1 AND language_id:2)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
        condition is unsatisfiable
`)
}

func TestQualifierSuggestions(t *testing.T) {
	expectWarn(t,
		"extension:*.txt AND language:python",
		`
WARNING:
   extension:*.txt AND language:python
   ^^^^^^^^^^^^^^^
   Unrecognized qualifier. Looking for a file extension? Try using the path qualifier

suggestion:
   path:*.txt AND language:python
`,
	)

	expectWarn(t,
		"extension:txt AND language:python",
		`
WARNING:
   extension:txt AND language:python
   ^^^^^^^^^^^^^
   Unrecognized qualifier. Looking for a file extension? Try using the path qualifier

suggestion:
   path:*.txt AND language:python
`,
	)

	expectWarn(t,
		"ZZZ AND file:readme.md AND language:python",
		`
WARNING:
   ZZZ AND file:readme.md AND language:python
           ^^^^^^^^^^^^^^
           Unrecognized qualifier. Looking for a filename? Try using the path qualifier

suggestion:
   ZZZ AND path:**/readme.md AND language:python
`,
	)

	// Don't provide a suggestion if it appears to be a regex
	expectWarn(t,
		"ZZZ AND file:/readme.md$/ AND language:python",
		`
WARNING:
   ZZZ AND file:/readme.md$/ AND language:python
           ^^^^^^^^^^^^^^^^^
           Unrecognized qualifier. Looking for a filename? Try using the path qualifier
`,
	)
}

func TestUnrecognizedIsValue(t *testing.T) {
	expectWarn(t,
		"X is:not-archived",
		`
WARNING:
   X is:not-archived
     ^^^^^^^^^^^^^^^
     Unrecognized is: qualifier value, searching for this term literally
`,
	)
}

func TestRegexDetection(t *testing.T) {
	expectWarn(t,
		"git.*push",
		`
WARNING:
   git.*push
   ^^^^^^^^^
   Searching for this literally, regular expressions must be surrounded by slashes.

suggestion:
   /git.*push/
`,
	)

	expectWarn(t,
		"\\d+",
		`
WARNING:
   \d+
   ^^^
   Searching for this literally, regular expressions must be surrounded by slashes.

suggestion:
   /\d+/
`,
	)

	expectWarn(t,
		"X OR [a-z]+",
		`
WARNING:
   X OR [a-z]+
        ^^^^^^
        Searching for this literally, regular expressions must be surrounded by slashes.

suggestion:
   X OR /[a-z]+/
`,
	)

	expectWarn(t,
		"/(?i)^(thm{.*}|tryhackme{.*})$",
		`
WARNING:
   /(?i)^(thm{.*}|tryhackme{.*})$
   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   Searching for this literally, regular expressions must be surrounded by slashes.

suggestion:
   /(?i)^(thm{.*}|tryhackme{.*})$/
`,
	)
}

func TestNonPrintingCharsWarning(t *testing.T) {
	expectWarn(t,
		"a\u200bbcdef",
		`
WARNING:
   a​bcdef
    ^
    Query contains non-printing unicode characters

suggestion:
   abcdef
`,
	)
}

func TestOverlyPermissiveRegex(t *testing.T) {
	expectWarn(t,
		"/.*/",
		`
FATAL:
   /.*/
   ^^^^
   Regular expression would match all documents
`,
	)

	expectWarn(t,
		`/(\w+ = \w+;\s+)*/`,
		`
FATAL:
   /(\w+ = \w+;\s+)*/
   ^^^^^^^^^^^^^^^^^^
   Regular expression would match all documents
`,
	)
}

func TestSemanticSearchValidation(t *testing.T) {
	expectWarnWithRewrites(t,
		`repo:github/blackbird prompt:"hello world"`,
		"",
		experiments.AllSemanticSearchLints,
		experiments.PromptQualifier,
	)

	expectWarnWithRewrites(t,
		`repo:github/blackbird OR repo:rails/rails prompt:"hello world"`,
		"",
		experiments.AllSemanticSearchLints,
		experiments.PromptQualifier,
	)

	expectWarnWithRewrites(t,
		`org:github OR org:rails prompt:"hello world"`,
		"",
		experiments.AllSemanticSearchLints,
		experiments.PromptQualifier,
	)

	expectWarnWithRewrites(t,
		`repo:github/blackbird prompt:"hello world" lang:Markdown`,
		"",
		experiments.AllSemanticSearchLints,
		experiments.PromptQualifier,
	)

	expectWarnWithRewrites(t,
		`repo:github/blackbird prompt:"hello world" path:README`,
		"",
		experiments.AllSemanticSearchLints,
		experiments.PromptQualifier,
	)

	expectWarnWithRewrites(t,
		`prompt:"hello world"`,
		`
FATAL:
   prompt:"hello world"
   ^^^^^^^^^^^^^^^^^^^^
   Semantic searches must be scoped to an organization or repository
`,
		experiments.AllSemanticSearchLints,
		experiments.PromptQualifier,
	)

	expectWarnWithRewrites(t,
		`repo:rails/rails OR prompt:"hello world"`,
		`
FATAL:
   repo:rails/rails OR prompt:"hello world"
                       ^^^^^^^^^^^^^^^^^^^^
                       Semantic searches must be scoped to an organization or repository
`,
		experiments.AllSemanticSearchLints,
		experiments.PromptQualifier,
	)

	expectWarnWithRewrites(t,
		`NOT org:github prompt:"hello world"`,
		`
FATAL:
   NOT org:github prompt:"hello world"
                  ^^^^^^^^^^^^^^^^^^^^
                  Semantic searches must be scoped to an organization or repository
`,
		experiments.AllSemanticSearchLints,
		experiments.PromptQualifier,
	)

	expectWarnWithRewrites(t,
		`repo:github/blackbird prompt:"hello world" content:README`,
		`
FATAL:
   repo:github/blackbird prompt:"hello world" content:README
                                              ^^^^^^^^^^^^^^
                                              Semantic searches must not include any qualifiers other than repo and owner
`,
		experiments.AllSemanticSearchLints,
		experiments.PromptQualifier,
	)
}
