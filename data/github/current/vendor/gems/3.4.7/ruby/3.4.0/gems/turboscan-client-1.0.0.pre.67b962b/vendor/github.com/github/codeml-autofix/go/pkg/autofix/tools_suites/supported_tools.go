// Port of cocofix/src/tools.ts, because tools.go is being used for different purpose.

package autofix

import "github.com/github/codeml-autofix/go/pkg/autofix/utils"

type Tool string

const (
	Tool_CodeQL Tool = "CodeQL"
)

// Amalgamated list of all tools supported by Autofix
var SupportedTools = map[Tool]bool{
	// Enabled tools, that work whether or not we are in dev mode
	"CodeQL": true,
	"ESLint": true,

	// Experimental tools, that only work in dev mode
	"Dependabot": false,
	"USAF":       false,
	"Autofind":   false,
}

// We consider a tool to be supported if it's present in SupportedTools
func IsSupported(tool Tool) bool {
	exists := SupportedTools[tool]
	return exists
}

// We consider a tool to be enabled if it's present in SupportedTools and the value is true
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
		lang := utils.Language_Javascript
		return []utils.Language{lang}
	}

	// The default, but it should already have been checked by IsEnabled
	return []utils.Language{}
}
