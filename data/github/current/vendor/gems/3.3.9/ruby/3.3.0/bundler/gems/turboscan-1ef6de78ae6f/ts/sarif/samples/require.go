// Package samples provides functions for loading sample SARIF files in
// tests. See ts/sarif/testdata for some examples.
package samples

import (
	"path"
	"runtime"
	"testing"

	"github.com/github/turboscan/ts/sarif"
	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/stretchr/testify/require"
)

// RequireSARIF opens and parses the given SARIF file and returns the
// parsed data. Fails and terminates the test if the file could not be
// read or parsed.
func RequireSARIF(t *testing.T, filepath string) *v2_1_0.SARIF {
	t.Helper()
	_, filename, _, _ := runtime.Caller(0)
	filepath = path.Join(path.Dir(filename), "..", filepath)
	sarif, err := sarif.FromFile(filepath)
	require.NoError(t, err, "Cannot load sample SARIF")
	return sarif
}
