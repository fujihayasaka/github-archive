package gormext

import (
	"strings"

	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

// union constructs the UNION of n parameters
func union(n int) string {
	params := make([]string, n)
	for i := range params {
		params[i] = "?"
	}
	return strings.Join(params, " UNION ")
}

// anySlice converts a slice of type A into a slice of type any.
func anySlice[A any](in []A) []any {
	out := make([]any, 0, len(in))
	for _, v := range in {
		out = append(out, v)
	}
	return out
}

// Union calls db.Raw with the UNION of all subqueries.
func Union(db *gorm.DB, subqueries ...*gorm.SqlExpr) *gorm.DB {
	if len(subqueries) == 0 {
		_ = db.AddError(errors.New("called union with no subqueries"))
		return db
	}
	return db.Raw(union(len(subqueries)), anySlice(subqueries)...)
}
