package pagination

import (
	"fmt"
	"math"
	"strconv"
	"testing"

	sql "github.com/Masterminds/squirrel"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewStandardFirstPage(t *testing.T) {
	page := NewStandardFirstPage()
	assert.Equal(t, "", page.Cursor())
	assert.Equal(t, int64(-1), page.Limit())
}

func TestStandardFirstPage_ApplyToAnyQuery(t *testing.T) {
	// Applies both cursor and order by queries
	r := require.New(t)
	page := NewStandardFirstPage()
	query := page.ApplyToAnyQuery(
		sql.Select("*").From("users"),
		func(q sql.SelectBuilder, page Page) sql.SelectBuilder {
			panic("should not be called")
		},
		func(q sql.SelectBuilder, page Page) sql.SelectBuilder {
			return q.OrderBy("id ASC")
		},
		func(q sql.SelectBuilder, page Page) sql.SelectBuilder {
			return q.Limit(uint64(page.Limit()))
		},
	)
	sqlStr, args, _ := query.ToSql()
	r.Nil(args)
	r.Equal(sqlStr, fmt.Sprintf("SELECT * FROM users ORDER BY id ASC LIMIT %s", strconv.FormatUint(math.MaxUint64, 10)))
}

func TestNewStandardPage(t *testing.T) {
	// Works with all values
	page := NewStandardPage(EncodeV1Cursor("5"), 20)
	assert.Equal(t, EncodeV1Cursor("5"), page.Cursor())
	assert.Equal(t, int64(20), page.Limit())

	// Works with missing cursor
	page = NewStandardPage("", 20)
	assert.Equal(t, "", page.Cursor())
	assert.Equal(t, int64(20), page.Limit())
}

func TestStandardPage_ApplyToAnyQuery(t *testing.T) {
	// Applies both cursor and order by queries
	r := require.New(t)
	sp := NewStandardPage("5", 20)
	query := sp.ApplyToAnyQuery(
		sql.Select("*").From("users"),
		func(q sql.SelectBuilder, page Page) sql.SelectBuilder {
			return q.Where("id > ?", page.Cursor())
		},
		func(q sql.SelectBuilder, page Page) sql.SelectBuilder {
			return q.OrderBy("id ASC").Limit(uint64(page.Limit()))
		},
		func(q sql.SelectBuilder, page Page) sql.SelectBuilder {
			return q.Limit(uint64(page.Limit()))
		},
	)
	sqlStr, args, _ := query.ToSql()
	r.Equal([]interface{}{"5"}, args)
	r.Equal("SELECT * FROM users WHERE id > ? ORDER BY id ASC LIMIT 20", sqlStr)
}

func TestNewNoLimitPage(t *testing.T) {
	page := NewNoLimitPage()
	assert.Equal(t, "", page.Cursor())
	assert.Equal(t, int64(-1), page.Limit())
}

func TestNoLimitPage_ApplyToAnyQuery(t *testing.T) {
	// Applies both cursor and order by queries
	r := require.New(t)
	page := NewNoLimitPage()
	query := page.ApplyToAnyQuery(
		sql.Select("*").From("users"),
		func(q sql.SelectBuilder, page Page) sql.SelectBuilder {
			panic("should not be called")
		},
		func(q sql.SelectBuilder, page Page) sql.SelectBuilder {
			return q.OrderBy("id ASC").Limit(uint64(page.Limit()))
		},
		func(q sql.SelectBuilder, page Page) sql.SelectBuilder {
			return q.Limit(uint64(page.Limit()))
		},
	)
	sqlStr, args, _ := query.ToSql()
	r.Nil(args)
	r.Equal(sqlStr, fmt.Sprintf("SELECT * FROM users ORDER BY id ASC LIMIT %s", strconv.FormatUint(math.MaxUint64, 10)))
}
