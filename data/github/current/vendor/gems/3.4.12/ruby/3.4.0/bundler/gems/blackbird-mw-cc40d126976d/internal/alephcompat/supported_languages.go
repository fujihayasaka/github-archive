package alephcompat

import "strings"

var AllSupportedLanguages = NewSupportedLanguages(
	Bash,
	C,
	CPP,
	CSharp,
	CodeQL,
	Elixir,
	Golang,
	Html,
	HtmlErb,
	Java,
	JavaScript,
	Lua,
	Php,
	Protobuf,
	Python,
	R,
	Ruby,
	Rust,
	Scala,
	Swift,
	Tsx,
	TypeScript,
)

type SupportedLanguages struct {
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
	bash       = "Bash"
	c          = "C"
	cpp        = "C++"
	codeQL     = "CodeQL"
	csharp     = "C#"
	elixir     = "Elixir"
	golang     = "Go"
	html       = "HTML"
	htmlErb    = "HTML+ERB"
	lua        = "Lua"
	java       = "Java"
	javaScript = "JavaScript"
	php        = "PHP"
	protobuf   = "Protocol Buffers"
	python     = "Python"
	ruby       = "Ruby"
	r          = "R"
	rust       = "Rust"
	scala      = "Scala"
	swift      = "Swift"
	tsx        = "TSX"
	typeScript = "TypeScript"
)

var Bash = &Language{
	Name: bash,
}

var C = &Language{
	Name: c,
}

var CPP = &Language{
	Name: cpp,
	LanguageFamily: LanguageFamily{
		Relatives: []string{
			c,
		},
	},
}

var CSharp = &Language{
	Name: csharp,
}

var CodeQL = &Language{
	Name: codeQL,
}

var Elixir = &Language{
	Name: elixir,
}

var Golang = &Language{
	Name: golang,
}

var Html = &Language{
	Name: html,
	LanguageFamily: LanguageFamily{
		Relatives: []string{
			javaScript,
			typeScript,
			tsx,
		}},
}

var HtmlErb = &Language{
	Name: htmlErb,
	LanguageFamily: LanguageFamily{
		Relatives: []string{
			ruby,
		},
	},
}

var Java = &Language{
	Name: java,
}

var JavaScript = &Language{
	Name: javaScript,
	LanguageFamily: LanguageFamily{
		Relatives: []string{
			html,
			typeScript,
			tsx,
		},
	},
}

var Lua = &Language{
	Name: lua,
}

var Php = &Language{
	Name: php,
}

var Protobuf = &Language{
	Name: protobuf,
}

var Python = &Language{
	Name: python,
}

var R = &Language{
	Name: r,
}

var Ruby = &Language{
	Name: ruby,
	LanguageFamily: LanguageFamily{
		Relatives:         []string{htmlErb},
		NoQueryExtensions: []string{"rbi"},
	},
}

var Rust = &Language{
	Name: rust,
}

var Swift = &Language{
	Name: swift,
}

var Scala = &Language{
	Name: scala,
}

var Tsx = &Language{
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
	Name: typeScript,
	LanguageFamily: LanguageFamily{
		Relatives: []string{
			html,
			javaScript,
			tsx,
		},
	},
}
