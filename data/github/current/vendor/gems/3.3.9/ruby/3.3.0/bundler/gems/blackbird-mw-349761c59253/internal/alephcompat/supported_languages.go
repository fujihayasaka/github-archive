package alephcompat

import "strings"

var AllSupportedLanguages = NewSupportedLanguages(
	CSharp,
	CodeQL,
	Elixir,
	Golang,
	Html,
	HtmlErb,
	Java,
	JavaScript,
	Php,
	Python,
	Ruby,
	Rust,
	Tsx,
	TypeScript,
)

type SupportedLanguages struct {
	Languages                []*Language
	languagesByLowercaseName map[string]*Language
}

func NewSupportedLanguages(languages ...*Language) SupportedLanguages {
	languagesByLowercaseName := map[string]*Language{}
	for i := range languages {
		language := languages[i]
		name := language.Name
		languagesByLowercaseName[strings.ToLower(name)] = language
	}
	return SupportedLanguages{
		languages,
		languagesByLowercaseName,
	}
}

// LanguageForNameCaseInsensitive returns the Language instance with a requested
// name (using a case-insensitive search), or nil if the language is not one
// that's supported.
func (sl *SupportedLanguages) LanguageForNameCaseInsensitive(language string) *Language {
	return sl.languagesByLowercaseName[strings.ToLower(language)]
}

// Language names
const (
	codeQL     = "CodeQL"
	csharp     = "C#"
	elixir     = "Elixir"
	golang     = "Go"
	html       = "HTML"
	htmlErb    = "HTML+ERB"
	java       = "Java"
	javaScript = "JavaScript"
	php        = "PHP"
	python     = "Python"
	ruby       = "Ruby"
	rust       = "Rust"
	tsx        = "TSX"
	typeScript = "TypeScript"
)

var CSharp = &Language{
	ID:   uint32(42),
	Name: csharp,
}

var CodeQL = &Language{
	ID:   uint32(424259634),
	Name: codeQL,
}

var Elixir = &Language{
	ID:   uint32(100),
	Name: elixir,
}

var Golang = &Language{
	ID:   uint32(132),
	Name: golang,
}

var Html = &Language{
	ID:   uint32(146),
	Name: html,
	LanguageFamily: LanguageFamily{
		Relatives: []string{
			javaScript,
			typeScript,
			tsx,
		}},
}

var HtmlErb = &Language{
	ID:   uint32(150),
	Name: htmlErb,
	LanguageFamily: LanguageFamily{
		Relatives: []string{
			ruby,
		},
	},
}

var Java = &Language{
	ID:   uint32(181),
	Name: java,
}

var JavaScript = &Language{
	ID:   uint32(183),
	Name: javaScript,
	LanguageFamily: LanguageFamily{
		Relatives: []string{
			html,
			typeScript,
			tsx,
		},
	},
}

var Php = &Language{
	ID:   uint32(272),
	Name: php,
}

var Python = &Language{
	ID:   uint32(303),
	Name: python,
}

var Ruby = &Language{
	ID:   uint32(326),
	Name: ruby,
	LanguageFamily: LanguageFamily{
		Relatives:         []string{htmlErb},
		NoQueryExtensions: []string{"rbi"},
	},
}

var Rust = &Language{
	ID:   uint32(327),
	Name: rust,
}

var Tsx = &Language{
	ID:   uint32(94901924),
	Name: tsx,
	LanguageFamily: LanguageFamily{
		Relatives: []string{
			html,
			javaScript,
			typeScript,
		},
	},
}

var TypeScript = &Language{
	ID:   uint32(378),
	Name: typeScript,
	LanguageFamily: LanguageFamily{
		Relatives: []string{
			html,
			javaScript,
			tsx,
		},
	},
}
