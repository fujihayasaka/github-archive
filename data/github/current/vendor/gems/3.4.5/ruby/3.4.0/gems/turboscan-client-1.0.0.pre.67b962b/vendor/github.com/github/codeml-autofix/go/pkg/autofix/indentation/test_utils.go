package indentation

import (
	"fmt"
	"testing"

	"github.com/github/codeml-autofix/go/pkg/autofix/codebase"
	"github.com/stretchr/testify/require"
)

var indentationTreeTestFileIndex = 0

func MkFileFromContents(t *testing.T, contents string) codebase.File {
	t.Helper()

	fileName := fmt.Sprintf("file%d", indentationTreeTestFileIndex)
	indentationTreeTestFileIndex += 1

	var err error
	codebase, err := codebase.NewLocalCodebase("/tmp")
	require.NoError(t, err)
	err = codebase.WriteContents(fileName, contents)
	require.NoError(t, err)
	file, err := codebase.GetFile(fileName)
	require.NoError(t, err)
	return file
}
