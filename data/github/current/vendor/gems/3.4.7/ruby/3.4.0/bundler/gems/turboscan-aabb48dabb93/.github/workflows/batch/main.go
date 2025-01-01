package main

import (
	"errors"
	"fmt"
	"go/ast"
	"go/token"
	"strings"

	"golang.org/x/tools/go/analysis"
	"golang.org/x/tools/go/analysis/passes/inspect"
	"golang.org/x/tools/go/analysis/singlechecker"
	"golang.org/x/tools/go/ast/inspector"
)

var analyzer = &analysis.Analyzer{
	Name:     "batch",
	Doc:      "Finds the transitions batched call without a \"FORCE INDEX\" parameter",
	Run:      run,
	Requires: []*analysis.Analyzer{inspect.Analyzer},
}

func New(conf any) ([]*analysis.Analyzer, error) {
	return []*analysis.Analyzer{
		analyzer,
	}, nil
}

func run(pass *analysis.Pass) (any, error) {
	inspector, ok := pass.ResultOf[inspect.Analyzer].(*inspector.Inspector)
	if !ok {
		return nil, fmt.Errorf("failed to load inspector")
	}

	nodeFilter := []ast.Node{
		(*ast.CallExpr)(nil),
	}

	inspector.Preorder(nodeFilter, func(n ast.Node) {
		call, ok := n.(*ast.CallExpr)
		if !ok {
			return
		}
		selector, ok := call.Fun.(*ast.SelectorExpr)
		if !ok {
			return
		}
		if selector.Sel.Name != "Batched" {
			return
		}
		ident, ok := selector.X.(*ast.Ident)
		if ok {
			if ident.Name == "Transitions" {
				reportIfNonIndexed(pass, n, call)
				return
			}
		}
		found := false
		for !found {
			callExpr, ok := selector.X.(*ast.CallExpr)
			if !ok {
				break
			}
			selector, ok = callExpr.Fun.(*ast.SelectorExpr)
			if ok {
				ident, ok = selector.X.(*ast.Ident)
				if !ok {
					continue
				}
				if ident.Name == "Transition" {
					found = true
				}
			}
		}
		reportIfNonIndexed(pass, n, call)
	})
	return nil, nil
}

func reportIfNonIndexed(pass *analysis.Pass, n ast.Node, call *ast.CallExpr) {
	args := call.Args
	if len(args) != 2 {
		pass.Reportf(n.Pos(), "expected two arguments in the Batched call")
		return
	}
	basicLit, ok := args[1].(*ast.BasicLit)
	if !ok {
		_, ok := args[1].(*ast.BinaryExpr)
		if !ok {
			return
		}
		constructed, err := retrieveConstructedStr(args[1])
		if err != nil {
			pass.Reportf(n.Pos(), "cannot determine the arguments value statically")
			return
		}
		// Index hints apply to SELECT and UPDATE statements. They also work with
		// multi-table DELETE statements, but not with single-table DELETE, as shown
		// later in this section.
		if !strings.Contains(strings.ToLower(constructed), "delete from") &&
			!strings.Contains(strings.ToLower(constructed), "force index") {
			pass.Reportf(n.Pos(), "Batched transition found without a forced index")
		}
		return
	}
	if basicLit.Kind != token.STRING {
		pass.Reportf(n.Pos(), "cannot determine the arguments value statically")
		return
	}
	// Index hints apply to SELECT and UPDATE statements. They also work with
	// multi-table DELETE statements, but not with single-table DELETE, as shown
	// later in this section.
	if !strings.Contains(strings.ToLower(basicLit.Value), "delete from") &&
		!strings.Contains(strings.ToLower(basicLit.Value), "force index") {
		pass.Reportf(n.Pos(), "Batched transition found without a forced index")
	}
}

func main() {
	singlechecker.Main(analyzer)
}

var ErrNonDeterministicArg = errors.New("non deterministic argument chain")

func retrieveConstructedStr(expr ast.Expr) (string, error) {
	binaryExpr, ok := expr.(*ast.BinaryExpr)
	if !ok {
		return "", ErrNonDeterministicArg
	}
	x, ok := binaryExpr.X.(*ast.BasicLit)
	if ok {
		y, ok := binaryExpr.Y.(*ast.BasicLit)
		if ok {
			return x.Value + y.Value, nil
		}
		yValue, err := retrieveConstructedStr(binaryExpr.Y)
		if err != nil {
			return "", err
		}
		return x.Value + yValue, nil
	}
	xValue, err := retrieveConstructedStr(binaryExpr.X)
	if err != nil {
		return "", err
	}
	y, ok := binaryExpr.Y.(*ast.BasicLit)
	if ok {
		return xValue + y.Value, nil
	}
	yValue, err := retrieveConstructedStr(y)
	if err != nil {
		return "", err
	}
	return xValue + yValue, nil
}
