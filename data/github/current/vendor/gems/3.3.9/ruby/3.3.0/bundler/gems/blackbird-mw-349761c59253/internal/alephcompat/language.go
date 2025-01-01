package alephcompat

// Language describes a programming language for which we have jump-to-definition
// and find-all-references support.
//
// NOTE: There is a fixed list of Language instances, defined in
// supported_languages.go.
type Language struct {
	// LanguageID is the linguist id assigned to this language in `github-linguist/linguist`.
	ID uint32

	// Name is the human-readable name of this language
	Name string

	// LanguageFamily contains additional language data used when constructing
	// blackbird queries from user code navigation requests.
	LanguageFamily LanguageFamily
}

// LanguageFamily helps inform query generation, and holds a list of related languages and
// a list of language extensions to exclude from blackbird query results.
type LanguageFamily struct {
	// Related languages allow querying for symbols that might be defined in a different
	// file type than what is usually identified as the primary language, for example, a symbol
	// defined in a ".html.erb" file that is referenced from a standard Ruby file.
	Relatives []string

	// NoQueryExtensions should omit the starting dot of a file extension, for example, "rbi"
	// rather than ".rbi". These extensions instruct queries to explicitly exclude results that
	// are found in files with these extensions. This is most applicable to machine generated
	// files that use a different extension, for example ".rbi" files (Ruby interface files),
	// but would otherwise be identified as having the same language id as their related
	// primary language.
	NoQueryExtensions []string
}
