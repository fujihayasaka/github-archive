// The gomod2json command reads stdin, parses it as a go.mod file, and prints it as JSON.
// The JSON schema (see Result type) is ad hoc and intended only for consumption
// by the Ruby manifest adapter logic.
// On failing to parse a readable input file,
// it reports the errors as JSON and exits successfully.
//
// The Rails app requires that an executable for this program has been
// built in the application's working directory; see root Dockerfile.
//
// For an overview, see "Go module support in Dependency Graph", ../../../../docs/go-modules.md.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"

	"golang.org/x/mod/modfile"
	"golang.org/x/mod/module"
)

// JSON interface. Empty slices are emitted as null.
type (
	Result struct {
		// Exactly one of these two fields is null.
		ModFile *ModFile
		Errors  []string
	}
	ModFile struct {
		Module    module.Version
		GoVersion string
		Require   []module.Version
		Exclude   []module.Version
		Replace   [][2]module.Version
		Retract   []Retract
		Tool      []Tool
	}
	Retract struct {
		From, To  string // versions (inclusive)
		Rationale string
	}
	Tool struct {
		Path string // module path
	}
)

func main() {
	if len(os.Args) != 1 {
		log.Fatalf("usage: gomod2json < go.mod > mod.json")
	}
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		log.Fatalf("gomod2json: %v", err)
	}

	var result Result
	f, err := parseWithFallback("go.mod", input, nil)
	if err != nil {
		// Report parse errors as JSON.
		if list, ok := err.(modfile.ErrorList); ok {
			for _, err := range list {
				result.Errors = append(result.Errors, err.Error())
			}
		} else {
			result.Errors = append(result.Errors, err.Error())
		}

	} else if f.Module == nil {
		// Though mandatory, a missing module declaration is not a parse error.
		result.Errors = []string{"missing module declaration"}

	} else {
		// Convert go.mod file to JSON.
		file := &ModFile{Module: f.Module.Mod}
		if f.Go != nil {
			file.GoVersion = f.Go.Version
		}
		for _, x := range f.Require {
			// (discard x.Indirect)
			file.Require = append(file.Require, x.Mod)
		}
		for _, x := range f.Exclude {
			file.Exclude = append(file.Exclude, x.Mod)
		}
		for _, x := range f.Replace {
			file.Replace = append(file.Replace, [2]module.Version{x.Old, x.New})
		}
		for _, x := range f.Retract {
			file.Retract = append(file.Retract,
				Retract{From: x.Low, To: x.High, Rationale: x.Rationale})
		}
		for _, x := range f.Tool {
			file.Tool = append(file.Tool, Tool{Path: x.Path})
		}
		result.ModFile = file
	}

	output, err := json.Marshal(result)
	if err != nil {
		log.Fatalf("internal error: %v", err)
	}
	fmt.Printf("%s\n", output)
}

// parseWithFallback attempts to parse with modfile.Parse. If that fails,
// it tries modfile.ParseLax as a fallback.
func parseWithFallback(file string, data []byte, fix modfile.VersionFixer) (*modfile.File, error) {
	if f, err := modfile.Parse(file, data, fix); err == nil {
		return f, nil
	}
	return modfile.ParseLax(file, data, fix)
}
