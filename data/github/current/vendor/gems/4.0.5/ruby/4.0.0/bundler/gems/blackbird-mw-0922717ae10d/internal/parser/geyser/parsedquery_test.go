package geyser

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestString(t *testing.T) {
	leftClause := &ParsedQuery{
		Field:      Content,
		Value:      "foo",
		ClauseType: Must,
	}
	middleClause := &ParsedQuery{
		Field:      Path,
		Value:      "bar",
		ClauseType: Should,
	}
	rightClause := &ParsedQuery{
		Field:      Content,
		Value:      "baz",
		ClauseType: MustNot,
	}
	baseQuery := &ParsedQuery{
		SubQueries: []*ParsedQuery{leftClause, middleClause, rightClause},
		ClauseType: Should,
	}
	require.Equal(t, "( +content:foo path:bar -content:baz )", baseQuery.String())
}

func TestFiltersWithShould(t *testing.T) {
	// this is similar to how we are constructing public OR private repo IDs filter
	privateRepoIDsClause := &ParsedQuery{
		Field: RepositoryID,
		SubQueries: []*ParsedQuery{
			{
				Field:      RepositoryID,
				ClauseType: Should,
				Value:      "3",
			},
			{
				Field:      RepositoryID,
				ClauseType: Should,
				Value:      "4",
			},
			{
				Field:      RepositoryID,
				ClauseType: Should,
				Value:      "5",
			},
		},
		ClauseType: Should,
	}
	publicReposClause := &ParsedQuery{
		Field:      Visibility,
		Value:      "public",
		ClauseType: Should,
	}
	filters := &ParsedQuery{
		SubQueries: []*ParsedQuery{privateRepoIDsClause, publicReposClause},
		ClauseType: Filter,
	}
	contentQuery := &ParsedQuery{
		Field:      Content,
		Value:      "bar",
		ClauseType: Should,
	}
	baseQuery := &ParsedQuery{
		SubQueries: []*ParsedQuery{contentQuery, filters},
		ClauseType: Must,
	}
	require.Equal(t, "+( content:bar #( repository_id:( 3 4 5 ) visibility:public ) )", baseQuery.String())
}

func TestIllegitimateFieldInheritance(t *testing.T) {
	innerClause := &ParsedQuery{
		Field: Content,
		Value: "foo",
	}
	outerClause := &ParsedQuery{
		SubQueries: []*ParsedQuery{innerClause},
		Field:      Path,
	}
	_, err := outerClause.string(Unspecified)
	require.Error(t, err)
	require.Equal(t, "field `content` is inconsistent with inherited field `path`", err.Error())
}

func TestMissingFielInheritance(t *testing.T) {
	// the rule is that the field in a group must match the field outside of the group; it can't even be missing
	innerClause := &ParsedQuery{
		// Field:  Intentionally missing
		Value: "foo",
	}
	outerClause := &ParsedQuery{
		SubQueries: []*ParsedQuery{innerClause},
		Field:      Path,
	}
	_, err := outerClause.string(Unspecified)
	require.Error(t, err)
	require.Equal(t, "field `` is inconsistent with inherited field `path`", err.Error())
}

func TestValueAndSubQueriesShouldError(t *testing.T) {
	innerClause := &ParsedQuery{
		Field: Content,
		Value: "foo",
	}
	outerClause := &ParsedQuery{
		SubQueries: []*ParsedQuery{innerClause},
		Value:      "bar",
		Field:      Content,
	}
	_, err := outerClause.string(Unspecified)
	require.Error(t, err)
	require.Equal(t, "invalid query: both parsedQuery.Value and parsedQuery.SubQueries are populated", err.Error())
}

func TestParsedQuery_Walk(t *testing.T) {
	visitor := func(pq *ParsedQuery) error {
		t.Logf("pq.Field: %s; pq.Value: %s, pq.IsPhrase: %t, clause type: %s, len(pq.Subqueries): %d",
			pq.Field, pq.Value, pq.IsPhrase, pq.ClauseType, len(pq.SubQueries))
		return nil
	}

	exampleQuery, err := ParseQuery("python language_id:123")
	require.NoError(t, err)

	tests := []struct {
		name    string
		wantErr bool
		visits  int
		visitor func(*ParsedQuery) error
		query   *ParsedQuery
	}{
		{
			name:    "normal query",
			wantErr: false,
			visits:  4,
			query: &ParsedQuery{
				SubQueries: []*ParsedQuery{
					{
						Field:      Content,
						Value:      "foo",
						ClauseType: Must,
					},
					{
						Field:      Path,
						Value:      "bar",
						ClauseType: Should,
					},
					{
						Field:      Content,
						Value:      "baz",
						ClauseType: MustNot,
					},
				},
				ClauseType: Should,
			},
			visitor: visitor,
		},
		{
			name:    "debugging example",
			wantErr: false,
			visits:  3,
			query:   exampleQuery,
			visitor: visitor,
		},
		{
			name:    "empty subqueries",
			wantErr: false,
			visits:  1,
			query:   &ParsedQuery{},
		},
		{
			name:    "visitor errors",
			wantErr: true,
			visits:  1,
			query:   &ParsedQuery{},
			visitor: func(_ *ParsedQuery) error {
				return errors.New("error")
			},
		},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			visits := 0
			if err := tt.query.Walk(func(q *ParsedQuery) error {
				visits++
				if tt.visitor != nil {
					return tt.visitor(q)
				}
				return nil
			}); (err != nil) != tt.wantErr {
				t.Errorf("Walk() error = %v, wantErr %v", err, tt.wantErr)
			}
			require.Equal(t, tt.visits, visits)
		})
	}
}
