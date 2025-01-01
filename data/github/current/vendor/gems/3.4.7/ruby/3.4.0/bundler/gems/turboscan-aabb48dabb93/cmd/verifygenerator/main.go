// Command verifygenerator uses codegen to create functions that efficiently test if two structs are equivalent.
// This was added to speed up an original implementation based on gocmp. Due to the cost of reflection
// validation of our archival process was taking a disproportionally large amount of the runtime.
// Generating code to do the equality checks gave an 82% speedup on large documents.
package main

import (
	"bytes"
	"embed"
	"flag"
	"fmt"
	"go/ast"
	"go/format"
	"go/token"
	"go/types"
	"io"
	"os"
	"reflect"
	"strconv"
	"strings"
	"text/template"

	"github.com/pkg/errors"

	"golang.org/x/tools/go/packages"

	"golang.org/x/tools/imports"
)

//go:embed templates/*
var fs embed.FS

var tmpl = template.Must(template.New("validategenerator").ParseFS(fs, "templates/*"))

// getIdent returns the ident for a struct field
func getIdent(node ast.Expr) *ast.Ident {
	if v, ok := node.(*ast.StarExpr); ok {
		node = v.X
	}
	if v, ok := node.(*ast.SelectorExpr); ok {
		node = v.X
	}
	if v, ok := node.(*ast.IndexExpr); ok {
		node = v.X
	}
	return node.(*ast.Ident)
}

type Struct struct {
	Name         string
	Fields       []Field
	BeforeVerify bool
	Receiver     string
}

type Field struct {
	Name      string
	Type      string
	Compare   string
	IsPointer bool
	IsMap     bool
	IsArray   bool
}

type tmplArgs struct {
	Package string
	Structs map[string]*Struct
}

// getRecv returns the type name of the receiver for a method
func getRecv(o types.Object) *types.TypeName {
	if s, ok := o.Type().(*types.Signature); ok {
		if n, ok := s.Recv().Type().(*types.Named); ok {
			return n.Obj()
		}
	}
	return nil
}

// getField converts ast information into a struct that can be rendered by a verifygenerator template.
func getField(name *ast.Ident, fieldType types.Type, targetSet map[string]struct{}) Field {
	isPointer := findType[*types.Pointer](fieldType) != nil

	guard := "%s"
	if isPointer {
		// check the pointers are not nil, if they are equal we can succeed
		guard = "%%[1]s != %%[2]s && (%%[1]s == nil || %%[2]s == nil || %s)"
	}

	underlyingType := underlyingTypeOf(fieldType)

	var useVerify bool
	// check if we will be generating a Verify method for this type and if so, use it
	if t, ok := underlyingType.(*types.Named); ok {
		_, useVerify = targetSet[t.Obj().Name()]
	}

	equal, _, _ := types.LookupFieldOrMethod(underlyingType, true, nil, "Equal")

	verify, _, _ := types.LookupFieldOrMethod(underlyingType, true, nil, "Verify")

	var compare string
	a, b := "%[1]s", "%[2]s"

	switch {
	case !useVerify && equal != nil:
		recv := getRecv(equal)

		if recv != nil && recv.Type() != underlyingType {
			// handle types where Equal is on an embedded struct, e.g: sqltime.Time
			// a.Equal((b).Time)
			b = fmt.Sprintf("(%s).%s", b, recv.Name())
		}

		compare = fmt.Sprintf("errors.New(%q); %s", "values not Equal for "+name.Name, fmt.Sprintf(guard, fmt.Sprintf("!%s.Equal(%s)", a, b)))
	case !useVerify && types.Comparable(underlyingType) && verify == nil:
		if isPointer {
			a = "*" + a
			b = "*" + b
		}
		compare = fmt.Sprintf("errors.New(%q); %s", "values not equal for "+name.Name, fmt.Sprintf(guard, fmt.Sprintf("%s != %s", a, b)))
	default:
		if !isPointer {
			b = "&" + b
		}
		compare = fmt.Sprintf("%s.Verify(%s); err != nil", a, b)
	}

	isMap := findType[*types.Map](fieldType) != nil
	isArray := findType[*types.Slice](fieldType) != nil

	return Field{
		Name:      name.Name,
		Type:      fieldType.String(),
		Compare:   compare,
		IsPointer: isPointer,
		IsMap:     isMap,
		IsArray:   isArray,
	}
}

// hasElem matches any container types like maps, pointers or slices
type hasElem interface {
	Elem() types.Type
}

// findType will search this type for T, de-referencing pointers or checking container contents
func findType[T types.Type](t types.Type) types.Type {
	if tt, ok := t.(T); ok {
		return tt
	}
	switch ty := t.(type) {
	case hasElem:
		return findType[T](ty.Elem())
	case *types.Named:
		return findType[T](ty.Underlying())
	}
	return nil
}

// underlyingTypeOf finds the true type of T after following all type definitions
func underlyingTypeOf(t types.Type) types.Type {
	switch ty := t.(type) {
	case hasElem:
		return underlyingTypeOf(ty.Elem())
	case *types.Named:
		u := ty.Underlying()
		// if the underlying type is a struct return the name of the struct, not the struct itself
		if _, ok := u.(*types.Struct); ok {
			return t
		}
		return underlyingTypeOf(u)
	}
	return t
}

// generate scans through the AST for targets and creates Verify functions that will return an error
// if one struct is not equal to another.
func generate(dir, pattern string, targets []string) ([]byte, error) {
	const mode packages.LoadMode = packages.NeedName |
		packages.NeedTypes |
		packages.NeedSyntax |
		packages.NeedTypesInfo

	fset := token.NewFileSet()

	cfg := &packages.Config{Fset: fset, Mode: mode, Dir: dir}

	pkgs, err := packages.Load(cfg, pattern)
	if err != nil {
		return nil, err
	}

	args := tmplArgs{
		Package: "ts",
		Structs: make(map[string]*Struct),
	}

	targetSet := make(map[string]struct{}, len(targets))
	for _, target := range targets {
		targetSet[target] = struct{}{}
	}

	for _, pkg := range pkgs {
		if len(pkg.Errors) > 0 {
			for _, e := range pkg.Errors {
				fmt.Fprintf(os.Stderr, "Error: %s\n", e)
			}
			os.Exit(1)
		}
		if pkg.Name != "ts" {
			continue
		}

		for _, root := range pkg.Syntax {
			for _, node := range root.Decls {
				if v, ok := node.(*ast.GenDecl); ok {
					for _, spec := range v.Specs {
						if typeSpec, ok := spec.(*ast.TypeSpec); ok {
							if _, ok := targetSet[typeSpec.Name.Name]; !ok {
								continue
							}

							s := &Struct{Name: typeSpec.Name.Name, Receiver: strings.ToLower(typeSpec.Name.Name[:1])}

							if structType, ok := typeSpec.Type.(*ast.StructType); ok {
								for _, field := range structType.Fields.List {
									if field.Tag != nil {
										tag, err := strconv.Unquote(field.Tag.Value)
										if err != nil {
											return nil, err
										}
										if reflect.StructTag(tag).Get("verify") == "ignore" {
											continue
										}
									}

									fieldType := pkg.TypesInfo.Types[field.Type].Type

									for _, name := range field.Names {
										s.Fields = append(s.Fields, getField(name, fieldType, targetSet))
									}
								}
							}

							args.Structs[s.Name] = s
						}
					}
				}
			}

			// scan the AST for any types with BeforeVerify methods
			// we should call this method to transform the object before we compare it
			for _, node := range root.Decls {
				if v, ok := node.(*ast.FuncDecl); ok {
					if v.Recv != nil {
						for _, recv := range v.Recv.List {
							i := getIdent(recv.Type)
							if s, ok := args.Structs[i.Name]; ok {
								if v.Name.Name != "Verify" {
									for _, name := range recv.Names {
										s.Receiver = name.Name
									}
								}
								if v.Name.Name == "beforeVerify" {
									s.BeforeVerify = true
								}
							}
						}
					}
				}
			}
		}
	}

	var buf bytes.Buffer

	// pre-allocate 16kb for the rendered template
	buf.Grow(16 * 1024)

	if err := tmpl.ExecuteTemplate(&buf, "package.tmpl", args); err != nil {
		return nil, errors.Wrap(err, "failed to execute template")
	}

	// go fmt
	formatted, err := format.Source(buf.Bytes())
	if err != nil {
		return nil, errors.Wrap(err, "failed to format source")
	}

	// goimports
	return imports.Process("", formatted, nil)
}

func main() {
	var outputPath, dir string
	flag.StringVar(&outputPath, "w", "", "write the generated file instead of sending it to stdout")
	flag.StringVar(&dir, "d", ".", "working directory")
	flag.Parse()
	pattern := flag.Arg(0)
	targets := flag.Args()[1:]

	data, err := generate(dir, pattern, targets)
	if err != nil {
		panic(err)
	}
	if outputPath != "" {
		err = os.WriteFile(outputPath, data, 0o644)
	} else {
		_, err = io.Copy(os.Stdout, bytes.NewReader(data))
	}
	if err != nil {
		panic(err)
	}
}
