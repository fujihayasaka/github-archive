//nolint:revive,stylecheck // Adding comments for the sake of adding comments is not useful
package prompt

import (
	"slices"
	"strings"
	"text/template"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/fix"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/model"
	"github.com/github/codeml-autofix/go/v2/pkg/autovalidate/replacement_block"
	"github.com/pkg/errors"
)

type file struct {
	Path    string
	Content string
}

type codeSnippet struct {
	File    file
	Content string
}

type userPromptArguments struct {
	Alert                fixdata.RespAlert
	CodeSnippets         []codeSnippet
	UseReplacementBlocks bool
	Diffs                []fixdata.Diff
	AlertSnippet         string
}

func getAlertType(alert fixdata.RespAlert) string {
	components := strings.Split(alert.RuleId, "/")
	lastComponent := components[len(components)-1]
	return strings.ReplaceAll(lastComponent, "-", " ")
}

func BuildUserPrompt(fixData *fix.Fix, codeBase codebase.VirtualCodebase, modelParameters *model.ModelParameters, useReplacementBlocks bool) (string, error) {
	relevantPaths := make([]string, 0, len(fixData.Diffs))

	for _, diff := range fixData.Diffs {
		relevantPaths = append(relevantPaths, diff.Path)
	}

	// If the alert path is not already in the list of relevant paths, add it
	if !slices.Contains(relevantPaths, fixData.Alert.Location.Path) {
		// TODO: add logging here that the alert path is not in the list of relevant paths
		relevantPaths = append(relevantPaths, fixData.Alert.Location.Path)
	}

	relevantFiles := make([]file, len(relevantPaths))

	for i, path := range relevantPaths {
		contents, err := codeBase.ReadContents(path)
		if err != nil {
			return "", err
		}
		relevantFiles[i] = file{
			Path:    path,
			Content: contents,
		}
	}

	// TODO add logging here that the prompt is truncated
	codeSnippets, _, err := generateCodeSnippetsForPrompt(relevantFiles, modelParameters)
	if err != nil {
		return "", errors.Errorf("failed to generate code snippets for prompt: %v", err)
	}

	alertFile, err := codeBase.GetFile(fixData.Alert.Location.Path)
	if err != nil {
		return "", err
	}
	alertSnippet, err := alertFile.ReadWithColumns(codebase.Region{
		LineRegion: codebase.LineRegion{
			File:      alertFile,
			StartLine: codebase.LineNumber(fixData.Alert.Location.StartLine),
			EndLine:   codebase.LineNumber(fixData.Alert.Location.EndLine),
		},
		StartColumn: codebase.ColumnNumber(fixData.Alert.Location.StartColumn),
		EndColumn:   codebase.ColumnNumber(fixData.Alert.Location.EndColumn),
	})
	if err != nil {
		return "", err
	}

	promptArguments := userPromptArguments{
		Alert:                fixData.Alert,
		CodeSnippets:         codeSnippets,
		UseReplacementBlocks: useReplacementBlocks,
		Diffs:                fixData.Diffs,
		AlertSnippet:         alertSnippet,
	}

	return ExecuteTemplate("user.md", promptArguments, template.FuncMap{
		"getAlertType":                   getAlertType,
		"convertDiffToReplacementBlocks": replacement_block.FromUnifiedDiff,
	})
}
