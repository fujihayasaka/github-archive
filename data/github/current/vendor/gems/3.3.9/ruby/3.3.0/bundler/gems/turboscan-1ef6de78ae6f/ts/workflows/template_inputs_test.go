package workflows_test

import (
	"testing"

	"github.com/github/turboscan/ts/workflows"
	"github.com/stretchr/testify/require"
)

func TestEmptyInputs(t *testing.T) {
	i := workflows.TemplateInputs{}
	require.False(t, i.IncludeValidation())
	require.Equal(t, `"" # Default query suite`, i.Queries())
}

func TestExtendedQueryInputs(t *testing.T) {
	i := workflows.TemplateInputs{
		ExtendedQuerySuite: true,
	}
	require.Equal(t, "security-extended", i.Queries())
}

func TestDefaultQueryInputs(t *testing.T) {
	i := workflows.TemplateInputs{
		ExtendedQuerySuite: false,
	}
	require.Equal(t, `"" # Default query suite`, i.Queries())
}

func TestDefaultRunnerLabels(t *testing.T) {
	require.Equal(t, `ubuntu-latest`, workflows.TemplateInputs{}.GetRunnerLabels())
}
