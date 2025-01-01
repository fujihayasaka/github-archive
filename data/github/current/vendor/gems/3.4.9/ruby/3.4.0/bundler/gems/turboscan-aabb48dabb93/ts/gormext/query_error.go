package gormext

import (
	"github.com/jinzhu/gorm"
)

type QueryError struct {
	Err     error
	SQL     string
	SQLVars []interface{}
}

func (e *QueryError) Error() string {
	return e.Err.Error()
}

func (e *QueryError) Unwrap() error {
	return e.Err
}

func AddGormErrorCallback(db *gorm.DB) {
	db.Callback().Query().After("gorm:query").Register("query_errors", afterQuery)
	db.Callback().Create().After("gorm:query").Register("query_errors", afterQuery)
	db.Callback().Update().After("gorm:query").Register("query_errors", afterQuery)
	db.Callback().Delete().After("gorm:query").Register("query_errors", afterQuery)
}

func afterQuery(scope *gorm.Scope) {
	if scope.HasError() && !gorm.IsRecordNotFoundError(scope.DB().Error) {
		err := QueryError{
			Err:     scope.DB().Error,
			SQL:     scope.SQL,
			SQLVars: scope.SQLVars,
		}
		scope.DB().Error = &err
	}
}
