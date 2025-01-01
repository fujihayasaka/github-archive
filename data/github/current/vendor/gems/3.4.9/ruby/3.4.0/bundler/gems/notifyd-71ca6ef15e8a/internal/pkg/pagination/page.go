package pagination

import (
	sql "github.com/Masterminds/squirrel"
)

// Page represents a page of results.
type Page interface {
	Cursor() string
	Limit() int64
	ApplyToAnyQuery(
		query sql.SelectBuilder,
		applyCursor func(query sql.SelectBuilder, page Page) sql.SelectBuilder,
		applyOrderBy func(query sql.SelectBuilder, page Page) sql.SelectBuilder,
		applyLimit func(query sql.SelectBuilder, page Page) sql.SelectBuilder,
	) sql.SelectBuilder
}

// StandardFirstPage represents the first page of results.
type StandardFirstPage struct{}

// NewStandardFirstPage creates a new StandardFirstPage.
func NewStandardFirstPage() StandardFirstPage {
	return StandardFirstPage{}
}

// Cursor returns the cursor.
func (p StandardFirstPage) Cursor() string {
	return ""
}

// Limit returns the limit.
func (p StandardFirstPage) Limit() int64 {
	return -1
}

// ApplyToAnyQuery applies the cursor, order by, and limit to the query.
func (p StandardFirstPage) ApplyToAnyQuery(query sql.SelectBuilder, applyCursorQuery, applyOrderBy, applyLimit func(query sql.SelectBuilder, page Page) sql.SelectBuilder) sql.SelectBuilder {
	return applyLimit(applyOrderBy(query, p), p)
}

// StandardPage represents a standard page of results.
type StandardPage struct {
	cursor string
	limit  int64
}

// Cursor returns the cursor.
func (p StandardPage) Cursor() string {
	return p.cursor
}

// Limit returns the limit.
func (p StandardPage) Limit() int64 {
	return p.limit
}

// ApplyToAnyQuery applies the cursor, order by, and limit to the query.
func (p StandardPage) ApplyToAnyQuery(query sql.SelectBuilder, applyCursorQuery, applyOrderBy, applyLimit func(query sql.SelectBuilder, page Page) sql.SelectBuilder) sql.SelectBuilder {
	return applyLimit(applyOrderBy(applyCursorQuery(query, p), p), p)
}

// NewStandardPage creates a new StandardPage.
func NewStandardPage(cursor string, limit int64) StandardPage {
	return StandardPage{
		cursor: cursor,
		limit:  limit,
	}
}

// NoLimitPage represents a page of results with no limit.
type NoLimitPage struct{}

// NewNoLimitPage creates a new NoLimitPage.
func NewNoLimitPage() NoLimitPage {
	return NoLimitPage{}
}

// Cursor returns the cursor.
func (p NoLimitPage) Cursor() string {
	return ""
}

// Limit returns the limit.
func (p NoLimitPage) Limit() int64 {
	return -1
}

// ApplyToAnyQuery applies the order by to the query.
func (p NoLimitPage) ApplyToAnyQuery(query sql.SelectBuilder, applyCursorQuery, applyOrderBy, applyLimit func(query sql.SelectBuilder, page Page) sql.SelectBuilder) sql.SelectBuilder {
	return applyOrderBy(query, p)
}
