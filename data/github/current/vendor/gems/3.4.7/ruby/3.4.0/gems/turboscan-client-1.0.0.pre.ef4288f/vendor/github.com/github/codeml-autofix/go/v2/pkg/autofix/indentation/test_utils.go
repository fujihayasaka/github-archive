package indentation

import (
	"fmt"
	"os"
	"testing"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/stretchr/testify/require"
)

var indentationTreeTestFileIndex = 0

// MkFileFromContents creates a temporary file with the given contents for indentation tests.
func MkFileFromContents(t *testing.T, contents string) codebase.File {
	t.Helper()

	fileName := fmt.Sprintf("file%d", indentationTreeTestFileIndex)
	indentationTreeTestFileIndex += 1

	var err error
	codebase, err := codebase.NewLocalCodebase(os.TempDir())
	require.NoError(t, err)
	err = codebase.WriteContents(fileName, contents)
	require.NoError(t, err)
	file, err := codebase.GetFile(utils.NormalizeFilePathForPlatform(fileName))
	require.NoError(t, err)
	return file
}
