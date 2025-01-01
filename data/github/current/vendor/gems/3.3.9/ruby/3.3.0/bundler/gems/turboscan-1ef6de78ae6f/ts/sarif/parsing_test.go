package sarif_test

import (
	"path/filepath"
	"testing"

	"github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/sarif/samples"
	"github.com/stretchr/testify/require"
)

func TestParsingExampleFiles(t *testing.T) {
	files, err := filepath.Glob("testdata/*.sarif")
	require.NoError(t, err, "No test sarif files found")

	for _, file := range files {
		t.Run(file, func(t *testing.T) {
			t.Log("Loading", file)
			samples.RequireSARIF(t, file)
		})

	}
}

func TestResultExtraction(t *testing.T) {
	file := samples.RequireSARIF(t, "testdata/builtSarif.sarif")
	resultMap, err := sarif.ResultsByAlertNumber(file)
	require.NoError(t, err)
	require.NotNil(t, resultMap)
	for i, result := range resultMap {
		require.NotNil(t, result.Properties)
		require.Equal(t, int(i), result.Properties.GithubAlertNumber)
	}
}
