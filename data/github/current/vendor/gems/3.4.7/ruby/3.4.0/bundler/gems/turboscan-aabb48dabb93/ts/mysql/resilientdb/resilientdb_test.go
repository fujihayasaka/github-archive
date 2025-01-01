package resilientdb_test

import (
	"testing"

	"github.com/github/turboscan/ts/mysql/resilientdb"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/go-sql-driver/mysql"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
)

func failingDB(nonResilient bool) dbtest.FailingDB {
	return dbtest.FailingDB{
		TargetErr:  mysql.ErrInvalidConn,
		TotalCount: 1,
		QueryPred: func(query string) bool {
			return resilientdb.ParseSQLVerb(query) == "SELECT"
		},
		NonResilientDB: nonResilient,
	}
}

func TestRetry(t *testing.T) {
	db := failingDB(false).RequireBadConnection(t)

	codeQL := ts.Tool{
		GUID:          "guid",
		CanonicalName: "CodeQL",
	}
	dbtest.RequireCreate(t, db, &codeQL)

	var found ts.Tool

	require.NoError(t, db.Model(ts.LogicalAlert{}).First(&found).Error)
	require.NotZero(t, found.ID)
}

func TestBadConnection(t *testing.T) {
	db := failingDB(true).RequireBadConnection(t)

	codeQL := ts.Tool{
		GUID:          "guid",
		CanonicalName: "CodeQL",
	}
	dbtest.RequireCreate(t, db, &codeQL)

	var found ts.Tool

	require.ErrorIs(t, db.Model(ts.LogicalAlert{}).First(&found).Error, mysql.ErrInvalidConn)
}

func TestRetryTransaction(t *testing.T) {
	db := failingDB(false).RequireBadConnection(t)

	codeQL := ts.Tool{
		GUID:          "guid",
		CanonicalName: "CodeQL",
	}
	dbtest.RequireCreate(t, db, &codeQL)

	require.NoError(t, db.Transaction(func(tx *gorm.DB) error {
		var found ts.Tool

		require.NoError(t, db.Model(ts.LogicalAlert{}).First(&found).Error)

		require.NotZero(t, found.ID)

		return nil
	}))
}

func TestParseSQLVerb(t *testing.T) {
	require.Equal(t, "SELECT", resilientdb.ParseSQLVerb("SELECT 1"))
	require.Equal(t, "SELECT", resilientdb.ParseSQLVerb(`SELECT
1`))
	require.Equal(t, "SELECT", resilientdb.ParseSQLVerb("  SELECT 1"))
	require.Equal(t, "UPDATE", resilientdb.ParseSQLVerb("  UPDATE   1"))
	require.Equal(t, "UPDATE", resilientdb.ParseSQLVerb("  update   1"))
	require.Equal(t, "UNKNOWN", resilientdb.ParseSQLVerb("  "))
	require.Equal(t, "UNKNOWN", resilientdb.ParseSQLVerb(""))
	require.Equal(t, "UNKNOWN", resilientdb.ParseSQLVerb("SELECT"))
}
