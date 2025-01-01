package processor

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/sarif/samples"
	"github.com/stretchr/testify/require"
)

func TestFindOrCreateConfiguration(t *testing.T) {
	ctx, db, p := setUp(t)

	sarif := samples.RequireSARIF(t, "../sarif/testdata/example_multi_tool.sarif")

	require.NoError(t, processResultsForRun(ctx, sarif.Runs[0], p))

	dbtest.RequireCount(t, 1, db.Model(&ts.Configuration{}))

	require.NoError(t, processResultsForRun(ctx, sarif.Runs[1], p))

	dbtest.RequireCount(t, 2, db.Model(&ts.Configuration{}))
}
