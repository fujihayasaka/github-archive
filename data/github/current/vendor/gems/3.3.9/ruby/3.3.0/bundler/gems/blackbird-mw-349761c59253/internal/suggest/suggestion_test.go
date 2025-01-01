package suggest

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/parser"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/search/searchfakes"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/types"
)

func testActor() *models.Actor {
	return &models.Actor{ID: 1, AccessiblePrivateRepoIDs: types.RepoIDSet{}}
}

func TestQualifierSuggestLanguage(t *testing.T) {
	input := "(X AND language:py) OR Y"
	parsed, err := parser.ParseQuery(context.Background(), input)
	require.Equal(t, nil, err)

	expected := []Suggestion{
		{
			Kind:  QuerySuggestion,
			Query: "(X AND language:python) OR Y",
		},
	}
	require.Equal(t, expected, Suggest(context.Background(), parsed, input, 0, &searchfakes.FakeIndex{}, testActor()))
}

func TestQualifierSuggestMultipleLanguages(t *testing.T) {
	input := "(X AND language:ru) OR Y"
	parsed, err := parser.ParseQuery(context.Background(), input)
	require.Equal(t, nil, err)

	expected := []Suggestion{
		{
			Kind:  QuerySuggestion,
			Query: "(X AND language:ruby) OR Y",
		},
		{
			Kind:  QuerySuggestion,
			Query: "(X AND language:rust) OR Y",
		},
	}
	require.Equal(t, expected, Suggest(context.Background(), parsed, input, 0, &searchfakes.FakeIndex{}, testActor()))
}

func TestSuggestOwner(t *testing.T) {
	repos := []*db.Repository{
		{
			Name:       "blackbird-test-repo",
			OwnerLogin: "github",
			RepoID:     124,
			OwnerID:    45,
			IsPublic:   true,
		},
		{
			Name:       "blackbird",
			OwnerLogin: "dsp",
			RepoID:     123,
			OwnerID:    456,
			IsPublic:   false,
		},
		{
			Name:       "blackbird-fe",
			OwnerLogin: "github-test",
			RepoID:     456,
			OwnerID:    789,
			IsPublic:   false,
		},
	}

	actor := &models.Actor{ID: 1, AuthorizedOrganizationIDs: []int64{45, 789}}
	index := helpers.SearchIndexWithRepos(t, repos...)

	input := "querystream owner:git"
	parsed, err := parser.ParseQuery(context.Background(), input)
	require.NoError(t, err)

	// need to rewrite
	_, _, err = parser.RewriteQuery(context.Background(), parsed, actor, nil /* tenant */, index, nil, parser.DisallowPromptQueries{})
	require.NoError(t, err)

	require.Equal(t,
		[]Suggestion{
			{
				Kind:  QuerySuggestion,
				Query: "querystream owner:github",
			},
			{
				Kind:  QuerySuggestion,
				Query: "querystream owner:github-test",
			},
		},
		Suggest(context.Background(), parsed, input, 0, index, actor))
}

func TestQualifierSuggestOneWorkingLanguage(t *testing.T) {
	input := "language:python OR language:ru"
	parsed, err := parser.ParseQuery(context.Background(), input)
	require.NoError(t, err)
	ctx := context.Background()
	require.NoError(t, err)

	// Need to rewrite the query, so we can detect that language:python is a valid
	// language while language:ru is not
	_, _, err = parser.RewriteQuery(ctx, parsed, nil, nil /* tenant */, helpers.SearchIndexWithRepos(t), nil, parser.DisallowPromptQueries{})
	require.NoError(t, err)

	errors, _ := parser.LintQuery(context.Background(), input, parsed, parsed)
	parser.ConvertQueryErrorToProto(errors)

	expected := []Suggestion{
		{
			Kind:  QuerySuggestion,
			Query: "language:python OR language:ruby",
		},
		{
			Kind:  QuerySuggestion,
			Query: "language:python OR language:rust",
		},
	}
	require.Equal(t, expected, Suggest(context.Background(), parsed, input, 0, &searchfakes.FakeIndex{}, testActor()))
}

func TestProtobufConversion(t *testing.T) {
	input := []Suggestion{
		{
			Kind:  QuerySuggestion,
			Query: "language:python OR language:ruby",
		},
		{
			Kind:  QuerySuggestion,
			Query: "language:python OR language:rust",
		},
		{
			Kind:          PathSuggestion,
			Path:          "a/b/c.txt",
			RepositoryNWO: "github/github",
			LanguageID:    5,
		},
		{
			Kind:          SymbolSuggestion,
			Path:          "a/b/c.txt",
			RepositoryNWO: "github/github",
			LanguageID:    5,
			LineNumber:    66,
			Symbol: &pb.Symbol{
				FullyQualifiedName: "XYZ::new",
				Kind:               entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF,
			},
		},
	}
	expected := []*pb.Suggestion{
		{
			Query: "language:python OR language:ruby",
			Kind:  pb.SuggestionKind_SUGGESTION_KIND_QUERY,
		},
		{
			Query: "language:python OR language:rust",
			Kind:  pb.SuggestionKind_SUGGESTION_KIND_QUERY,
		},
		{
			Kind:          pb.SuggestionKind_SUGGESTION_KIND_PATH,
			Path:          "a/b/c.txt",
			RepositoryNwo: "github/github",
			LanguageId:    5,
		},
		{
			Kind:          pb.SuggestionKind_SUGGESTION_KIND_SYMBOL,
			Path:          "a/b/c.txt",
			RepositoryNwo: "github/github",
			LanguageId:    5,
			LineNumber:    66,
			Symbol: &pb.Symbol{
				FullyQualifiedName: "XYZ::new",
				Kind:               entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF,
			},
		},
	}
	require.Equal(t, expected, ConvertToProto(input))
}

func TestSuggestionExtraction(t *testing.T) {
	ctx := context.Background()
	oid := helpers.RandomOID(t)
	response := pb.QueryResponse{
		Documents: []*pb.GitDocumentMatch{
			{
				LanguageId: 5,
				Locations: []*pb.Location{{
					Path:      "a/b/c.txt",
					RepoId:    456,
					RepoNwo:   "github/blackbird-fe",
					CommitSha: oid.Bytes(),
				}},
				ScoringInfo: &pb.ScoringInfo{
					Snippets: []*pb.Snippet{{
						StartingLineNumber: uint32(0),
						EndingLineNumber:   uint32(6),
					}},
				},
			},
			{
				LanguageId: 5,
				Content:    []byte("function XYZ() {}"),
				Locations: []*pb.Location{{
					Path:      "x/y/z.txt",
					RepoId:    456,
					RepoNwo:   "github/blackbird-fe",
					CommitSha: oid.Bytes(),
				}},
				ScoringInfo: &pb.ScoringInfo{
					Snippets: []*pb.Snippet{{
						StartingLineNumber: uint32(0),
						EndingLineNumber:   uint32(6),
					}},
					MatchedSymbols: []*pb.Symbol{{
						FullyQualifiedName: "XYZ",
						IdentStart:         11,
						IdentEnd:           14,
						ExtentStart:        18,
						ExtentEnd:          19,
						Kind:               entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF,
					}},
				},
			},
		},
	}

	suggestions := ExtractSuggestionsFromSearch(ctx, &response)

	expected := []Suggestion{
		{
			Kind:          PathSuggestion,
			Path:          "a/b/c.txt",
			RepositoryNWO: "github/blackbird-fe",
			RepositoryID:  456,
			LanguageID:    5,
			CommitSHA:     oid.String(),
			LineNumber:    3,
		},
		{
			Kind:          SymbolSuggestion,
			Path:          "x/y/z.txt",
			RepositoryNWO: "github/blackbird-fe",
			RepositoryID:  456,
			LanguageID:    5,
			CommitSHA:     oid.String(),
			LineNumber:    1,
			Symbol: &pb.Symbol{
				FullyQualifiedName: "XYZ",
				Kind:               entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF,
				IdentStart:         11,
				IdentEnd:           14,
				ExtentStart:        18,
				ExtentEnd:          19,
			},
		},
	}
	require.Equal(t, expected, suggestions)
}

func TestWeirdQuerySuggestions(t *testing.T) {
	input := "、Driver.*? SQL[-_ ]*Server"
	parsed, err := parser.ParseQuery(context.Background(), input)
	require.Equal(t, nil, err)
	ctx := context.Background()
	_, _, err = parser.RewriteQuery(ctx, parsed, nil, nil /* tenant */, &searchfakes.FakeIndex{}, nil, parser.DisallowPromptQueries{})
	require.NoError(t, err)

	errors, _ := parser.LintQuery(context.Background(), input, parsed, parsed)
	parser.ConvertQueryErrorToProto(errors)

	expected := []*parser.QueryError{
		{
			Message:    "Searching for this literally, regular expressions must be surrounded by slashes.",
			Suggestion: "/、Driver.*?/ SQL[-_ ]*Server",
			Ranges: []parser.Range{
				{
					Start: 0,
					End:   12,
				},
			},
			Type: parser.ErrorTypeParsingWarning,
		},
	}
	require.Equal(t, expected, errors)
}

func TestSuggestRerankingSimple(t *testing.T) {
	beforeRanking := []Suggestion{
		{
			Kind:  QuerySuggestion,
			Query: "a b c d",
		},
		{
			Kind:  QuerySuggestion,
			Query: "b c d e",
		},
		{
			Kind:  QuerySuggestion,
			Query: "c d e f",
		},
		{
			Kind:  QuerySuggestion,
			Query: "d e f g",
		},
		{
			Kind: PathSuggestion,
			Path: "docs/README.md",
		},
	}

	expected := []Suggestion{
		{
			Kind:  QuerySuggestion,
			Query: "a b c d",
		},
		{
			Kind: PathSuggestion,
			Path: "docs/README.md",
		},
	}

	out := RerankSuggestions(beforeRanking, 2)
	require.Equal(t, expected, out)
}

func TestSuggestRerankingNoSuggestions(t *testing.T) {
	beforeRanking := []Suggestion{}
	expected := []Suggestion{}

	out := RerankSuggestions(beforeRanking, 4)
	require.Equal(t, expected, out)
}

func TestSuggestReranking(t *testing.T) {
	beforeRanking := []Suggestion{
		{
			Kind:  QuerySuggestion,
			Query: "a b c d",
		},
		{
			Kind:  QuerySuggestion,
			Query: "b c d e",
		},
		{
			Kind:  QuerySuggestion,
			Query: "c d e f",
		},
		{
			Kind:  QuerySuggestion,
			Query: "d e f g",
		},
		{
			Kind: PathSuggestion,
			Path: "docs/README.md",
		},
	}

	// The result should retain the ordering of the input, but
	// drop things to meet the limit.
	expected := []Suggestion{
		{
			Kind:  QuerySuggestion,
			Query: "a b c d",
		},
		{
			Kind:  QuerySuggestion,
			Query: "b c d e",
		},
		{
			Kind: PathSuggestion,
			Path: "docs/README.md",
		},
	}

	out := RerankSuggestions(beforeRanking, 3)
	require.Equal(t, expected, out)
}
