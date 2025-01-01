// Package query implements custom SQL expressions compatible with squirrel.Sqlizer
package query

import "github.com/Masterminds/squirrel"

type isNullExpr struct {
	column string
}

// squirrel.Sqlizer interface
func (expr isNullExpr) ToSql() (string, []interface{}, error) { //nolint:stylecheck,revive // method name matches interface
	return squirrel.Eq{expr.column: nil}.ToSql()
}

// IsNull returns a `col IS NULL` expression
//
// Example:
//
// squirrel.Select("*").From("subscriptions").Where(query.IsNull("user_id"))
func IsNull(column string) squirrel.Sqlizer {
	return isNullExpr{column}
}

type isNotNullExpr struct {
	column string
}

// squirrel.Sqlizer interface
func (expr isNotNullExpr) ToSql() (string, []interface{}, error) { //nolint:stylecheck,revive // method name matches interface
	return squirrel.NotEq{expr.column: nil}.ToSql()
}

// IsNotNull returns a `col IS NOT NULL` expression
//
// Example:
//
// squirrel.Select("*").From("subscriptions").Where(query.IsNotNull("user_id"))
func IsNotNull(column string) squirrel.Sqlizer {
	return isNotNullExpr{column}
}
