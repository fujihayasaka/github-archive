package ts_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

func TestAnalysisExtractedFilesMessages(t *testing.T) {
	db := dbtest.RequireConnection(t)
	err := db.Create(&ts.AnalysisExtractedFilesMessages{ID: 1, RepositoryID: 2, AnalysisID: 3, Path: "path", Message: "message"}).Error

	require.NoError(t, err)

	var analysisExtractedFilesMessages ts.AnalysisExtractedFilesMessages
	err = db.First(&analysisExtractedFilesMessages).Error

	require.NoError(t, err)
}
