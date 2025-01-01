package sarif_test

import (
	"path/filepath"
	"testing"

	"github.com/github/turboscan/ts/proto"
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

func TestParsingInvalidExampleFiles(t *testing.T) {
	files, err := filepath.Glob("testdata/invalid/*.sarif")
	require.NoError(t, err, "No test sarif files found")

	for _, file := range files {
		t.Run(file, func(t *testing.T) {
			t.Log("Loading", file)
			_, err := sarif.FromFile(file)
			require.Error(t, err)
		})
	}
}

func TestResultsByLocations(t *testing.T) {
	file := samples.RequireSARIF(t, "testdata/builtSarif.sarif")
	missingChanges := map[string][]*proto.Change{
		"test": {
			{
				StartLine: 1,
				EndLine:   1,
			},
		},
	}

	resultMap := sarif.ResultsByLocations(file, missingChanges)
	require.Empty(t, resultMap)

	existingChanges := map[string][]*proto.Change{
		"file1": {
			{
				StartLine: 1,
				EndLine:   1,
			},
		},
	}
	resultMap = sarif.ResultsByLocations(file, existingChanges)
	require.Len(t, resultMap, 1)
	require.Equal(t, 1, resultMap[0].Properties.GithubAlertNumber)

	relatedLocationChanges := map[string][]*proto.Change{
		"file1": {
			{
				StartLine: 3,
				EndLine:   3,
			},
		},
	}
	resultMap = sarif.ResultsByLocations(file, relatedLocationChanges)
	require.Len(t, resultMap, 2)
	require.Equal(t, 1, resultMap[0].Properties.GithubAlertNumber) // matches related location
	require.Equal(t, 3, resultMap[1].Properties.GithubAlertNumber) // matches actual location

}
