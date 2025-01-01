package mysqldb

import (
	"errors"
	"fmt"

	"github.com/github/go-exceptions"
	"github.com/go-sql-driver/mysql"
)

func RollupDBError(err error) error {
	if err == nil {
		return nil
	}

	var mysqlErr *mysql.MySQLError
	if !errors.As(err, &mysqlErr) {
		return err
	}

	return exceptions.WithRollupInfo(err, fmt.Sprintf("mysql error %d", mysqlErr.Number))
}
