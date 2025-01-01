package db

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

// WriteFailoverError error return by mysql server on writes during primary failover because write requests gets routed to a
// read-only replica.
var WriteFailoverError = &mysql.MySQLError{Number: 1290}

// the returned error value must be named here so that it can be assigned in the deferred function
func WithTransaction(ctx context.Context, db *sqlx.DB, txFunc func(*sqlx.Tx) error) (err error) {
	tx, err := db.BeginTxx(ctx, nil)
	if err != nil {
		return errors.WithStack(err)
	}
	defer func() {
		if p := recover(); p != nil {
			// a panic occurred, rollback and repanic
			_ = tx.Rollback()
			panic(p)
		} else if err != nil {
			// an error was returned, rollback
			_ = tx.Rollback()
		} else {
			// err was nil, update it if Commit returns error
			if commitErr := tx.Commit(); commitErr != nil {
				err = errors.WithStack(commitErr)
			}
		}
	}()

	// assign the result of txFunc to err so the deferred closure can access it
	err = txFunc(tx)
	return err
}

func GetMinId(ctx context.Context, db *sqlx.DB, tableName string) (int, error) {
	ctx, span := tracing.ChildSpan(ctx, "mysql.GetMinId")
	defer span.End()

	var minId int
	err := db.GetContext(ctx, &minId, fmt.Sprintf("SELECT IFNULL(MIN(id), 0) FROM `%s`", tableName))
	if err != nil {
		return 0, errors.WithStack(err)
	}

	return minId, nil
}

func GetMaxId(ctx context.Context, db *sqlx.DB, tableName string) (int, error) {
	ctx, span := tracing.ChildSpan(ctx, "mysql.GetMaxId")
	defer span.End()

	var maxId int
	err := db.GetContext(ctx, &maxId, fmt.Sprintf("SELECT IFNULL(MAX(id), 0) FROM `%s`", tableName))
	if err != nil {
		return 0, errors.WithStack(err)
	}

	return maxId, nil
}

func ParseGTID(gtid string) (string, int, error) {
	parsedGTID := strings.Split(gtid, ":")
	if len(parsedGTID) != 2 {
		return "", 0, errors.Errorf("failed to parse GTID value: %s", gtid)
	}
	serverUUID := parsedGTID[0]
	transactionID := parsedGTID[1]
	transactionIDInt, err := strconv.Atoi(transactionID)
	if err != nil {
		return "", 0, errors.Wrapf(err, "failed to parse GTID value: %s", gtid)
	}

	return serverUUID, transactionIDInt, nil
}

// IDRangeWhereClause builds a WHERE query given an inclusive start/end ID
// example: IDRangeWhereClause(1, 5)
// result: "id >= 1 AND id <= 5"
func IDRangeWhereClause(startInclusive, endInclusive int) string {
	return fmt.Sprintf("id >= %v AND id <= %v", startInclusive, endInclusive)
}

// IDInWhereClause builds a "IN" WHERE query given an array of IDs
// example: IDInWhereClause([]int64{ 1, 2, 3 })
// result: "id in (1, 2, 3)"
func IDInWhereClause(ids []int64) string {
	return fmt.Sprintf("id in (%v)", common.Int64sToString(ids, ", "))
}
