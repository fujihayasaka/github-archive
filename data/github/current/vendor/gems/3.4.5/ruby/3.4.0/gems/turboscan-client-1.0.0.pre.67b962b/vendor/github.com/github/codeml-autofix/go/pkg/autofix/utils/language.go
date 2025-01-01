package utils

import (
	"path/filepath"
	"strings"
)

const (
	Language_Actions    Language = "actions"
	Language_Cpp        Language = "cpp"
	Language_Csharp     Language = "csharp"
	Language_Go         Language = "go"
	Language_Java       Language = "java"
	Language_Javascript Language = "javascript"
	Language_Python     Language = "python"
	Language_Ruby       Language = "ruby"
	Language_Swift      Language = "swift"
	Language_Unknown    Language = ""
)

// The Language type represents a programming language, or the empty string.
type Language string

func NewLanguage(langOrLangId string) Language {
	if IsSupportedLanguageId(langOrLangId) {
		return supportedLanguagesMap[langOrLangId]
	} else if IsSupportedLanguage(langOrLangId) {
		return Language(langOrLangId)
	} else {
		return Language_Unknown
	}
}

var supportedLanguagesMap map[string]Language = map[string]Language{
	"actions": Language_Actions,
	"cpp":     Language_Cpp,
	"cs":      Language_Csharp,
	"go":      Language_Go,
	"java":    Language_Java,
	"js":      Language_Javascript,
	"py":      Language_Python,
	"rb":      Language_Ruby,
	"swift":   Language_Swift,
}

func SupportedLanguageIds() []string {
	return Keys(supportedLanguagesMap)
}

func SupportedLanguages() []Language {
	return Values(supportedLanguagesMap)
}

func IsSupportedLanguage(language string) bool {
	return Contains(SupportedLanguages(), Language(language))
}

func IsSupportedLanguageId(languageId string) bool {
	_, found := supportedLanguagesMap[languageId]
	return found
}

// LanguageIdFromQueryId returns the language id from a query id, if it exists.
// The language id is the first part of the query id, up to the first "/".
// For example, "cpp/some-query" returns "cpp".
// Returns nil, if the query id does not contain a "/" or if the language id is not supported.
func LanguageFromQueryId(queryId string) Language {
	s := strings.Split(queryId, "/")
	if len(s) == 0 {
		return Language_Unknown
	}

	languageId := s[0]
	return NewLanguage(languageId)
}

// Maps a file extension to a language name.
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
	}

	if lang != "" {
		return NewLanguage(lang)
	} else {
		return Language_Unknown
	}
}

// Try to infer the language of a file from the file extension.
// Returns nil, if the language could not be inferred.
func LanguageFromFilename(fileName string) Language {
	fileExtension := filepath.Ext(fileName)
	return LanguageFromExtension(fileExtension)
}
