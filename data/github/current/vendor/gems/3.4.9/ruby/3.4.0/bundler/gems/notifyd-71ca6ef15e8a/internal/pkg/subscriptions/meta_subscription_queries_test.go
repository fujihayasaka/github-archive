package subscriptions

import (
	"testing"

	sql "github.com/Masterminds/squirrel"
	"github.com/stretchr/testify/assert"

	"github.com/github/notifyd/internal/pkg/pagination"
)

func TestApplyQueries(t *testing.T) {
	testCases := []struct {
		name     string
		page     pagination.Page
		expected sql.SelectBuilder
	}{
		{
			name:     "StandardFirstPage",
			page:     pagination.NewStandardFirstPage(),
			expected: sql.Select("*").From("meta_subscriptions AS s").OrderBy("s.id ASC").Suffix("LIMIT ?", MaximumRequestPageLimit),
		},
		{
			name:     "StandardPage",
			page:     pagination.NewStandardPage(pagination.EncodeV1Cursor("6"), 10),
			expected: sql.Select("*").From("meta_subscriptions AS s").Where(sql.Gt{"s.id": int64(6)}).OrderBy("s.id ASC").Suffix("LIMIT ?", 10),
		},
		{
			name:     "StandardPage With No Cursor",
			page:     pagination.NewStandardPage("", 10),
			expected: sql.Select("*").From("meta_subscriptions AS s").OrderBy("s.id ASC").Suffix("LIMIT ?", 10),
		},
		{
			name:     "StandardPage With No Limit",
			page:     pagination.NewStandardPage(pagination.EncodeV1Cursor("6"), 0),
			expected: sql.Select("*").From("meta_subscriptions AS s").Where(sql.Gt{"s.id": int64(6)}).OrderBy("s.id ASC").Suffix("LIMIT ?", MaximumRequestPageLimit),
		},
		{
			name:     "NoLimitPage",
			page:     pagination.NewNoLimitPage(),
			expected: sql.Select("*").From("meta_subscriptions AS s").OrderBy("s.id ASC"),
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			query := sql.Select("*").From("meta_subscriptions AS s")

			resultQuery := tc.page.ApplyToAnyQuery(query, applyCursorQuery, applyOrderBy, applyLimit)

			sql, args, _ := resultQuery.ToSql()
			sqlExpectedSQL, expectedArgs, _ := tc.expected.ToSql()

			assert.Equal(t, sqlExpectedSQL, sql)
			assert.Equal(t, expectedArgs, args)
		})
	}
}
