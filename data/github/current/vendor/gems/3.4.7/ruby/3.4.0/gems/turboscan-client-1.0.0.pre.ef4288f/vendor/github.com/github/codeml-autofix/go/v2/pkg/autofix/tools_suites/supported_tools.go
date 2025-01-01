// Port of cocofix/src/tools.ts, because tools.go is being used for different purpose.

package toolsuites

import "github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"

// Tool identifies a scanning or analysis tool whose query suites are managed.
type Tool string

const (
	ToolCodeQL Tool = "CodeQL"
)

// SupportedTools is an amalgamated list of all tools supported by Autofix.
var SupportedTools = map[Tool]bool{
	// Enabled tools, that work whether or not we are in dev mode
	"CodeQL": true,
	"ESLint": true,

	// Experimental tools, that only work in dev mode
	"Dependabot": false,
	"USAF":       false,
	"Autofind":   false,
}

// IsSupported returns true if a tool is present in SupportedTools.
func IsSupported(tool Tool) bool {
	_, exists := SupportedTools[tool]
	return exists
}

// IsEnabled returns true if a tool is present in SupportedTools and the value is true.
func IsEnabled(tool Tool) bool {
	val, exists := SupportedTools[tool]
	return exists && val
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
