package ts

import (
	"go/ast"
	"go/parser"
	"go/token"
	"strconv"
	"testing"

	"github.com/stretchr/testify/require"
)

func getDefinedAnalysisMessageKeys(t *testing.T) []analysisMessageKey {
	t.Helper()

	var keys []analysisMessageKey

	// find all the possible values of AnalysisMessageKey declared in ts/analysis_message.go
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, "analysis_message.go", nil, parser.ParseComments)
	require.NoError(t, err)
	for _, decl := range f.Decls {
		if node, ok := decl.(*ast.GenDecl); ok {
			// look for constants
			if node.Tok == token.CONST {
				for _, spec := range node.Specs {
					if v, ok := spec.(*ast.ValueSpec); ok {
						if i, ok := v.Type.(*ast.Ident); ok {
							// find constants of type AnalysisMessageKey
							if i.Name == "analysisMessageKey" {
								for _, val := range v.Values {
									// each value will be a quoted string
									if l, ok := val.(*ast.BasicLit); ok {
										key, err := strconv.Unquote(l.Value)
										require.NoError(t, err)
										keys = append(keys, analysisMessageKey(key))
									}
								}
							}
						}
					}
				}
			}
		}
	}

	require.NotEmpty(t, keys)

	return keys
}

func TestAnalysisMessageDeclarations(t *testing.T) {
	for _, key := range getDefinedAnalysisMessageKeys(t) {
		decl := GetAnalysisMessageDecl(key)

		require.Equal(t, key, decl.Key())
		require.NoError(t, decl.Verify(), "verification error for %s", key)
	}
}
