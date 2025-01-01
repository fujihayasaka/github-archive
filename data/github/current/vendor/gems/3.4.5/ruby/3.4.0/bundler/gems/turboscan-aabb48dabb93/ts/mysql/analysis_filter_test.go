package mysql_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/mysql"
)

func TestApplyAnalysisFilter_DeliveryOrigin(t *testing.T) {
	db := dbtest.RequireConnection(t)
	repoID := ts.RepositoryEID(123)
	// Create two analyses for two delivery origin types.
	// Show that the interpretation of the DeliveryOrigin
	// filter is correct.
	ymlOrigin := ts.DeliveryOrigin_YML
	APIOrigin := ts.DeliveryOrigin_API

	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/heads/main"),
		AnalysisComplete:   true,
		DeliveryOrigin:     ymlOrigin,
	})

	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/heads/main"),
		AnalysisComplete:   true,
		DeliveryOrigin:     APIOrigin,
	})

	// Test without filter
	emptyFilter := ts.AnalysisFilter{RepositoryID: repoID}
	dbtest.RequireCount(t, 2, mysql.ApplyAnalysisFilter(emptyFilter, db.Model(&ts.Analysis{})))

	// Test with only YML Origin filter
	ymlFilter := ts.AnalysisFilter{
		RepositoryID:   repoID,
		DeliveryOrigin: &ymlOrigin,
	}
	dbtest.RequireCount(t, 1, mysql.ApplyAnalysisFilter(ymlFilter, db.Model(&ts.Analysis{})))

}
