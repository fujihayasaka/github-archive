package cocofix

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

func testdataPath(t *testing.T) string {
	t.Helper()
	cwd, err := os.Getwd()
	require.NoError(t, err)
	tdPath := filepath.Join(cwd, "testdata")
	return tdPath
}

func readTestFile(t *testing.T, name string) []byte {
	t.Helper()
	content, err := os.ReadFile(filepath.Join(testdataPath(t), name))
	require.NoError(t, err)
	return content
}

func mockLogicalAlert(sarifIdentifier string, tool string) *ts.LogicalAlert {
	return &ts.LogicalAlert{
		SarifIdentifier: sarifIdentifier,
		Rule: &ts.Rule{
			Tool: &ts.Tool{
				CanonicalName: ts.ToToolName(tool),
			},
		},
	}
}
