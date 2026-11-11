package featureflags

import (
	"go/ast"
	"go/parser"
	"go/token"
	"path/filepath"
	"runtime"
	"sort"
	"testing"

	"github.com/stretchr/testify/require"
)

// TestFeatureFlagConstants_AlphabeticalOrder ensures feature flag constants are sorted alphabetically
// by constant name to reduce merge conflicts and improve readability. This test parses the featureflags.go
// source file and checks that constants are declared in alphabetical order.
func TestFeatureFlagConstants_AlphabeticalOrder(t *testing.T) {
	// Get the path to the featureflags.go file relative to this test file
	_, currentFile, _, ok := runtime.Caller(0)
	require.True(t, ok, "failed to get current file path")

	featureflagsGoPath := filepath.Join(filepath.Dir(currentFile), "featureflags.go")

	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, featureflagsGoPath, nil, parser.ParseComments)
	require.NoError(t, err, "failed to parse featureflags.go")

	var constNames []string
	for _, decl := range f.Decls {
		genDecl, ok := decl.(*ast.GenDecl)
		if !ok || genDecl.Tok != token.CONST {
			continue
		}

		// Skip const blocks with only one declaration
		if len(genDecl.Specs) <= 1 {
			continue
		}

		for _, spec := range genDecl.Specs {
			valueSpec, ok := spec.(*ast.ValueSpec)
			if !ok {
				continue
			}
			for _, name := range valueSpec.Names {
				constNames = append(constNames, name.Name)
			}
		}
	}

	require.NotEmpty(t, constNames, "no const blocks found in featureflags.go")

	// Check if constants are sorted
	if !sort.StringsAreSorted(constNames) {
		sorted := make([]string, len(constNames))
		copy(sorted, constNames)
		sort.Strings(sorted)

		for i := range constNames {
			if constNames[i] != sorted[i] {
				t.Errorf("feature flag constants must be sorted alphabetically by constant name: %q is out of order (expected %q at position %d)", constNames[i], sorted[i], i)
				break
			}
		}
	}
}
