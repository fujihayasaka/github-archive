package root

import (
	"go/ast"
	"go/parser"
	"go/token"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestBasic(t *testing.T) {
	w := httptest.NewRecorder()
	r := httptest.NewRequest("POST", "http://localhost:8888/twirp/github.turboscan.Results/GetCounts", strings.NewReader(`{}`))
	r.Header.Set("Content-Type", "application/json")
	handler("../../../ruby/spec/fixtures/vcr_cassettes/code-scanning").ServeHTTP(w, r)
	require.Equal(t, http.StatusOK, w.Code, w.Body)
	require.Contains(t, w.Body.String(), "analysis_exists")
	require.Contains(t, w.Body.String(), "open_count")
}

type VisitorFunc func(node ast.Node)

func (v VisitorFunc) Visit(node ast.Node) ast.Visitor {
	v(node)
	return v
}

func TestCassettes(t *testing.T) {
	var fset token.FileSet
	pkgs, err := parser.ParseDir(&fset, "services", nil, parser.ParseComments)
	require.NoError(t, err)

	for _, pkg := range pkgs {
		for _, file := range pkg.Files {
			for _, decl := range file.Decls {
				ast.Walk(VisitorFunc(func(node ast.Node) {
					if v, ok := node.(*ast.BasicLit); ok {
						if v.Kind == token.STRING {
							unquoted, err := strconv.Unquote(v.Value)
							require.NoError(t, err)
							if strings.HasSuffix(unquoted, ".yml") {
								path := filepath.Join("../../..", DefaultCassettePath, unquoted)
								require.FileExists(t, path)
							}
						}
					}
				}), decl)
			}
		}
	}
}
