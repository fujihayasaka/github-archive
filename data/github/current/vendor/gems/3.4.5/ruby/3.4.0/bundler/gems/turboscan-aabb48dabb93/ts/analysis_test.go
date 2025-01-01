package ts_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

func TestAnalysis_DeliveryOrigin(t *testing.T) {
	tcs := map[ts.AnalysisKey]ts.DeliveryOrigin{
		ts.ManagedAnalysisWorkflowPath:                 ts.DeliveryOrigin_MANAGED,
		"dynamic/github-actions/Debug:codeql-analysis": ts.DeliveryOrigin_DYNAMIC,
		".github/workflows/codeql.yml:analyze":         ts.DeliveryOrigin_YML,
		"(default)":                                    ts.DeliveryOrigin_API,
		"":                                             ts.DeliveryOrigin_API,
	}

	for k, v := range tcs {
		require.Equal(t, v, (&ts.Delivery{AnalysisKey: k}).OriginFromAnalysisKey(), "Test failed for '%s'", k)
	}
}
func TestAnalysis_WorkflowPath(t *testing.T) {
	empty := ts.EmptyWorkflowPath()
	tcs := map[ts.AnalysisKey]ts.WorkflowPath{
		ts.ManagedAnalysisWorkflowPath:                 empty,
		"dynamic/github-actions/Debug:codeql-analysis": empty,
		".github/workflows/codeql.yml:analyze":         ts.ToWorkflowPath([]byte(".github/workflows/codeql.yml")),
		"(default)":                                    empty,
		"":                                             empty,
		":analyze":                                     empty,
	}

	for k, v := range tcs {
		require.Equal(t, v, (&ts.Delivery{AnalysisKey: k}).WorkflowPathFromAnalysisKey(), "Test failed for '%s'", k)
	}
}
