package gormext_test

import (
	"encoding/json"
	"testing"

	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/gormext"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
)

func TestGormErrorCallbackDoesNotInterfereWithNormalErrorChecks(t *testing.T) {
	db := dbtest.RequireConnection(t)
	gormext.AddGormErrorCallback(db)
	analysis := ts.Analysis{}
	err := db.First(&analysis).Error
	require.Error(t, err)
	require.True(t, gorm.IsRecordNotFoundError(err))
}

func TestGormErrorCallbackExtendsErrors(t *testing.T) {
	db := dbtest.RequireConnection(t)
	gormext.AddGormErrorCallback(db)
	analysis := ts.Analysis{AnalysisKey: "semisecret"}
	err := db.Table("nonexistent").First(&analysis, &analysis).Error
	require.Error(t, err)
	require.False(t, gorm.IsRecordNotFoundError(err))
	queryError := &gormext.QueryError{}
	require.True(t, errors.As(err, &queryError))
	require.Contains(t, queryError.SQL, "FROM `nonexistent`")
	require.NotContains(t, queryError.SQL, "semisecret")
	marshaledSQLVars, err := json.Marshal(queryError.SQLVars)
	require.NoError(t, err)
	require.Contains(t, string(marshaledSQLVars), "semisecret")
	// require.Contains(t, queryError.SQLVars, "semisecret")
}
