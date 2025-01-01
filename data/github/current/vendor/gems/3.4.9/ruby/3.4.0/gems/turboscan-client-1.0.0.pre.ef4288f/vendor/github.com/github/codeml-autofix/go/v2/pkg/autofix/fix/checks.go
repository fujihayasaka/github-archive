package fix

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/github/github-telemetry-go/kvp"
	"gopkg.in/yaml.v3"
)

func newInvalidSyntaxProblem() fixdata.Problem {
	return fixdata.Problem{
		Kind:        fixdata.ProblemKind_SYNTAX_ERROR,
		Description: "invalid syntax",
	}
}

func newNoProblems() []fixdata.Problem {
	return []fixdata.Problem{}
}

// ChangeChecker compares the before and after contents of a file and returns
// new problems introduced by the change.
type ChangeChecker = func(before, after string) ([]fixdata.Problem, error)

// SourceChecker validates the contents of a single file returning detected problems.
type SourceChecker = func(contents string) ([]fixdata.Problem, error)

// Construct a source checker from a syntax checker which returns a boolean
// indicating whether the source is syntactically valid.
func syntaxChecker(
	check func(contents string) bool,
) SourceChecker {
	return func(contents string) ([]fixdata.Problem, error) {
		if !check(contents) {
			return []fixdata.Problem{newInvalidSyntaxProblem()}, nil
		} else {
			return newNoProblems(), nil
		}
	}
}

// Construct a change checkers from a source checker.
//
// We apply the change checker to the file before and after the edits, and
// return the set of problems that are present after the edits but not before.
func diffChecker(check SourceChecker) ChangeChecker {
	return func(before, after string) ([]fixdata.Problem, error) {
		problemsBefore, err := check(before)
		if err != nil {
			return nil, err
		}

		if utils.Contains(problemsBefore, newInvalidSyntaxProblem()) {
			// if we can't parse the file before the change, there's not much we
			// can do
			return newNoProblems(), nil
		}

		problemsAfter, err := check(after)
		if err != nil {
			return nil, err
		}

		problemsAfterMinusBefore := utils.Filter(problemsAfter, func(p fixdata.Problem) bool {
			return !utils.Contains(problemsBefore, p)
		})

		return problemsAfterMinusBefore, nil
	}
}

func checkJsonSyntax(contents string) bool {
	var jsonVal interface{}
	err := json.Unmarshal([]byte(contents), &jsonVal)
	isJson := err == nil
	return isJson
}

func checkYamlSyntax(contents string) bool {
	var yamlVal interface{}
	err := yaml.Unmarshal([]byte(contents), &yamlVal)
	return err == nil
}

// GetChecker constructs a change checker for a given language (based on the file extension).
//
// There are some important differences between the Go and TS Versions.
//
// Fix validation checks the before- and after-versions of a fixed alert. If fix
// validation finds an error, the fix will be marked as invalid.
//
// In the legacy typescript version, fix validation is implemented for a few
// languages only, and the implementation differs from implementation to
// implementation. Look at the `getChecker` function in `checks.ts` for the
// details.
//
// In the go version, the fix validations simply parse the before- and after
// versions (currently, no linters are implemented). Fixes where the before-version
// can be parsed, but the after-version can't are marked as invalid.
//
//   - java: The ts version does not use tree-sitter. It does a semantic check that
//     makes attempts to make sure that newly added identifiers are also used
//     before the fix. This seems to be an attempt to make sure that the LLM does
//     not refer to hallucinated identifiers.
//   - javascript: The ts version parses the code using js/ts libraries.
//     Additionally, it'll run `eslint` on the source code.
//
// Also refer to the docs/language-status.md file for the current status of the ts
// version.
func GetChecker(ctx context.Context, file string) (ChangeChecker, autofix.AutofixError) {
	isTypescript := map[string]bool{
		".js":  false,
		".cjs": false,
		".mjs": false,
		".es6": false,
		".es":  false,
		".jsx": false,
		".ts":  true,
		".cts": true,
		".mts": true,
		".tsx": true,
	}

	language := utils.LanguageFromFilename(file)
	ext := filepath.Ext(file)
	if ext == ".json" {
		return diffChecker(syntaxChecker(checkJsonSyntax)), nil
	} else if ext == ".yml" || ext == ".yaml" {
		return diffChecker(syntaxChecker(checkYamlSyntax)), nil
	} else if language == utils.LanguageActions {
		// actions files are always yml, so this should never happen
		return nil, autofix.NewLogicError(fmt.Sprintf("Requested checker for 'actions' with a file that is not YAML: %s", file))
	} else if language == utils.LanguageSwift {
		// Swift doesn't have a tree-sitter implementation yet
		enhancedctx.Logger(ctx).Warn("checker for swift not implemented", kvp.String("file", file))
		return bypassChecker(), nil
	} else if language == utils.LanguageUnknown {
		// Unknown language - log and return dummy checker
		enhancedctx.Logger(ctx).Warn("No checker for unknown language file", kvp.String("file", file))
		return bypassChecker(), nil
	} else {
		// Only use tree-sitter for languages we support
		if hasTreeSitterParser(language) {
			dialect := ""
			if language == utils.LanguageJavascript && isTypescript[ext] {
				dialect = "typescript"
			}
			return treesitterChecker(language, dialect), nil
		} else {
			enhancedctx.Logger(ctx).Warn("No tree-sitter parser for language", kvp.Any("file", file), kvp.Any("language", language))
			return bypassChecker(), nil
		}
	}
}

// Map of languages that have tree-sitter parsers
var treeParserLanguages = map[utils.Language]bool{
	utils.LanguageGo:         true,
	utils.LanguageJavascript: true,
	utils.LanguagePython:     true,
	utils.LanguageRuby:       true,
	utils.LanguageCpp:        true,
	utils.LanguageJava:       true,
	utils.LanguageCsharp:     true,
	utils.LanguageRust:       true,
}

// hasTreeSitterParser checks if we have a tree-sitter parser for the given language
func hasTreeSitterParser(language utils.Language) bool {
	return treeParserLanguages[language]
}

// bypassChecker returns a checker that always passes validation
func bypassChecker() ChangeChecker {
	return func(before, after string) ([]fixdata.Problem, error) {
		return newNoProblems(), nil
	}
}
