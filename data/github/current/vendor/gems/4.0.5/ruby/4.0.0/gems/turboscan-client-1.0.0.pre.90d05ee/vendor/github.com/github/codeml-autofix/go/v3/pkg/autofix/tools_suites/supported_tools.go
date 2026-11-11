// Package toolsuites provides supported tool metadata and query suite helpers.
package toolsuites

import "github.com/github/codeml-autofix/go/v3/pkg/autofix/utils"

// Tool identifies a scanning or analysis tool whose query suites are managed.
type Tool string

const (
	// ToolCodeQL is the CodeQL analysis tool.
	ToolCodeQL Tool = "CodeQL"

	// ToolESLint is the ESLint analysis tool.
	ToolESLint Tool = "ESLint"

	// ToolAutofind is the Autofind analysis tool.
	ToolAutofind Tool = "Autofind"
)

// SupportedTools lists the tools supported by autofix.
var SupportedTools = map[Tool]bool{
	ToolCodeQL:   true,
	ToolESLint:   true,
	ToolAutofind: true,
}

// IsSupported returns true if a tool is present in SupportedTools.
func IsSupported(tool Tool) bool {
	val, exists := SupportedTools[tool]
	return val && exists
}

// IsEnabled returns true if a tool is present in SupportedTools and the value is true.
func IsEnabled(tool Tool) bool {
	tools := GetEnabledTools()
	val, exists := tools[tool]
	return val && exists
}

// GetSupportedLanguages returns a list of languages that are supported by a given tool.
func GetSupportedLanguages(tool Tool) []utils.Language {
	if !IsEnabled(tool) {
		return []utils.Language{}
	}

	switch tool {
	case "CodeQL":
		return utils.SupportedLanguages()
	case "ESLint":
		lang := utils.LanguageJavascript
		return []utils.Language{lang}
	}

	// The default, but it should already have been checked by IsEnabled
	return []utils.Language{}
}
