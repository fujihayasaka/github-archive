package alert_test

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/github/turboscan/ts/mysql/alert"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/mysql/gormbulk"
	"github.com/stretchr/testify/require"
)

func TestStoreUnrecoverableAnalysisError(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	id := ts.AnalysisID(42)
	analysis := ts.Analysis{
		ID:                 id,
		RepositoryID:       55,
		SourceRepositoryID: 55,
	}

	sarifID, _ := ts.NewSarifID("4b2d3d60-b565-4556-9733-a74e9b7fe748")
	pe := ts.NewUnrecoverableAnalysisError(analysis.RepositoryID, &analysis, "This is a test")
	pe.SarifID = sarifID
	err := as.LogProcessError(ctx, pe)
	require.NoError(t, err)

	require.NoError(t, db.Find(&pe).Error)
	require.Equal(t, pe.Message, "This is a test")
	require.Equal(t, sarifID, pe.SarifID)
}

func TestTruncateProcessErrorMessage(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	id := ts.AnalysisID(42)
	analysis := ts.Analysis{
		ID:                 id,
		RepositoryID:       55,
		SourceRepositoryID: 55,
	}

	message := strings.Repeat("I'm a super long string!", 171)
	pe := ts.NewUnrecoverableAnalysisError(analysis.RepositoryID, &analysis, message)
	err := as.LogProcessError(ctx, pe)
	require.NoError(t, err)

	require.NoError(t, db.Find(&pe).Error)
	require.Equal(t, 4096, len(pe.Message))
}

func TestStoreUnrecoverableDeliveryError(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	sarifID, _ := ts.NewSarifID("4b2d3d60-b565-4556-9733-a74e9b7fe748")
	pe := ts.NewUnrecoverableDeliveryError(55, sarifID, "Test delivery error")
	err := as.LogProcessError(ctx, pe)
	require.NoError(t, err)

	require.NoError(t, db.Find(&pe).Error)
	require.Equal(t, "Test delivery error", pe.Message)
	require.Equal(t, sarifID, pe.SarifID)
}

func TestProcessErrorsForSarifId_noneFound(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	sarifID, _ := ts.NewSarifID("4b2d3d60-b565-4556-9733-a74e9b7fe748")
	repoID := ts.RepositoryEID(55)
	pe := ts.NewUnrecoverableDeliveryError(repoID, sarifID, "Test delivery error")
	err := as.LogProcessError(ctx, pe)
	require.NoError(t, err)

	// Both params have to match, not just one

	res, err := as.ProcessErrorsForSarifId(repoID, "05e22430-623d-4e45-a5df-c01a229dae75")
	require.NoError(t, err)
	require.Empty(t, res)

	res, err = as.ProcessErrorsForSarifId(repoID-1, sarifID)
	require.NoError(t, err)
	require.Empty(t, res)

	// Just to prove that the above aren't false positives, retrieve the error
	// (actually getting results is tested in more detail below)
	res, err = as.ProcessErrorsForSarifId(repoID, sarifID)
	require.NoError(t, err)
	require.Len(t, res, 1)
}

func TestProcessErrorsForSarifId_oneFound(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	sarifID, _ := ts.NewSarifID("4b2d3d60-b565-4556-9733-a74e9b7fe748")
	repoID := ts.RepositoryEID(55)
	pe := ts.NewUnrecoverableDeliveryError(repoID, sarifID, "Test delivery error")
	err := as.LogProcessError(ctx, pe)
	require.NoError(t, err)

	someOthersarifID, _ := ts.NewSarifID("9907c348-e805-4148-9107-5668f4dbd899")
	otherProcessError := ts.NewUnrecoverableDeliveryError(repoID, someOthersarifID, "Another test delivery error")
	err = as.LogProcessError(ctx, otherProcessError)
	require.NoError(t, err)

	res, err := as.ProcessErrorsForSarifId(repoID, sarifID)
	require.NoError(t, err)
	require.Len(t, res, 1)
	require.Equal(t, "Test delivery error", res[0].Message)
}

// This test also ensures that different error types can be returned,
// and that adding the SARIF ID after the initial creation still
// allows it to be matched.
//
// For speed of CI, those checks aren't split out into their own tests.
func TestProcessErrorsForSarifId_twoFound(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	sarifID, _ := ts.NewSarifID("4b2d3d60-b565-4556-9733-a74e9b7fe748")
	repoID := ts.RepositoryEID(55)

	pe := ts.NewUnrecoverableDeliveryError(repoID, sarifID, "Test delivery error")
	err := as.LogProcessError(ctx, pe)
	require.NoError(t, err)

	pe2 := ts.NewUnrecoverableAnalysisError(repoID, nil, "Test analysis error")
	pe2.SarifID = sarifID
	err = as.LogProcessError(ctx, pe2)
	require.NoError(t, err)

	res, err := as.ProcessErrorsForSarifId(repoID, sarifID)
	require.NoError(t, err)
	require.Len(t, res, 2)
	require.Equal(t, "Test analysis error", res[0].Message)
	require.Equal(t, "Test delivery error", res[1].Message)
}

func TestProcessErrorsForSarifId_limitAndOrder(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	ctx := context.Background()

	repoID := ts.RepositoryEID(1)
	sarifID, _ := ts.NewSarifID("03514ddb-132f-49f5-ad8a-07d57eee849d")
	var errors []*ts.ProcessError
	for i := 1; i <= 101; i++ {
		pe := ts.NewUnrecoverableDeliveryError(
			repoID,
			sarifID,
			fmt.Sprintf("Test delivery error %d", i),
		)
		errors = append(errors, pe)
	}

	err := gormbulk.Insert(ctx, &gormbulk.InsertOptions[ts.ProcessError]{
		DB:        db,
		Objects:   errors,
		ChunkSize: 100,
	})
	require.NoError(t, err)

	res, err := as.ProcessErrorsForSarifId(repoID, sarifID)
	require.NoError(t, err)
	require.Len(t, res, 100)
	// Should be a limit of 100, ordered by updated_at
	require.Equal(t, "Test delivery error 101", res[0].Message)
	require.Equal(t, "Test delivery error 2", res[99].Message)
}
