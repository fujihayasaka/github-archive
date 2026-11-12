package goerrorslint

import (
	"go/ast"

	"github.com/golangci/plugin-module-register/register"
	"golang.org/x/tools/go/analysis"
)

func init() {
	register.Plugin("goerrorslint", New)

}

func New(settings any) (register.LinterPlugin, error) {
	return &Plugin{}, nil
}

type Plugin struct{}

func (p *Plugin) BuildAnalyzers() ([]*analysis.Analyzer, error) {
	return []*analysis.Analyzer{
		{
			Name: "goerrorslint",
			Doc:  "Checks to ensure use of error wrapping functions from the goerrors package",
			Run:  run,
		},
	}, nil
}

func (p *Plugin) GetLoadMode() string {
	return register.LoadModeSyntax
}

const (
	errorfFound = "Please use goerrors.Errorf instead of fmt.Errorf in order to ensure proper stacktracing"
	newFound    = "Please use goerrors.New instead of errors.New in order to ensure proper stacktracing"
)

func run(pass *analysis.Pass) (any, error) {
	for _, f := range pass.Files {
		pkgFmt := ""
		pkgErrors := ""

		for node := range ast.Preorder(f) {
			if pkgFmt != "" && pkgErrors != "" {
				break
			}

			importSpec, ok := node.(*ast.ImportSpec)
			if !ok {
				continue
			}

			if importSpec.Path.Value == "\"fmt\"" {
				if importSpec.Name != nil {
					pkgFmt = importSpec.Name.Name
					continue
				}

				pkgFmt = "fmt"
				continue
			}

			if importSpec.Path.Value == "\"errors\"" {
				if importSpec.Name != nil {
					pkgErrors = importSpec.Name.Name
					continue
				}

				pkgErrors = "errors"
				continue
			}
		}

		if pkgFmt == "" && pkgErrors == "" {
			continue
		}

		// Range manually over the top level decls
		for _, decl := range f.Decls {
			// We only want to scan inside functions, this avoids scanning errors defined in var blocks and the like that shouldn't have stack traces attached.
			_, ok := decl.(*ast.FuncDecl)
			if !ok {
				continue
			}

			for node := range ast.Preorder(decl) {
				call, ok := node.(*ast.CallExpr)
				if !ok {
					// Not a function call node
					continue
				}

				selector, ok := call.Fun.(*ast.SelectorExpr)
				if !ok {
					// Function exists in this package
					continue
				}

				x, ok := selector.X.(*ast.Ident)
				if !ok {
					// ??
					continue
				}

				if pkgFmt != "" && x.Name == pkgFmt {
					if selector.Sel.Name == "Errorf" {
						pass.Report(analysis.Diagnostic{
							Pos:     node.Pos(),
							Message: errorfFound,
							SuggestedFixes: []analysis.SuggestedFix{{
								Message: "change \"fmt\" to \"goerrors\"",
								TextEdits: []analysis.TextEdit{{
									Pos:     node.Pos(),
									End:     node.Pos() + 3,
									NewText: []byte("goerrors"),
								}},
							}},
						})
					}

					continue
				}

				if pkgErrors != "" && x.Name == pkgErrors {
					if selector.Sel.Name == "New" {
						pass.Report(analysis.Diagnostic{
							Pos:     node.Pos(),
							Message: newFound,
							SuggestedFixes: []analysis.SuggestedFix{{
								Message: "change \"errors\" to \"goerrors\"",
								TextEdits: []analysis.TextEdit{{
									Pos:     node.Pos(),
									End:     node.Pos() + 6,
									NewText: []byte("goerrors"),
								}},
							}},
						})
					}
				}
			}
		}
	}

	return nil, nil
}
