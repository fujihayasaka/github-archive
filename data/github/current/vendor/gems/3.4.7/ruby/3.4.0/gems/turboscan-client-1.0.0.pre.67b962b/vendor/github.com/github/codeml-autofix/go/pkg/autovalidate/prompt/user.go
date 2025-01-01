package prompt

import (
	"slices"
	"strings"
	"text/template"

	"github.com/github/codeml-autofix/go/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/pkg/autovalidate/fix"
	"github.com/github/codeml-autofix/go/pkg/autovalidate/model"
	"github.com/github/codeml-autofix/go/pkg/autovalidate/replacement_block"
	"github.com/github/codeml-autofix/go/pkg/autovalidate/utils"
)

type File struct {
	Path    string
	Content string
}

type CodeSnippet struct {
	File    File
	Content string
}

type ReplacementBlock struct {
	File             string
	OriginalLines    string
	ReplacementLines string
}

type UserPromptArguments struct {
	Alert                fixdata.RespAlert
	CodeSnippets         []CodeSnippet
	UseReplacementBlocks bool
	Diffs                []fixdata.Diff
}

func prependLineNumbers(code string) string {
	return utils.PrependLineNumbersWithStartLine(code, 1)
}

func getAlertType(alert fixdata.RespAlert) string {
	components := strings.Split(alert.RuleId, "/")
	last_component := components[len(components)-1]
	return strings.ReplaceAll(last_component, "-", " ")
}

func BuildUserPrompt(fix *fix.Fix, codeBase codebase.VirtualCodebase, modelParameters *model.ModelParameters, useReplacementBlocks bool) (string, error) {

	relevantPaths := make([]string, len(fix.Diffs))

	for i, diff := range fix.Diffs {
		relevantPaths[i] = diff.Path
	}

	// If the alert path is not already in the list of relevant paths, add it
	if !slices.Contains(relevantPaths, fix.Alert.Location.Path) {
		// TODO: add logging here that the alert path is not in the list of relevant paths
		relevantPaths = append(relevantPaths, fix.Alert.Location.Path)
	}

	relevantFiles := make([]File, len(relevantPaths))

	for i, path := range relevantPaths {
		contents, err := codeBase.ReadContents(path)
		if err != nil {
			return "", err
		}
		relevantFiles[i] = File{
			Path:    path,
			Content: contents,
		}
	}

	maxCodeTokens := modelParameters.MaxPromptTokens - modelParameters.ReservedPromptTokens
	maxCodeChars := maxCodeTokens * modelParameters.CharactersPerToken

	// This logic follows the same logic as in the Python version, which computes
	// the total number of characters before prepending line numbers.
	totalCodeChars := 0
	for _, file := range relevantFiles {
		totalCodeChars += len(file.Content)
	}

	codeSnippets := make([]CodeSnippet, len(relevantFiles))
	overflow := totalCodeChars - maxCodeChars
	if overflow > 0 {
		// TODO: add logging here that the prompt is too long
		perFileOverflow := overflow / len(relevantFiles)
		for i := range relevantFiles {
			codeSnippets[i].File = relevantFiles[i]
			codeSnippets[i].Content = prependLineNumbers(relevantFiles[i].Content)[:len(relevantFiles[i].Content)-perFileOverflow]
		}
	} else {
		for i := range relevantFiles {
			codeSnippets[i].File = relevantFiles[i]
			codeSnippets[i].Content = prependLineNumbers(relevantFiles[i].Content)
		}
	}

	promptArguments := UserPromptArguments{
		Alert:                fix.Alert,
		CodeSnippets:         codeSnippets,
		UseReplacementBlocks: useReplacementBlocks,
		Diffs:                fix.Diffs,
	}

	return ExecuteTemplate("user.md", promptArguments, template.FuncMap{
		"getAlertType":                   getAlertType,
		"convertDiffToReplacementBlocks": replacement_block.FromUnifiedDiff,
	})
}
