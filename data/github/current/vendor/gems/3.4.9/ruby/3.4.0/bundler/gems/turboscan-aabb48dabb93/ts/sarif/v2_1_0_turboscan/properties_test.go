package v210turboscan_test

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts/sarif/samples"
)

func TestCodeQLConfigSummary(t *testing.T) {
	s := samples.RequireSARIF(t, "testdata/codeql_config.sarif")
	require.Len(t, s.Runs, 1)
	props := s.Runs[0].Properties
	require.NotNil(t, props)
	summary := props.CodeqlConfigSummary
	require.NotNil(t, summary)
	require.True(t, summary.DisableDefaultQueries)
	require.Len(t, summary.Queries, 3)

	require.Equal(t, "./path/to/query.ql", summary.Queries[0].Uses)
	require.Equal(t, "localQuery", summary.Queries[0].Type)

	require.Equal(t, "security-extended", summary.Queries[1].Uses)
	require.Equal(t, "builtinSuite", summary.Queries[1].Type)

	require.Equal(t, "github/mona/my/awesome/query/suite.qls@main", summary.Queries[2].Uses)
	require.Equal(t, "externalRepo", summary.Queries[2].Type)
}
