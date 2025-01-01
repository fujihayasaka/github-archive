package ts

import (
	"fmt"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/stretchr/testify/require"
)

func TestExtractFilePaths(t *testing.T) {
	pa := newPhysicalAlert("index.js")
	pa.CodeFlowsDocument = &CodeFlowsDocument{
		RepositoryID: 1,
		Document: CodeFlows{
			newCodeFlow(0, "index.js"),
			newCodeFlow(0, "lib/hello.js"),
		},
	}
	id := CodeFlowsDocumentID(123)
	pa.CodeFlowsDocumentID = &id
	filePaths, err := pa.ExtractFilePaths()
	require.NoError(t, err)
	require.NotEmpty(t, filePaths)
	require.Equal(t, 2, len(filePaths))
	expected := []string{
		"index.js",
		"lib/hello.js",
	}
	for _, filePath := range filePaths {
		require.Contains(t, expected, filePath)
	}
}

func TestExtractFilePathsWithNoCodeFlowsGiven(t *testing.T) {
	pa := newPhysicalAlert("index.js")
	pa.CodeFlowsDocument = &CodeFlowsDocument{
		RepositoryID: 1,
		Document: CodeFlows{
			newCodeFlow(0, "index.js"),
			newCodeFlow(0, "lib/hello.js"),
		},
	}
	pa.LogicalAlert = &LogicalAlert{
		FilePath: "index.js",
	}
	filePaths, err := pa.ExtractFilePaths()
	require.NoError(t, err)
	require.NotEmpty(t, filePaths)
	require.Equal(t, 1, len(filePaths))
	require.Equal(t, "index.js", filePaths[0])
}

func newCodeFlow(i uint32, filePath string) CodeFlow {
	message := fmt.Sprintf("some message (%d)", i)
	return CodeFlow{
		FilePath: filePath,
		Region: Region{
			StartLine:   1 + i,
			EndLine:     100,
			StartColumn: 4 + i,
			EndColumn:   10,
		},
		Message:         &message,
		CodeFlowIndex:   i,
		ThreadFlowIndex: i,
		StepIndex:       i,
	}
}

func newPhysicalAlert(filePath string) PhysicalAlert {
	now := sqltime.Now()
	return PhysicalAlert{
		RepositoryID: 1,
		FilePath:     filePath,
		Analysis: &Analysis{
			CommitOid: "xxx",
			Ref:       []byte("refs/heads/ref1"),
		},
		LastStateChangeAt: now,
	}
}
