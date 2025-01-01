package mysql

import (
	"errors"

	"github.com/go-sql-driver/mysql"
)

// https://dev.mysql.com/doc/mysql-errors/8.0/en/server-error-reference.html#error_er_lock_nowait
func IsLockNoWaitErr(err error) bool {
	var sqlError *mysql.MySQLError
	if errors.As(err, &sqlError) {
		return sqlError.Number == 3572
	}

	return false
}
