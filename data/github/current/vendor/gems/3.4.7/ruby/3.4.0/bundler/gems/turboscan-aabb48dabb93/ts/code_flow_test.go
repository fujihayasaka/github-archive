package ts

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestUnmarshal(t *testing.T) {
	// can successfully unmarshal a message with too few columns, leaving missing values as zero
	var codeFlow CodeFlow
	require.NoError(t, json.Unmarshal([]byte(`[1, "filepath"]`), &codeFlow))
	require.Equal(t, uint32(1), codeFlow.CodeFlowIndex)
	require.Equal(t, "filepath", codeFlow.FilePath)
	require.Nil(t, codeFlow.Message)
}

func TestGroupByCodeFlowIndex(t *testing.T) {
	require.Equal(t, []CodeFlows{
		{
			CodeFlow{
				CodeFlowIndex:   1,
				ThreadFlowIndex: 1,
				StepIndex:       1,
			},
			CodeFlow{
				CodeFlowIndex:   1,
				ThreadFlowIndex: 1,
				StepIndex:       2,
			},
		},
		{
			CodeFlow{
				CodeFlowIndex:   2,
				ThreadFlowIndex: 1,
				StepIndex:       1,
			},
		},
	}, GroupByCodeFlowIndex(CodeFlows{
		CodeFlow{
			CodeFlowIndex:   1,
			ThreadFlowIndex: 1,
			StepIndex:       1,
		},
		CodeFlow{
			CodeFlowIndex:   1,
			ThreadFlowIndex: 1,
			StepIndex:       2,
		},
		CodeFlow{
			CodeFlowIndex:   2,
			ThreadFlowIndex: 1,
			StepIndex:       1,
		},
	}))
}

func ptrTo(v string) *string {
	return &v
}

func TestSort(t *testing.T) {
	message := ptrTo("message")

	locations := CodeFlows{
		// CodeFlow 1 with 2 ThreadFlows
		CodeFlow{
			CodeFlowIndex:   10,
			ThreadFlowIndex: 0,
			StepIndex:       10,
			Message:         message,
			FilePath:        "file1",
			Region: Region{
				StartLine:   1,
				EndLine:     2,
				StartColumn: 1,
				EndColumn:   2,
			},
		},
		CodeFlow{
			CodeFlowIndex:   5,
			ThreadFlowIndex: 0,
			StepIndex:       10,
			Message:         message,
			FilePath:        "file2",
			Region: Region{
				StartLine:   1,
				EndLine:     2,
				StartColumn: 1,
				EndColumn:   2,
			},
		},
		CodeFlow{
			CodeFlowIndex:   10,
			ThreadFlowIndex: 0,
			StepIndex:       1,
			Message:         message,
			FilePath:        "file1",
			Region: Region{
				StartLine:   2,
				EndLine:     2,
				StartColumn: 2,
				EndColumn:   2,
			},
		},
		// CodeFlow 2 with 1 ThreadFlow
		CodeFlow{
			CodeFlowIndex:   2,
			ThreadFlowIndex: 0,
			StepIndex:       10,
			Message:         message,
			FilePath:        "file3",
			Region: Region{
				StartLine:   1,
				EndLine:     2,
				StartColumn: 1,
				EndColumn:   2,
			},
		},
		CodeFlow{
			CodeFlowIndex:   1,
			ThreadFlowIndex: 1,
			StepIndex:       5,
			Message:         message,
			FilePath:        "file4",
			Region: Region{
				StartLine:   1,
				EndLine:     2,
				StartColumn: 1,
				EndColumn:   2,
			},
		},
	}

	actual := SortCodeFlows(locations)

	require.Equal(t, CodeFlows{
		{"file4", Region{1, 2, 1, 2}, message, 1, 1, 5},
		{"file3", Region{1, 2, 1, 2}, message, 2, 0, 10},
		{"file2", Region{1, 2, 1, 2}, message, 5, 0, 10},
		{"file1", Region{2, 2, 2, 2}, message, 10, 0, 1},
		{"file1", Region{1, 2, 1, 2}, message, 10, 0, 10},
	}, actual)
}
