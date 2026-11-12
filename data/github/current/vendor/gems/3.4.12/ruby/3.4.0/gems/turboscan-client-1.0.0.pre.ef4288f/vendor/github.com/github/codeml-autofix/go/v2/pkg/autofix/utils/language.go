package utils

import (
	"path/filepath"
	"strings"
)

// The Language type represents a programming language, or the empty string.
type Language string

const (
	LanguageActions    Language = "actions"
	LanguageCpp        Language = "cpp"
	LanguageCsharp     Language = "csharp"
	LanguageGo         Language = "go"
	LanguageJava       Language = "java"
	LanguageJavascript Language = "javascript"
	LanguagePython     Language = "python"
	LanguageRuby       Language = "ruby"
	LanguageSwift      Language = "swift"
	LanguageRust       Language = "rust"
	LanguageUnknown    Language = ""
)

// LanguageDependencyFiles lists glob patterns of dependency manifest files per language.
var LanguageDependencyFiles = map[Language][]string{
	LanguageActions:    {},
	LanguageCpp:        {},
	LanguageCsharp:     {"*.csproj"},
	LanguageGo:         {"go.mod"},
	LanguageJava:       {"pom.xml", "build.gradle", "build.gradle.kts"},
	LanguageJavascript: {"package.json"},
	LanguagePython:     {"requirements.txt", "Pipfile", "pyproject.toml", "setup.py"},
	LanguageRuby:       {"Gemfile", "gemspec"},
	LanguageRust:       {"Cargo.toml"},
	LanguageSwift:      {},
	LanguageUnknown:    {},
}

func NewLanguage(langOrLangID string) Language {
	if IsSupportedLanguageID(langOrLangID) {
		return supportedLanguagesMap[langOrLangID]
	} else if IsSupportedLanguage(langOrLangID) {
		return Language(langOrLangID)
	} else {
		return LanguageUnknown
	}
}

var supportedLanguagesMap map[string]Language = map[string]Language{
	"actions": LanguageActions,
	"cpp":     LanguageCpp,
	"cs":      LanguageCsharp,
	"go":      LanguageGo,
	"java":    LanguageJava,
	"js":      LanguageJavascript,
	"py":      LanguagePython,
	"rb":      LanguageRuby,
	"swift":   LanguageSwift,
	"rust":    LanguageRust,
}

func SupportedLanguageIDs() []string {
	return Keys(supportedLanguagesMap)
}

// SupportedLanguages returns the list of languages recognized by the system
func SupportedLanguages() []Language {
	return Values(supportedLanguagesMap)
}

// IsSupportedLanguage reports whether the provided language name is supported (Should
// be called with a full language name, so `ruby` and not `rb`).
func IsSupportedLanguage(language string) bool {
	return Contains(SupportedLanguages(), Language(language))
}

func IsSupportedLanguageID(languageId string) bool {
	_, found := supportedLanguagesMap[languageId]
	return found
}

// LanguageFromQueryID returns the language id from a query id, if it exists.
// The language id is the first part of the query id, up to the first "/".
// For example, "cpp/some-query" returns "cpp".
// Returns nil, if the query id does not contain a "/" or if the language id is not supported.
func LanguageFromQueryID(queryID string) Language {
	s := strings.Split(queryID, "/")
	if len(s) == 0 {
		return LanguageUnknown
	}

	languageID := s[0]
	return NewLanguage(languageID)
}

// LanguageFromExtension maps a file extension to a language name.
func LanguageFromExtension(extension string) Language {
	lang := ""
	switch extension {
	case ".go":
		lang = "go"
	case ".py":
		lang = "python"
	case ".rb", ".ruby":
		lang = "ruby"
	case ".cs":
		lang = "csharp"
	case ".java":
		lang = "java"
	case ".swift":
		lang = "swift"
	case ".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".hxx":
		lang = "cpp"
	case ".js", ".cjs", ".mjs", ".es6", ".es", ".jsx", ".ts", ".cts", ".mts", ".tsx":
		lang = "javascript"
	case ".rs":
		lang = "rust"
	}

	if lang != "" {
		return NewLanguage(lang)
	} else {
		return LanguageUnknown
	}
}

// LanguageFromFilename tries to infer the language of a file from the file extension.
// Returns nil, if the language could not be inferred.
func LanguageFromFilename(fileName string) Language {
	fileExtension := filepath.Ext(fileName)
	return LanguageFromExtension(fileExtension)
}
