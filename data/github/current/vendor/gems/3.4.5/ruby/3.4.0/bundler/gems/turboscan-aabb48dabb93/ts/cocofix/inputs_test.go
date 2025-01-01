package cocofix

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

func Test_buildSarifInput(t *testing.T) {
	defaultRef := []byte("refs/heads/main")
	analysis := &ts.Analysis{ID: 1, RepositoryID: 1, SourceRepositoryID: 1, Ref: defaultRef}
	alertNo := uint32(1)
	la := &ts.LogicalAlert{
		ID:              ts.LogicalAlertID(1),
		Number:          alertNo,
		SarifIdentifier: "js/reflected-xss",
		FilePath:        "foo/bar.js",
		Region: ts.Region{
			StartLine:   1,
			StartColumn: 5,
			EndColumn:   10,
			EndLine:     1,
		},
	}
	pa := &ts.PhysicalAlert{
		ID:           ts.PhysicalAlertID(1),
		Analysis:     analysis,
		LogicalAlert: la,
		RepositoryID: ts.RepositoryEID(1),
	}

	c := &CocofixRunner{}

	tool := ToolInfo{}
	res, paths, err := c.buildSarifInput(context.Background(), &tool, pa, SarifBuilderOpts{})
	require.NoError(t, err)
	require.NotEmpty(t, res)
	require.Len(t, paths, 1)
}
