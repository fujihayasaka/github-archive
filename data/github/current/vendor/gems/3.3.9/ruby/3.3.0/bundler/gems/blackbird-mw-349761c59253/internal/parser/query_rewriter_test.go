package parser

import (
	"context"
	"errors"
	"fmt"
	"log"
	"testing"

	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/constants"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/models"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_SimplyNotNothing(t *testing.T) {
	query := Not(Nothing())
	SimplifyQuery(query)
	require.Equal(t, Serialize(Everything()), Serialize(query))
}

func Test_SimplyNotEverything(t *testing.T) {
	query := Not(Everything())
	SimplifyQuery(query)
	require.Equal(t, Serialize(Nothing()), Serialize(query))
}

func Test_SimplifyDiveristyAndText(t *testing.T) {
	query := And(Text("a"), Text("b"))
	query.DivorToScore = 10
	query.DivorToRetrieve = 2 * 10
	SimplifyQuery(query)
	require.Equal(t, Serialize(And(Text("a"), Text("b"))), Serialize(query))
}

func Test_SimplyAndNothing(t *testing.T) {
	query := And(Nothing(), RepoID(1))
	SimplifyQuery(query)
	require.Equal(t, Serialize(Nothing()), Serialize(query))
}

func Test_SimplyAndEverything(t *testing.T) {
	query := And(Everything(), RepoID(1))
	SimplifyQuery(query)
	require.Equal(t, Serialize(RepoID(1)), Serialize(query))
}

func Test_SimplyAndEverything2(t *testing.T) {
	query := And(Everything(), RepoID(1), RepoID(2))
	SimplifyQuery(query)
	require.Equal(t, Serialize(And(RepoID(1), RepoID(2))), Serialize(query))
}

func Test_SimplyAndJustEverything(t *testing.T) {
	query := And(Everything())
	SimplifyQuery(query)
	require.Equal(t, Serialize(Everything()), Serialize(query))
}

func Test_SimplyEmptyOrIsNothing(t *testing.T) {
	query := Or()
	SimplifyQuery(query)
	require.Equal(t, Serialize(Nothing()), Serialize(query))
}

func Test_SimplyOrNothing(t *testing.T) {
	query := Or(Nothing(), RepoID(1))
	SimplifyQuery(query)
	require.Equal(t, Serialize(RepoID(1)), Serialize(query))
}

func Test_SimplyOrEverything(t *testing.T) {
	query := Or(Everything(), RepoID(1))
	SimplifyQuery(query)
	require.Equal(t, Serialize(Everything()), Serialize(query))
}

func Test_SimplyOrEverything2(t *testing.T) {
	query := Or(Everything(), RepoID(1), RepoID(2))
	SimplifyQuery(query)
	require.Equal(t, Serialize(Everything()), Serialize(query))
}

func Test_SimplyOrNothing2(t *testing.T) {
	query := Or(Nothing(), RepoID(1), RepoID(2))
	SimplifyQuery(query)
	require.Equal(t, Serialize(RepoID(1, 2)), Serialize(query))
}

func Test_SimplifyNestedAnd(t *testing.T) {
	query := And(And(RepoID(1), RepoID(2)), RepoID(3))
	SimplifyQuery(query)
	require.Equal(t, Serialize(And(RepoID(1), RepoID(2), RepoID(3))), Serialize(query))
}

func Test_SimplifyComplexOr(t *testing.T) {
	// The language IDs, owner IDs, and repo IDs should be merged together
	query := Or(LanguageID(1), OwnerID(2), RepoID(3), LanguageID(4), RepoID(5), OwnerID(6))
	SimplifyQuery(query)
	require.Equal(t, Serialize(Or(LanguageID(1, 4), OwnerID(2, 6), RepoID(3, 5))), Serialize(query))
}

func Test_AccessiblePrivateRepo(t *testing.T) {
	repos := []*db.Repository{privateRepo(1)}
	query, _ := rewriteQuery(t, "repo_id:1 hello world", actorWithAccess(repos), repos...)
	expected := Serialize(
		And(
			RepoID(1),
			Text("hello"),
			Text("world"),
			DefaultBranch(),
		),
	)
	require.Equal(t, expected, Serialize(query))

	query, _ = rewriteQuery(t, "repo_id:1 OR world", actorWithAccess(repos), repos...)
	expected = Serialize(
		And(
			Or(
				RepoID(1),
				Text("world"),
			),
			DefaultBranch(),
			Or(
				RepoID(1),
				PublicRepo(),
			),
		),
	)
	require.Equal(t, expected, Serialize(query))

	repos = []*db.Repository{privateRepo(1), privateRepo(2)}
	query, _ = rewriteQuery(t, "repo_id:1 OR repo_id:2", actorWithAccess(repos), repos...)
	expected = Serialize(
		And(
			RepoID(1, 2),
			DefaultBranch(),
		),
	)
	require.Equal(t, expected, Serialize(query))

	repos = []*db.Repository{privateRepo(1)}
	query, _ = rewriteQuery(t, "world NOT repo_id:1", actorWithAccess(repos), repos...)
	expected = Serialize(And(
		Text("world"),
		Not(
			RepoID(1),
		),
		DefaultBranch(),
		Or(
			RepoID(1),
			PublicRepo(),
		),
	),
	)
	require.Equal(t, expected, Serialize(query))
}

func Test_GlobalQueries(t *testing.T) {
	repos := []*db.Repository{privateRepo(1)}
	query, _ := rewriteQuery(t, "hello world", actorWithAccess(repos), repos...)
	expected := Serialize(
		And(
			Text("hello"),
			Text("world"),
			DefaultBranch(),
			Or(
				RepoID(1),
				PublicRepo(),
			),
		),
	)
	require.Equal(t, expected, Serialize(query))

	query, _ = rewriteQuery(t, "hello OR world", actorWithAccess(repos), repos...)
	expected = Serialize(
		And(
			Or(
				Text("hello"),
				Text("world"),
			),
			DefaultBranch(),
			Or(
				RepoID(1),
				PublicRepo(),
			),
		),
	)
	require.Equal(t, expected, Serialize(query))

	query, _ = rewriteQuery(t, "NOT hello world", actorWithAccess(repos), repos...)
	expected = Serialize(
		And(
			Not(
				Text("hello"),
			),
			Text("world"),
			DefaultBranch(),
			Or(
				RepoID(1),
				PublicRepo(),
			),
		),
	)
	require.Equal(t, expected, Serialize(query))

	query, _ = rewriteQuery(t, "trait:public_repo hello", actorWithAccess(repos), repos...)
	expected = Serialize(
		And(
			PublicRepo(),
			Text("hello"),
			DefaultBranch(),
		),
	)
	require.Equal(t, expected, Serialize(query))
}

func Test_BasicRewriteForInaccessiblePrivateRepo(t *testing.T) {
	query, _ := rewriteQuery(t, "repo_id:1", actorWithAccess(nil), privateRepo(1))
	require.Equal(t, Serialize(Nothing()), Serialize(query))

	query, _ = rewriteQuery(t, "repo_id:1 hello", actorWithAccess(nil), privateRepo(1))
	require.Equal(t, Serialize(Nothing()), Serialize(query))
}

func Test_PublicRepo(t *testing.T) {
	query, _ := rewriteQuery(t, "repo_id:1", actorWithAccess(nil), publicRepo(1))
	require.Equal(t, Serialize(And(RepoID(1), DefaultBranch())), Serialize(query))

	repos := []*db.Repository{publicRepo(1)}
	query, _ = rewriteQuery(t, "repo_id:1", actorWithAccess(repos), repos...)
	require.Equal(t, Serialize(And(RepoID(1), DefaultBranch())), Serialize(query))
}

func Test_RepoNotIndexed(t *testing.T) {
	expected := []*QueryError{{
		Message: `Unknown repo_id: [1]`,
		Ranges: []Range{{
			Start: 0,
			End:   9,
		}},
		Type: ErrorTypeParsingWarning,
	}}

	// Repo isn't indexed and no accessible repo ids
	query, errors := rewriteQuery(t, "repo_id:1", actorWithAccess(nil))
	require.Equal(t, Serialize(Nothing()), Serialize(query))
	require.Equal(t, expected, errors)

	// Single accessible_repo_id
	query, errors = rewriteQuery(t, "repo_id:1", actorWithAccess([]*db.Repository{privateRepo(1)}))
	require.Equal(t, Serialize(Nothing()), Serialize(query))
	require.Equal(t, expected, errors)

	// Single accessible_repo_id (different repo though)
	query, errors = rewriteQuery(t, "repo_id:1", actorWithAccess([]*db.Repository{privateRepo(2)}))
	require.Equal(t, Serialize(Nothing()), Serialize(query))
	require.Equal(t, expected, errors)
}

// Repo is in snapshot index with various kinds of permanent error
func Test_RepoWithPermanentError(t *testing.T) {
	const (
		repoID = 1
		nwo    = "github/xyz"
	)

	var tests = []struct {
		permanentErrorType entities.PermanentErrorType
		expectedMessage    string
		expectedErrorType  ErrorType
	}{
		{
			permanentErrorType: entities.PermanentErrorType_SYSTEM_LIMIT,
			expectedMessage:    `Unknown repo: "github/xyz"`,
			expectedErrorType:  ErrorTypeMissingInaccessibleRepoOrg,
		},
		{
			permanentErrorType: entities.PermanentErrorType_RETRIES_EXHAUSTED,
			expectedMessage:    `Unknown repo: "github/xyz"`,
			expectedErrorType:  ErrorTypeMissingInaccessibleRepoOrg,
		},
		{
			permanentErrorType: entities.PermanentErrorType_INVALID_DEFAULT_REF,
			expectedMessage:    `Unknown repo: "github/xyz"`,
			expectedErrorType:  ErrorTypeMissingInaccessibleRepoOrg,
		},
		{
			permanentErrorType: entities.PermanentErrorType_BAD_COMMIT,
			expectedMessage:    `Unknown repo: "github/xyz"`,
			expectedErrorType:  ErrorTypeMissingInaccessibleRepoOrg,
		},
		{
			permanentErrorType: entities.PermanentErrorType_LEGACY_ERROR, // This gives a vague error message since we don't know the actual cause
			expectedMessage:    `Unknown repo: "github/xyz"`,
			expectedErrorType:  ErrorTypeMissingInaccessibleRepoOrg,
		},
		{
			permanentErrorType: entities.PermanentErrorType_FETCHING_METADATA_FAILED,
			expectedMessage:    `Unknown repo: "github/xyz"`,
			expectedErrorType:  ErrorTypeMissingInaccessibleRepoOrg,
		},
	}

	for _, test := range tests {
		t.Run(test.permanentErrorType.String(), func(t *testing.T) {
			snapshot := &snapshotpb.SnapshotEntry{
				RepoId:             repoID,
				Nwo:                nwo,
				PermanentError:     "some string message",
				PermanentErrorType: test.permanentErrorType,
			}
			index := helpers.SearchIndexWithSnapshots(t, snapshot)

			query, errors := rewriteQueryWithIndex(t, fmt.Sprintf("repo:%s", nwo), actorWithAccess([]*db.Repository{privateRepo(repoID)}), nil, nil, index)
			require.Equal(t, Serialize(Nothing()), Serialize(query))

			expected := []*QueryError{
				{
					Message: test.expectedMessage,
					Ranges: []Range{{
						Start: 0,
						End:   15,
					}},
					Type:                   test.expectedErrorType,
					InaccessibleRepoOrgNWO: nwo,
				},
			}

			require.Equal(t, expected, errors)
		})
	}
}

func Test_SingleOwnerID(t *testing.T) {
	repos := []*db.Repository{}
	for i := 0; i < 15; i++ {
		repos = append(repos, privateRepoWithOwner(types.RepoID(i), uint32(2)))
	}
	query, _ := rewriteQuery(t, "hello", actorWithAccess(repos), repos...)
	expected := Serialize(
		And(
			Text("hello"),
			DefaultBranch(),
			Or(
				OwnerID(2),
				PublicRepo(),
			),
		),
	)
	require.Equal(t, expected, Serialize(query))
}

func Test_UsesAccessibleReposWhenSmaller(t *testing.T) {
	repos := []*db.Repository{}
	for i := 0; i < 10; i++ {
		repos = append(repos, privateRepoWithOwner(types.RepoID(i), uint32(i)))
	}
	query, _ := rewriteQuery(t, "hello", actorWithAccess([]*db.Repository{privateRepoWithOwner(1, 1)}), repos...)
	expected := Serialize(
		And(
			Text("hello"),
			DefaultBranch(),
			Or(
				RepoID(1),
				PublicRepo(),
			),
		),
	)
	require.Equal(t, expected, Serialize(query))
}

func Test_MultipleOwnerIDs(t *testing.T) {
	repos := []*db.Repository{}
	for i := 0; i < 15; i++ {
		owner := 2
		if i > 5 {
			owner = 4
		}
		repos = append(repos, privateRepoWithOwner(types.RepoID(i), uint32(owner)))
	}

	query, _ := rewriteQuery(t, "hello", actorWithAccess(repos), repos...)
	expected := Serialize(
		And(
			Text("hello"),
			DefaultBranch(),
			Or(
				OwnerID(2, 4),
				PublicRepo(),
			),
		),
	)
	alternative := Serialize(
		And(
			Text("hello"),
			DefaultBranch(),
			Or(
				OwnerID(4, 2),
				PublicRepo(),
			),
		),
	)
	actual := Serialize(query)

	// NOTE: the ordering is not deterministic, so try both
	if expected != actual && alternative != actual {
		require.Equal(t, expected, actual)
	}
}

func Test_SameMultipleReposWithSameOwnerID(t *testing.T) {
	repos := []*db.Repository{}
	for i := 0; i < 15; i++ {
		repos = append(repos, privateRepoWithOwner(types.RepoID(i), uint32(2)))
	}

	query, _ := rewriteQuery(t, "hello", actorWithAccess(repos), privateRepoWithOwner(1, 2), privateRepoWithOwner(2, 2))
	expected := Serialize(
		And(
			Text("hello"),
			DefaultBranch(),
			Or(
				OwnerID(2),
				PublicRepo(),
			),
		),
	)
	require.Equal(t, expected, Serialize(query))
}

func Test_BranchTraitSpecified(t *testing.T) {
	query, _ := rewriteQuery(t, "repo_id:1 trait:non_default_branch", actorWithAccess(nil), publicRepo(1))
	require.Equal(t, Serialize(And(RepoID(1), Trait(Text("non_default_branch")))), Serialize(query))
}

func Test_BranchSomeOtherTraitSpecified(t *testing.T) {
	query, _ := rewriteQuery(t, "repo_id:1 trait:non_default_branch trait:other_trait", actorWithAccess(nil), publicRepo(1))
	require.Equal(t, Serialize(
		And(
			RepoID(1), Trait(Text("non_default_branch")),
			Trait(Text("other_trait")),
		),
	), Serialize(query))
}

func Test_NonBranchTraitSpecified(t *testing.T) {
	query, _ := rewriteQuery(t, "repo_id:1 trait:other_trait", actorWithAccess(nil), publicRepo(1))
	require.Equal(t, Serialize(
		And(
			RepoID(1),
			Trait(Text("other_trait")),
			DefaultBranch(),
		),
	), Serialize(query))
}

func Test_PushDownNots(t *testing.T) {
	var tests = []struct {
		q        string
		expected *Query
	}{
		{
			q: "NOT NOT foo",
			expected: And(
				Text("foo"),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "NOT NOT NOT foo",
			expected: And(
				Not(Text("foo")),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "NOT (foo)",
			expected: And(
				Not(Text("foo")),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "NOT (NOT foo)",
			expected: And(
				Text("foo"),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "NOT (foo bar baz)",
			expected: And(
				Or(
					Not(Text("foo")),
					Not(Text("bar")),
					Not(Text("baz")),
				),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "(foo AND bar) AND NOT (x OR NOT y) NOT path:readme.md",
			expected: And(
				Text("foo"),
				Text("bar"),
				Not(Text("x")),
				Text("y"),
				Not(MakeQualifier(PathQualifier, (Text("readme.md")))),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "NOT (/[a-z]+/ AND (NOT x NOT y))",
			expected: And(
				Or(
					Not(Regex("[a-z]+")),
					Text("x"),
					Text("y"),
				),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "(NOT (NOT (NOT (NOT (x y NOT z)))))",
			expected: And(
				Text("x"),
				Text("y"),
				Not(Text("z")),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "x AND NOT (y OR NOT z)",
			expected: And(
				Text("x"),
				Not(Text("y")),
				Text("z"),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "NOT is:archived",
			expected: And(
				NonArchivedRepo(),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "NOT is:vendored",
			expected: And(
				NonVendoredTrait(),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "NOT is:generated",
			expected: And(
				NonGeneratedTrait(),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "NOT is:fork",
			expected: And(
				NonForkRepo(),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "NOT (is:archived OR foo)",
			expected: And(
				NonArchivedRepo(),
				Not(Text("foo")),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		// Negative tests below here.
		// These queries shouldn't be changed by rewriting.
		{
			q: "foo AND bar NOT baz",
			expected: And(
				Text("foo"),
				Text("bar"),
				Not(Text("baz")),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "(foo AND bar OR baz)",
			expected: And(
				Or(
					And(
						Text("foo"),
						Text("bar"),
					),
					Text("baz"),
				),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "is:archived",
			expected: And(
				ArchivedRepo(),
				DefaultBranch(),
				PublicRepo(),
			),
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.q, func(t *testing.T) {
			t.Parallel()

			query, _ := rewriteQuery(t, test.q, nil)
			require.Equal(t, Serialize(test.expected), Serialize(query))
		})
	}
}

func TestRepoNameRewriting(t *testing.T) {
	for _, nwo := range []string{"github/blackbird", "GitHub/blackbird", "github/Blackbird"} {
		repos := []*db.Repository{
			{
				Name:       "blackbird",
				OwnerLogin: "github",
				RepoID:     123,
				IsPublic:   false,
			},
		}
		query, _ := rewriteQuery(t, fmt.Sprintf("repo:%s hello world", nwo), actorWithAccess(repos), repos...)
		expected := Serialize(
			And(
				RepoID(123),
				Text("hello"),
				Text("world"),
				DefaultBranch(),
			))
		require.Equal(t, expected, Serialize(query), nwo)
	}
}

func TestRepoNameRewritingWithTenant(t *testing.T) {
	tenant := &pb.Tenant{Shortcode: "abcd"}
	for _, nwo := range []string{"github/blackbird", "GitHub/blackbird", "github/Blackbird"} {
		repos := []*db.Repository{
			{
				Name:       "blackbird",
				OwnerLogin: "github_abcd",
				RepoID:     123,
				IsPublic:   false,
			},
		}
		query, _ := rewriteQueryWithTenant(t, fmt.Sprintf("repo:%s hello world", nwo), actorWithAccess(repos), tenant, repos...)
		expected := Serialize(
			And(
				RepoID(123),
				Text("hello"),
				Text("world"),
				DefaultBranch(),
			))
		require.Equal(t, expected, Serialize(query), nwo)
	}
}

func TestUnknownRepoRewriting(t *testing.T) {
	repos := []*db.Repository{
		{
			Name:       "blackbird",
			OwnerLogin: "github",
			RepoID:     123,
			IsPublic:   false,
		},
	}

	query, _ := rewriteQuery(t, "repo:j hello world", actorWithAccess(repos))
	expected := Serialize(
		Nothing(),
	)
	require.Equal(t, expected, Serialize(query))

	query, _ = rewriteQuery(t, "repo:j/k hello world", actorWithAccess(repos))
	expected = Serialize(
		Nothing(),
	)
	require.Equal(t, expected, Serialize(query))
}

func TestOrgLoginRewriting(t *testing.T) {
	for _, login := range []string{"github", "GitHub", "gItHuB"} {
		query, _ := rewriteQuery(t, fmt.Sprintf("org:%s hello world", login), nil, &db.Repository{
			Name:       "github",
			OwnerLogin: "github",
			RepoID:     123,
			OwnerID:    5050,
			IsPublic:   false,
		})
		expected := Serialize(And(
			OwnerID(5050),
			Text("hello"),
			Text("world"),
			DefaultBranch(),
			PublicRepo(),
		))
		require.Equal(t, expected, Serialize(query))
	}
}

func TestOrgLoginRewritingWithTenant(t *testing.T) {
	tenant := &pb.Tenant{Shortcode: "axybze"}
	for _, login := range []string{"github", "GitHub", "gItHuB"} {
		query, _ := rewriteQueryWithTenant(t, fmt.Sprintf("org:%s hello world", login), nil /* actor */, tenant, &db.Repository{
			Name:       "github",
			OwnerLogin: "github_axybze",
			RepoID:     123,
			OwnerID:    5050,
			IsPublic:   false,
		})
		expected := Serialize(And(
			OwnerID(5050),
			Text("hello"),
			Text("world"),
			DefaultBranch(),
			PublicRepo(),
		))
		require.Equal(t, expected, Serialize(query))
	}
}

func TestLanguageRewriting(t *testing.T) {
	query, _ := rewriteQuery(t, "language:python hello world", actorWithAccess([]*db.Repository{privateRepo(1)}))
	expected := Serialize(And(
		LanguageID(303), // = python
		Text("hello"),
		Text("world"),
		DefaultBranch(),
		Or(RepoID(1), PublicRepo()),
	))
	require.Equal(t, expected, Serialize(query))
}

func TestIsQualifierRewriting(t *testing.T) {
	var tests = []struct {
		q        string
		expected *Query
	}{
		{
			q: "is:archived",
			expected: And(
				ArchivedRepo(),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "is:vendored",
			expected: And(
				VendoredTrait(),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "is:generated",
			expected: And(
				GeneratedTrait(),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "is:fork",
			expected: And(
				ForkRepo(),
				DefaultBranch(),
				PublicRepo(),
			),
		},
		{
			q: "is:generated OR is:vendored",
			expected: And(
				Or(GeneratedTrait(), VendoredTrait()),
				DefaultBranch(),
				PublicRepo(),
			),
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.q, func(t *testing.T) {
			t.Parallel()

			query, _ := rewriteQuery(t, test.q, nil)
			require.Equal(t, Serialize(test.expected), Serialize(query))
		})
	}

}

func TestLanguageRewritingWithSymbol(t *testing.T) {
	query, _ := rewriteQuery(t, "symbol:abcdef_ghi", actorWithAccess([]*db.Repository{privateRepo(1)}))
	expected := Serialize(
		And(
			Symbol(Text("abcdef_ghi")),
			DefaultBranch(),
			Or(RepoID(1), PublicRepo()),
		))
	require.Equal(t, expected, Serialize(query))
}

func TestExfiltration(t *testing.T) {
	// Check exfiltration of repos
	noAccessQuery, errors := rewriteQuery(t, "repo:github/blackbird hello world", actorWithAccess(nil), &db.Repository{
		Name:       "blackbird",
		OwnerLogin: "github",
		RepoID:     123,
		IsPublic:   false,
	})
	require.Equal(t, Serialize(Nothing()), Serialize(noAccessQuery))
	require.Equal(t, []*QueryError{{
		Message: `Unknown repo: "github/blackbird"`,
		Ranges: []Range{{
			Start: 0,
			End:   21,
		}},
		InaccessibleRepoOrgNWO: "github/blackbird",
		Type:                   ErrorTypeMissingInaccessibleRepoOrg,
	}}, errors)

	doesNotExistQuery, errors := rewriteQuery(t, "repo:github/blackbird hello world", actorWithAccess(nil))
	require.Equal(t, Serialize(Nothing()), Serialize(doesNotExistQuery))
	require.Equal(t, errors, []*QueryError{{
		Message: `Unknown repo: "github/blackbird"`,
		Ranges: []Range{{
			Start: 0,
			End:   21,
		}},
		InaccessibleRepoOrgNWO: "github/blackbird",
		Type:                   ErrorTypeMissingInaccessibleRepoOrg,
	}})

	// TODO: We should allow these (org existence is not secret)
	//
	// Check that nonexistent orgs are rewritten as nothing
	doesNotExistQuery, errors = rewriteQuery(t, "org:github hello world", actorWithAccess(nil))
	require.Equal(t, Serialize(Nothing()), Serialize(doesNotExistQuery))
	require.Equal(t, errors, []*QueryError{{
		Message: `Unknown org or user: "github"`,
		Ranges: []Range{{
			Start: 0,
			End:   10,
		}},
		InaccessibleRepoOrgNWO: "github",
		Type:                   ErrorTypeMissingInaccessibleRepoOrg,
	}})
}

func TestContradictoryQuerySimplification(t *testing.T) {
	query, _ := rewriteQuery(t, "org:facebook repo:github/blackbird", actorWithAccess(nil),
		&db.Repository{
			Name:       "blackbird",
			OwnerLogin: "github",
			RepoID:     1,
			OwnerID:    10,
			IsPublic:   true,
		},
		&db.Repository{
			Name:       "presto",
			OwnerLogin: "facebook",
			RepoID:     2,
			OwnerID:    20,
			IsPublic:   true,
		},
	)
	SimplifyQuery(query)

	// The contradictory owner ID should not be removed
	expected := Serialize(And(OwnerID(20), RepoID(1), DefaultBranch()))
	require.Equal(t, expected, Serialize(query))
}

func TestRepoQuotedString(t *testing.T) {
	query, _ := rewriteQuery(t, `repo:"github/blackbird"`, actorWithAccess([]*db.Repository{privateRepo(1)}),
		&db.Repository{
			Name:       "blackbird",
			OwnerLogin: "github",
			RepoID:     1,
			OwnerID:    10,
			IsPublic:   false,
		},
	)
	SimplifyQuery(query)

	expected := Serialize(And(RepoID(1), DefaultBranch()))
	require.Equal(t, expected, Serialize(query))
}

func TestRewriteCustomScopes(t *testing.T) {
	// Rewrite based on named scope
	query, _ := rewriteQueryWithCustomScopes(t, "scope:mycustomscope", map[string]*Query{"mycustomscope": Language("go")})
	SimplifyQuery(query)
	expected := Serialize(And(LanguageID(132), DefaultBranch(), PublicRepo()))
	require.Equal(t, expected, Serialize(query))

	// Rewrite based on a repo name
	query, errors := rewriteQueryWithCustomScopes(t, "scope:github/blackbird",
		map[string]*Query{},
		&db.Repository{
			Name:       "blackbird",
			OwnerLogin: "github",
			RepoID:     1,
			OwnerID:    10,
			IsPublic:   true,
		},
	)
	if errors != nil {
		require.Equal(t, []*QueryError{}, errors)
	}
	SimplifyQuery(query)
	expected = Serialize(And(RepoID(1), DefaultBranch()))
	require.Equal(t, expected, Serialize(query))

	// Rewrite based on user/org name
	query, errors = rewriteQueryWithCustomScopes(t, "scope:@github",
		map[string]*Query{},
		&db.Repository{
			Name:       "blackbird",
			OwnerLogin: "github",
			RepoID:     1,
			OwnerID:    10,
			IsPublic:   true,
		},
	)
	if errors != nil {
		require.Equal(t, []*QueryError{}, errors)
	}
	SimplifyQuery(query)
	expected = Serialize(And(OwnerID(10), DefaultBranch(), PublicRepo()))
	require.Equal(t, expected, Serialize(query))
}

func TestRewriteCustomScopesWithError(t *testing.T) {
	// Rewrite based on named scope
	_, errors := rewriteQueryWithCustomScopes(t, "scope:fakescope", map[string]*Query{})
	require.Equal(t, []*QueryError{{
		Message: `Unknown custom scope: fakescope`,
		Ranges:  []Range{{Start: 0, End: 15}},
		Type:    ErrorTypeParsingFatal,
	}}, errors)

	_, errors = rewriteQueryWithCustomScopes(t, "scope:github/blackbird", map[string]*Query{})
	require.Equal(t, []*QueryError{{
		Message:                `Unknown repo: "github/blackbird"`,
		Ranges:                 []Range{{Start: 0, End: 22}},
		Type:                   ErrorTypeMissingInaccessibleRepoOrg,
		InaccessibleRepoOrgNWO: "github/blackbird",
	}}, errors)

	// NB: Can't do this if we use trait:owner_
	_, errors = rewriteQueryWithCustomScopes(t, "scope:@github", map[string]*Query{})
	require.Equal(t, []*QueryError{{
		Message:                `Unknown org or user: "github"`,
		Ranges:                 []Range{{Start: 0, End: 13}},
		Type:                   ErrorTypeMissingInaccessibleRepoOrg,
		InaccessibleRepoOrgNWO: "github",
	}}, errors)
}

func TestRewriteCustomScopesRecursion(t *testing.T) {
	_, errors := rewriteQueryWithCustomScopes(t, "scope:fakescope AND xyz", map[string]*Query{"fakescope": MakeQualifier(ScopeQualifier, Text("fakescope"))})
	require.Equal(t, []*QueryError{{
		Message: `Named scopes cannot be nested`,
		Ranges:  []Range{{Start: 0, End: 15}},
		Type:    ErrorTypeParsingFatal,
	}}, errors)

	_, errors = rewriteQueryWithCustomScopes(t, "scope:a OR scope:b", map[string]*Query{"a": MakeQualifier(ScopeQualifier, Text("b")), "b": MakeQualifier(ScopeQualifier, Text("a"))})
	require.Equal(t, []*QueryError{{
		Message: `Named scopes cannot be nested`,
		Ranges:  []Range{{Start: 0, End: 7}},
		Type:    ErrorTypeParsingFatal,
	}}, errors)

	// In this case, a org in: qualifier is nested within a custom scope, which is fine
	query, errors := rewriteQueryWithCustomScopes(t, "xyz OR scope:recurscope",
		map[string]*Query{"recurscope": MakeQualifier(ScopeQualifier, Text("@github"))},
		&db.Repository{
			Name:       "blackbird",
			OwnerLogin: "github",
			RepoID:     1,
			OwnerID:    10,
			IsPublic:   true,
		},
	)

	if errors != nil {
		require.Equal(t, []*QueryError{}, errors)
	}
	expected := Serialize(And(Or(Text("xyz"), OwnerID(10)), DefaultBranch(), PublicRepo()))
	require.Equal(t, expected, Serialize(query))
}

func TestRewriteCustomScopesComplexCase(t *testing.T) {
	// Rewrite based on user/org name
	query, errors := rewriteQueryWithCustomScopes(t, "scope:blackbird OR (scope:@github AND /xyz/)",
		map[string]*Query{"blackbird": Repo("github/blackbird")},
		&db.Repository{
			Name:       "blackbird",
			OwnerLogin: "github",
			RepoID:     1,
			OwnerID:    10,
			IsPublic:   true,
		},
	)
	if errors != nil {
		require.Equal(t, []*QueryError{}, errors)
	}
	SimplifyQuery(query)
	expected := Serialize(And(Or(RepoID(1), And(OwnerID(10), Regex("xyz"))), DefaultBranch(), PublicRepo()))
	require.Equal(t, expected, Serialize(query))
}

func TestErrorReportingInsideCustomScope(t *testing.T) {
	// Rewrite based on user/org name
	_, errors := rewriteQueryWithCustomScopes(t, "abc AND scope:missing OR /xyz/",
		map[string]*Query{"missing": Repo("github/doesnotexist")},
	)
	require.Equal(t, []*QueryError{{
		Message:                `Unknown repo: "github/doesnotexist"`,
		Ranges:                 []Range{{Start: 8, End: 21}},
		InaccessibleRepoOrgNWO: "github/doesnotexist",
		Type:                   ErrorTypeMissingInaccessibleRepoOrg,
	}}, errors)
}

func TestInvalidOrgQualifier(t *testing.T) {
	repos := []*db.Repository{privateRepo(1)}
	query, errors := rewriteQuery(t, "org:github/github hello world", actorWithAccess(repos), repos...)
	expected := Serialize(Nothing())
	require.Equal(t, expected, Serialize(query))
	require.Equal(t, 1, len(errors))
	require.Equal(t, "Invalid owner: github/github", errors[0].Message)
}

func TestBareRepoQualifiers(t *testing.T) {
	repos := []*db.Repository{{RepoID: 123, Name: "test", OwnerLogin: "blah", IsPublic: false}}
	query, errors := rewriteQuery(t, "language:python repo:test", actorWithAccess(repos), repos...) // query matches repo name
	expected := Serialize(Nothing())
	require.Equal(t, expected, Serialize(query))
	require.Equal(t, []*QueryError{{
		Message: "Invalid repository name: test",
		Ranges:  []Range{{Start: 16, End: 25}},
		Type:    ErrorTypeParsingWarning,
	}}, errors)

	query, errors = rewriteQuery(t, "org:blah repo:test", actorWithAccess(repos), repos...) // query matches repo name and owner name
	expected = Serialize(Nothing())
	require.Equal(t, expected, Serialize(query))
	require.Equal(t, []*QueryError{{
		Message: "Invalid repository name: test",
		Ranges:  []Range{{Start: 9, End: 18}},
		Type:    ErrorTypeParsingWarning,
	}}, errors)
}

func TestDenyRegexRepoQualifier(t *testing.T) {
	repos := []*db.Repository{
		{
			Name:       "blackbird-fe",
			OwnerLogin: "github",
			RepoID:     1,
			OwnerID:    10,
			IsPublic:   false,
		},
	}
	query, errors := rewriteQuery(t, "repo:/blackbird-.*/", actorWithAccess(repos), repos...)
	SimplifyQuery(query)
	require.Equal(t, Serialize(Nothing()), Serialize(query))
	require.Equal(t, []*QueryError{{
		Message: "Invalid repository name: blackbird-.*",
		Ranges:  []Range{{Start: 0, End: 19}},
		Type:    ErrorTypeParsingWarning,
	}}, errors)
}

func TestPromptRewriting(t *testing.T) {
	ctx := experiments.WithExperiment(context.Background(), experiments.PromptQualifier, experiments.Enabled)
	query, err := ParseQuery(ctx, `prompt:"test"`)
	if err != nil {
		log.Fatal(err)
	}

	// Copilot calls are successful and we get an embedding.
	copilot := helpers.CopilotClient(t)
	fakeEmbedding := []float32{0.1234, 0.24321, 0.2221}
	copilot.GetEmbeddingReturns(fakeEmbedding, nil)
	promptRewriter := NewEmbeddingsRewriter(copilot, routing.Text3SmallInference, 512)

	queryErrors, embeddingCount, err := RewriteQuery(ctx, query, actorWithAccess(nil), nil /* tenant */, helpers.SearchIndexWithRepos(t, publicRepo(1)), nil, promptRewriter)
	require.Empty(t, queryErrors)
	require.Equal(t, 1, embeddingCount)
	require.NoError(t, err)
	SimplifyQuery(query)
	require.Equal(t, Serialize(And(Embedding(fakeEmbedding, 70), DefaultBranch(), PublicRepo())), Serialize(query))

	require.Equal(t, IsEmbeddingSearch(ConvertToProto(query)), true)

	embeddings := getAllEmbeddings(t, query)
	require.Equal(t, 1, len(embeddings))
	require.Equal(t, fakeEmbedding, embeddings[0].Embedding)
	require.Equal(t, constants.PromptDivorToRetrieve, embeddings[0].DivorToRetrieve)
	require.Equal(t, constants.PromptDivorToScore, embeddings[0].DivorToScore)

	// Copilot calls fail and we should get an error
	copilot = helpers.CopilotClient(t)
	copilot.GetEmbeddingReturns(nil, errors.New("Azure is non-cognitive right now, come back later!"))
	promptRewriter = NewEmbeddingsRewriter(copilot, routing.Text3SmallInference, 512)
	query, err = ParseQuery(ctx, `prompt:"test"`)
	require.NoError(t, err)

	_, embeddingCount, err = RewriteQuery(ctx, query, actorWithAccess(nil), nil /* tenant */, helpers.SearchIndexWithRepos(t, publicRepo(1)), nil, promptRewriter)
	require.Equal(t, 1, embeddingCount)
	require.Error(t, err)
}

func TestMultiplePromptRewriting(t *testing.T) {
	ctx := experiments.WithExperiment(context.Background(), experiments.PromptQualifier, experiments.Enabled)
	query, err := ParseQuery(ctx, `prompt:"test" prompt:"test2"`)
	if err != nil {
		log.Fatal(err)
	}

	// Copilot calls are successful and we get an embedding.
	copilot := helpers.CopilotClient(t)
	fakeEmbedding := []float32{0.1234, 0.24321, 0.2221}
	copilot.GetEmbeddingReturns(fakeEmbedding, nil)
	promptRewriter := NewEmbeddingsRewriter(copilot, routing.Text3SmallInference, 512)

	queryErrors, embeddingCount, err := RewriteQuery(ctx, query, actorWithAccess(nil), nil /* tenant */, helpers.SearchIndexWithRepos(t, publicRepo(1)), nil, promptRewriter)
	require.Empty(t, queryErrors)
	require.Equal(t, 2, embeddingCount)
	require.NoError(t, err)
	SimplifyQuery(query)
	require.Equal(t, Serialize(And(Embedding(fakeEmbedding, 70), Embedding(fakeEmbedding, 70), DefaultBranch(), PublicRepo())), Serialize(query))

	require.Equal(t, IsEmbeddingSearch(ConvertToProto(query)), true)

	embeddings := getAllEmbeddings(t, query)
	require.Equal(t, 2, len(embeddings))
	require.Equal(t, fakeEmbedding, embeddings[0].Embedding)
	require.Equal(t, constants.PromptDivorToRetrieve, embeddings[0].DivorToRetrieve)
	require.Equal(t, constants.PromptDivorToScore, embeddings[0].DivorToScore)

	// Copilot calls fail and we should get an error and attempt to compute the first embedding
	copilot = helpers.CopilotClient(t)
	copilot.GetEmbeddingReturns(nil, errors.New("Azure is non-cognitive right now, come back later!"))
	promptRewriter = NewEmbeddingsRewriter(copilot, routing.Text3SmallInference, 512)
	query, err = ParseQuery(ctx, `prompt:"test"`)
	require.NoError(t, err)

	_, embeddingCount, err = RewriteQuery(ctx, query, actorWithAccess(nil), nil /* tenant */, helpers.SearchIndexWithRepos(t, publicRepo(1)), nil, promptRewriter)
	require.Equal(t, 1, embeddingCount)
	require.Error(t, err)
}

func TestBM25Rewriting(t *testing.T) {
	ctx := experiments.WithExperiment(context.Background(), experiments.PromptQualifier, experiments.PromptQualifierBM25)
	query, err := ParseQuery(ctx, `prompt:"how do I use code search"`)
	if err != nil {
		log.Fatal(err)
	}

	promptRewriter := BM25PromptRewriter{}
	_, _, err = RewriteQuery(ctx, query, actorWithAccess(nil), nil /* tenant */, helpers.SearchIndexWithRepos(t, publicRepo(1)), nil, promptRewriter)
	require.NoError(t, err)
	require.Equal(t, IsEmbeddingSearch(ConvertToProto(query)), false)
	SimplifyQuery(query)
	require.Equal(t, Serialize(And(
		BM25("how do I use code search"),
		DefaultBranch(),
		PublicRepo(),
	)), Serialize(query))
}

func getAllEmbeddings(t *testing.T, query *Query) []*Query {
	prompts := []*Query{}
	if query.Kind == QualifierQuery && query.QualifierKind == EmbeddingQualifier {
		prompts = append(prompts, query)
	}
	for _, sub := range query.Subqueries {
		prompts = append(prompts, getAllEmbeddings(t, sub)...)
	}

	return prompts
}

func actorWithAccess(repos []*db.Repository) *models.Actor {
	repoIDs := types.RepoIDSet{}
	orgIDs := types.U32Set{}
	for _, r := range repos {
		repoIDs[r.RepoID] = true
		orgIDs[r.OwnerID] = true
	}

	return &models.Actor{
		ID:                        1,
		AccessiblePrivateRepoIDs:  repoIDs,
		AccessibleOrganizationIDs: orgIDs,
	}
}

func rewriteQuery(t *testing.T, q string, actor *models.Actor, repos ...*db.Repository) (*Query, []*QueryError) {
	return rewriteQueryWithRepos(t, q, actor, nil /* tenant */, nil /* customScopes */, repos...)
}

func rewriteQueryWithCustomScopes(t *testing.T, q string, customScopes map[string]*Query, repos ...*db.Repository) (*Query, []*QueryError) {
	return rewriteQueryWithRepos(t, q, actorWithAccess(nil), nil /* tenant */, customScopes, repos...)
}

func rewriteQueryWithTenant(t *testing.T, q string, actor *models.Actor, tenant *pb.Tenant, repos ...*db.Repository) (*Query, []*QueryError) {
	return rewriteQueryWithRepos(t, q, actor, tenant, nil /* customScopes */, repos...)
}

func rewriteQueryWithRepos(t *testing.T, q string, actor *models.Actor, tenant *pb.Tenant, customScopes map[string]*Query, repos ...*db.Repository) (*Query, []*QueryError) {
	return rewriteQueryWithIndex(t, q, actor, tenant, customScopes, helpers.SearchIndexWithRepos(t, repos...))
}

func rewriteQueryWithIndex(t *testing.T, q string, actor *models.Actor, tenant *pb.Tenant, customScopes map[string]*Query, index search.Index) (*Query, []*QueryError) {
	t.Helper()

	query, err := ParseQuery(context.Background(), q)
	require.NoError(t, err)

	queryErrors, _, err := RewriteQuery(context.Background(), query, actor, tenant, index, customScopes, DisallowPromptQueries{})
	require.NoError(t, err)
	SimplifyQuery(query)
	return query, queryErrors
}

func publicRepo(id types.RepoID) *db.Repository {
	return &db.Repository{RepoID: id, Name: fmt.Sprintf("public-repo-%d", id), OwnerLogin: "test-owner", IsPublic: true}
}

func privateRepo(id types.RepoID) *db.Repository {
	return &db.Repository{RepoID: id, Name: fmt.Sprintf("private-repo-%d", id), OwnerLogin: "test-owner", IsPublic: false}
}

func privateRepoWithOwner(id types.RepoID, owner uint32) *db.Repository {
	return &db.Repository{RepoID: id, Name: fmt.Sprintf("private-repo-%d", id), OwnerLogin: "test-owner", OwnerID: owner, IsPublic: false}
}
