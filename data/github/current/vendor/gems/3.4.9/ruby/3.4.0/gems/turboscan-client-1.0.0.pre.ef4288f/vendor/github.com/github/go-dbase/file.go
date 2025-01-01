package dbase

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"
	"unicode"
)

// Section represents a labeled section of an option file. Option values that
// precede any named section are still associated with a Section object, but
// with a Name of "".
type Section struct {
	Name   string
	Values map[string]string
}

// File represents a form of ini-style option file. Lines can contain
// [sections], option=value, option without value (usually for bools), or
// comments.
type File struct {
	Dir                  string
	Name                 string
	IgnoreUnknownOptions bool
	sections             []*Section
	sectionIndex         map[string]*Section
	read                 bool
	parsed               bool
	contents             string
	selected             []string
}

// NewFile returns a value representing an option file. The arg(s) will be
// joined to create a single path, so it does not matter if the path is provided
// in a way that separates the dir from the base filename or not.
func NewFile(paths ...string) *File {
	pathAndName := path.Join(paths...)
	cleanPath, err := filepath.Abs(filepath.Clean(pathAndName))
	if err == nil {
		pathAndName = cleanPath
	}

	defaultSection := &Section{
		Name:   "",
		Values: make(map[string]string),
	}

	return &File{
		Dir:          path.Dir(pathAndName),
		Name:         path.Base(pathAndName),
		sections:     []*Section{defaultSection},
		sectionIndex: map[string]*Section{"": defaultSection},
	}
}

// Exists returns true if the file exists and is visible to the current user.
func (f *File) Exists() bool {
	_, err := os.Stat(f.Path())
	return (err == nil)
}

// Path returns the file's full absolute path with filename.
func (f *File) Path() string {
	return path.Join(f.Dir, f.Name)
}

// Read loads the contents of the option file, but does not parse it.
func (f *File) Read() error {
	file, err := os.Open(f.Path())
	if err != nil {
		return err
	}
	defer file.Close()
	bytes, err := io.ReadAll(file)
	if err != nil {
		return err
	}
	f.contents = string(bytes)
	f.read = true
	return nil
}

// Parse parses the file contents into a series of Sections. A Config object
// must be supplied so that the list of valid Options is known.
func (f *File) Parse() error {
	if !f.read {
		if err := f.Read(); err != nil {
			return err
		}
	}

	section := f.sectionIndex[""]

	var lineNumber int
	scanner := bufio.NewScanner(strings.NewReader(f.contents))
	for scanner.Scan() {
		line := scanner.Text()
		lineNumber++

		parsedLine, err := parseLine(line)
		if err != nil {
			return fmt.Errorf("Parse error in %s line %d: %w", f.Path(), lineNumber, err)
		}

		switch parsedLine.kind {
		case lineTypeSectionHeader:
			section = f.getOrCreateSection(parsedLine.sectionName)
		case lineTypeKeyOnly, lineTypeKeyValue:
			if parsedLine.kind == lineTypeKeyOnly {
				// For booleans, option without value indicates option is being enabled
				parsedLine.value = "1"
			}
			section.Values[parsedLine.key] = parsedLine.value
		}
	}

	f.parsed = true
	f.selected = []string{""}
	return scanner.Err()
}

// UseSection changes which section(s) of the file are used when calling
// OptionValue. If multiple section names are supplied, multiple sections will
// be checked by OptionValue, with sections listed first taking precedence over
// subsequent ones.
// Note that the default nameless section "" (i.e. lines at the top of the file
// prior to a section header) is automatically appended to the end of the list.
// So this section is always checked, at lowest priority, need not be
// passed to this function.
func (f *File) UseSection(names ...string) error {
	notFound := make([]string, 0)
	already := make(map[string]bool, len(names))
	f.selected = make([]string, 0, len(names)+1)

	for _, name := range names {
		if already[name] {
			continue
		}
		already[name] = true
		if f.HasSection(name) {
			f.selected = append(f.selected, name)
		} else {
			notFound = append(notFound, name)
		}
	}
	if !already[""] {
		//nolint:gocritic // not assigning to the same slice is intentional
		f.selected = append(names, "")
	}

	if len(notFound) == 0 {
		return nil
	}
	return fmt.Errorf("File %s missing section: %s", f.Path(), strings.Join(notFound, ", "))
}

// HasSection returns true if the file has a section with the supplied name.
func (f *File) HasSection(name string) bool {
	_, ok := f.sectionIndex[name]
	return ok
}

// OptionValue returns the value for the requested option from the option file.
// Only the previously-selected section(s) of the file will be used, or the
// default section "" if no section has been selected via UseSection.
// Panics if the file has not yet been parsed, as this would indicate a bug.
// This is satisfies the OptionValuer interface, allowing Files to be used as
// an option source in Config.
func (f *File) OptionValue(optionName string) (string, bool) {
	if !f.parsed {
		panic(fmt.Errorf("call to OptionValue(\"%s\") on unparsed file %s", optionName, f.Path()))
	}
	for _, sectionName := range f.selected {
		section := f.sectionIndex[sectionName]
		if section == nil {
			continue
		}
		if value, ok := section.Values[optionName]; ok {
			return value, true
		}
	}
	return "", false
}

// OptionValueWithDefault behaves just like OptionValue, but a `defaultValue`
// can be supplied to the method. If the `optionName` is not found then the
// default value will be returned insted.
func (f *File) OptionValueWithDefault(optionName, defaultValue string) string {
	if v, ok := f.OptionValue(optionName); ok {
		return v
	}

	return defaultValue
}

func (f *File) getOrCreateSection(name string) *Section {
	if s, exists := f.sectionIndex[name]; exists {
		return s
	}
	s := &Section{
		Name:   name,
		Values: make(map[string]string),
	}
	f.sections = append(f.sections, s)
	f.sectionIndex[name] = s
	return s
}

type lineType int

const (
	lineTypeBlank lineType = iota
	lineTypeComment
	lineTypeSectionHeader
	lineTypeKeyOnly
	lineTypeKeyValue
)

type parsedLine struct {
	sectionName string
	key         string
	value       string
	comment     string
	kind        lineType
	isLoose     bool
}

// parseLine parses a file line into its components.
func parseLine(line string) (*parsedLine, error) {
	line = strings.TrimLeftFunc(line, unicode.IsSpace)
	result := new(parsedLine)

	if line == "" {
		result.kind = lineTypeBlank
		return result, nil
	}
	if line[0] == ';' || line[0] == '#' {
		result.kind = lineTypeComment
		result.comment = line[1:]
		return result, nil
	}

	if line[0] == '[' {
		endIndex := strings.Index(line, "]")
		hashIndex := strings.Index(line, "#")
		if endIndex == -1 || (hashIndex > -1 && hashIndex < endIndex) {
			return nil, errors.New("unterminated section name")
		}
		if endIndex < len(line)-1 {
			var after string
			if hashIndex > -1 {
				after = line[endIndex+1 : hashIndex]
			} else {
				after = line[endIndex+1:]
			}
			if strings.TrimSpace(after) != "" {
				return nil, errors.New("extra characters after section name")
			}
		}
		result.kind = lineTypeSectionHeader
		result.sectionName = line[1:endIndex]
		if hashIndex > -1 {
			result.comment = line[hashIndex+1:]
		}
		return result, nil
	}

	// If we get here, it's one of the key/value types
	var inValue, escapeNext bool
	var inQuote rune

	// Parse out any inline comment, being careful to still allow escaped hashes or
	// hashes inside of quoted values
	for n, c := range line {
		if escapeNext {
			escapeNext = false
			continue
		}
		if c == '#' && inQuote == 0 {
			result.comment = line[n+1:]
			line = line[0:n]
			break
		}
		if !inValue {
			switch c {
			case '=':
				inValue = true
			case '\'', '"', '`', '\\':
				return nil, fmt.Errorf("illegal character %c in option name", c)
			}
			continue
		}
		switch c {
		case '\'', '"', '`':
			if c == inQuote {
				inQuote = 0
			} else if inQuote == 0 {
				inQuote = c
			}
		case '\\':
			escapeNext = true
		}
	}

	if inQuote != 0 {
		return nil, errors.New("quoted value has no terminating quote")
	}
	if escapeNext {
		return nil, errors.New("value ends in a single backslash")
	}

	var hasValue bool
	result.key, result.value, hasValue, result.isLoose = normalizeOptionToken(line)
	if hasValue {
		result.kind = lineTypeKeyValue
	} else {
		result.kind = lineTypeKeyOnly
	}
	return result, nil
}

// normalizeOptionToken takes a string of form "foo=bar" or just "foo", and
// parses it into separate key and value. It also returns whether the arg
// included a value (to tell "" vs no-value) and whether it had a "loose-"
// prefix, meaning that the calling parser shouldn't return an error if the key
// does not correspond to any existing option.
func normalizeOptionToken(arg string) (key, value string, hasValue, loose bool) {
	tokens := strings.SplitN(arg, "=", 2)
	key = strings.TrimFunc(tokens[0], unicode.IsSpace)
	if key == "" {
		return key, value, false, false
	}
	key = strings.ToLower(key)
	key = strings.ReplaceAll(key, "_", "-")

	if strings.HasPrefix(key, "loose-") {
		key = key[6:]
		loose = true
	}

	var negated bool
	switch {
	case strings.HasPrefix(key, "skip-"):
		key = key[5:]
		negated = true
	case strings.HasPrefix(key, "disable-"):
		key = key[8:]
		negated = true
	case strings.HasPrefix(key, "enable-"):
		key = key[7:]
	}

	if len(tokens) > 1 {
		hasValue = true
		value = strings.TrimFunc(tokens[1], unicode.IsSpace)
		// negated and value supplied: set to falsey value of "" UNLESS the value is
		// also falsey, in which case we have a double-negative, meaning enable
		if negated {
			switch strings.ToLower(value) {
			case "off", "false", "0":
				value = "1"
			default:
				value = ""
			}
		}
	} else if negated {
		// No value supplied and negated: set to falsey value of ""
		value = ""

		// But negation still satisfies "having a value" for RequireValue options
		hasValue = true
	}
	return key, value, hasValue, loose
}
