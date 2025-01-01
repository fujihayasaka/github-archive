package dependencies

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"sort"
	"strings"

	"github.com/BurntSushi/toml"
	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/replacement"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/pkg/errors"
	"gopkg.in/yaml.v3"
)

// DependencySupportPython implements dependency discovery and manipulation for Python projects.
type DependencySupportPython struct {
}

// NewDependencySupportPython constructs a new Python dependency support helper.
func NewDependencySupportPython() IDependencySupport {
	return &DependencySupportPython{}
}

var _ IDependencySupport = DependencySupportPython{}

//go:embed languages/python_builtins.json
var pythonBuiltins []byte

var pythonBuiltinList []string

func init() {
	if err := json.Unmarshal(pythonBuiltins, &pythonBuiltinList); err != nil {
		panic(err)
	}
}

// IsBuiltIn reports whether the given dependency spec refers to a Python builtin module.
func (d DependencySupportPython) IsBuiltIn(spec string) bool {
	name := d.GetDependencyName(spec)
	if name == nil {
		return false
	}
	for _, builtin := range pythonBuiltinList {
		if builtin == *name {
			return true
		}
	}
	return false
}

// PythonRequirementsSection is a section of a python dependencies file.
//
// This is used to represent a section of a requirements.txt file, or a Pipfile.
type PythonRequirementsSection struct {
	startLine int
	endLine   int
	file      *codebase.File
}

var _ IDependenciesFile = &PythonRequirementsSection{} //nolint:exhaustruct

func (s PythonRequirementsSection) renderDependencyLine(dep DependencyNameAndVersion) string {
	if strings.HasSuffix(s.file.Path, "requirements.txt") {
		return fmt.Sprintf("%s==%s", dep.name, dep.version)
	} else {
		return fmt.Sprintf("%s = \"^%s\"", dep.name, dep.version)
	}
}

// Contents returns the raw text of the requirements segment (or entire file if unspecified).
func (s PythonRequirementsSection) Contents() (string, error) {
	fileContents, err := s.file.ReadContents()
	if err != nil {
		return "", err
	}

	if s.startLine < 0 || s.endLine < 0 {
		// use the whole file
		return fileContents, nil
	}

	// If the file is empty, return an empty string
	lines := strings.Split(fileContents, "\n")

	var contentsSlice []string
	for l := s.startLine; l <= s.endLine; l++ {
		contentsSlice = append(contentsSlice, lines[l-1])
	}

	return strings.Join(contentsSlice, "\n"), nil
}

// GetCurrentDependencies extracts dependency specifications from the requirements section.
func (s PythonRequirementsSection) GetCurrentDependencies() ([]string, error) {
	contents, err := s.Contents()
	if err != nil {
		return nil, err
	}

	return pythonRequirementsParseCurrentDependencies(contents)
}

// pythonRequirementsParseCurrentDependencies parses the contents of a requirements.txt or Pipfile
// and returns a list of dependencies.
//
// See tests for input/output examples.
func pythonRequirementsParseCurrentDependencies(contents string) ([]string, error) {
	lines := strings.Split(contents, "\n")

	// process line continuations
	processed_lines := make([]string, 0, len(lines))
	for i := 0; i < len(lines); i++ {
		line := lines[i]
		for strings.HasSuffix(line, "\\") {
			// remove the trailing backslash and add the next line
			line = strings.TrimSuffix(line, "\\")
			if i+1 < len(lines) {
				i++
				line = strings.TrimSpace(line) + " " + strings.TrimSpace(lines[i])
			} else {
				return nil, errors.New("line continuation without next line")
			}
		}
		processed_lines = append(processed_lines, line)
	}

	lines = processed_lines

	// remove comments
	processed_lines = make([]string, 0, len(lines))
	for i := range lines {
		line := lines[i]
		if strings.Contains(line, "#") {
			// remove the comment
			line = strings.Split(line, "#")[0]
		}

		if strings.TrimSpace(line) != "" {
			// add the line if it's not empty
			processed_lines = append(processed_lines, line)
		}
	}

	// trim whitespace
	for i := range processed_lines {
		processed_lines[i] = strings.TrimSpace(processed_lines[i])
	}
	return processed_lines, nil
}

// AddDependencies inserts the provided dependencies into the requirements section and returns resulting edits.
func (s PythonRequirementsSection) AddDependencies(
	ctx context.Context,
	dependencies []string,
	addDeps AddDependenciesDeps,
) (AddedDependencies, error) {
	prepResult, err := prepareDependenciesForAdding(ctx, s, dependencies, addDeps)
	if err != nil {
		return AddedDependencies{}, err
	}
	if (len(prepResult.newDependencies) == 0) || (prepResult.info == nil) {
		return AddedDependencies{
			Edits: []editcommands.FileEdit{},
			Info:  prepResult.info,
		}, nil
	}

	newDepLines := make([]string, 0, len(prepResult.newDependencies))
	for _, dep := range prepResult.newDependencies {
		newDepLines = append(newDepLines, s.renderDependencyLine(dep))
	}

	// if the region is empty, add a new dependency section
	if s.startLine == s.endLine {
		if strings.HasSuffix(s.file.Path, "Pipfile") {
			// insert [packages] at the start of the newDepLines array:
			newDepLines = append([]string{"[packages]", ""}, newDepLines...)
		}
	}

	editStartLine := codebase.LineNumber(s.endLine + 1)
	if s.startLine <= 0 {
		// in this case, insert at the start of the file:
		editStartLine = codebase.LineNumber(1)
	}

	return AddedDependencies{
		Edits: []editcommands.FileEdit{
			{
				FilePath: s.file.Path,
				EditCommands: editcommands.NewEditCommands([]editcommands.EditCommand{
					editcommands.NewInsertAfter(
						editStartLine,
						newDepLines,
					),
				}),
			},
		},
		Info: prepResult.info,
	}, nil
}

// GetLanguage returns the language handled by this dependencies file (Python).
func (s PythonRequirementsSection) GetLanguage() utils.Language {
	return utils.LanguagePython
}

// NewPythonRequirementsTxt creates a new PythonRequirementsSection from a requirements.txt file.
func NewPythonRequirementsTxt(sourceFile codebase.File, ctx context.Context) *PythonRequirementsSection {
	return &PythonRequirementsSection{
		file:      &sourceFile,
		startLine: -1,
		endLine:   -1,
	}
}

// NewPythonPipFile creates a new PythonRequirementsSection from a Pipfile.
func NewPythonPipFile(sourceFile codebase.File, ctx context.Context) (*PythonRequirementsSection, error) {
	contents, err := sourceFile.ReadContents()
	if err != nil {
		return nil, err
	}

	dependencyHeader := "[packages]"
	if !strings.Contains(contents, dependencyHeader) {
		return nil, errors.New("Pipfile does not contain a section for dependencies")
	}

	// Find the start and end lines of the dependency section
	lines := strings.Split(contents, "\n")
	startLine := -1
	endLine := -1
	for i, line := range lines {
		lineIdx := i + 1
		if strings.Contains(line, dependencyHeader) {
			// the line AFTER the header is the start line
			startLine = lineIdx + 1
			break
		}
	}
	for i := startLine; i < len(lines); i++ {
		lineIdx := i + 1
		if strings.TrimSpace(lines[i]) == "" || strings.HasPrefix(lines[i], "[") {
			endLine = lineIdx - 1
			break
		}
	}
	if endLine == -1 {
		endLine = len(lines) - 1
	}
	if startLine == -1 || endLine == -1 {
		return nil, errors.New("Pipfile does not contain a valid section for dependencies")
	}

	return &PythonRequirementsSection{
		file:      &sourceFile,
		startLine: startLine,
		endLine:   endLine,
	}, nil
}

// SetupPyFileWithInstallRequires represents a setup.py file containing an install_requires argument.
type SetupPyFileWithInstallRequires struct {
	file *codebase.File
}

var _ IDependenciesFile = &SetupPyFileWithInstallRequires{} //nolint:exhaustruct

// Contents returns the raw contents of the setup.py file.
func (s SetupPyFileWithInstallRequires) Contents() (string, error) {
	return s.file.ReadContents()
}

type parsedInstallRequires struct {
	installRequires      []string
	rawInstallRequires   string
	startIdx             int
	sliceLength          int
	foundInstallRequires bool
}

// parseInstallRequires parses the install_requires array from a setup.py file.
//
// for this file:
//
// ```python
// from setuptools import setup
//
// setup(
//
//	name="example",
//	version="0.1",
//	install_requires=[
//	    "requests>=2.20.0",
//	    "numpy>=1.18.0",
//	],
//
// )
// ```
//
// it will return something like this:
//
// ```
//
//	parsedInstallRequires{
//	    installRequires: ["requests>=2.20.0", "numpy>=1.18.0"],
//	    rawInstallRequires: "[\n        \"requests>=2.20.0\",\n        \"numpy>=1.18.0\",\n    ]",
//	    startIdx: <index of the first character of the install_requires array>,
//	    sliceLength: <length of the install_requires array>,
//	    foundInstallRequires: true,
//	}
//
// ```
func parseInstallRequires(contents string) (parsedInstallRequires, error) {
	// look for setup(..., install_requires=[...], ...),
	// capturing everything before the first bracket as well as the contents of the array
	re := regexp.MustCompile(`(?m)^\s*setup\s*\((?:.|\s)*install_requires\s*=\s*(\[(?:.|\s)*\])`)
	match := re.FindStringSubmatch(contents)
	if match == nil {
		// if there is no `install_requires=[...]` argument, we return an empty array.

		// as the startIdx, we use the character after `setup(`.
		setupParenMatch := regexp.MustCompile(`(?m)^\s*setup\s*(\()`).FindStringSubmatchIndex(contents)
		if setupParenMatch == nil {
			return parsedInstallRequires{}, errors.New("failed to find setup() function")
		}

		return parsedInstallRequires{
			installRequires:      []string{},
			rawInstallRequires:   "",
			startIdx:             setupParenMatch[1] + 1,
			sliceLength:          0,
			foundInstallRequires: false,
		}, nil
	}

	// parse as yml:
	var installRequires []string
	if err := yaml.Unmarshal([]byte(match[1]), &installRequires); err != nil {
		return parsedInstallRequires{}, st.EnsureStackTrace(err, "failed to parse install_requires")
	}

	return parsedInstallRequires{
		installRequires:      installRequires,
		rawInstallRequires:   match[1],
		startIdx:             strings.Index(contents, match[1]),
		sliceLength:          len(match[1]),
		foundInstallRequires: true,
	}, nil
}

// replaces the install_requires array in the setup.py file with a new one,
// matching the indentation of the original file.
func replaceInstallRequires(contents string, newInstallRequires []string) (string, error) {
	parsed, err := parseInstallRequires(contents)
	if err != nil {
		return "", err
	}

	addQuotes := func(dep string) string {
		return "'" + strings.TrimSpace(dep) + "'"
	}

	if len(parsed.installRequires) == 0 {
		// if there are no install_requires, replace the old one.
		newInstallRequiresWithQuotes := utils.Map(newInstallRequires, addQuotes)
		renderedNew := "[" +
			strings.Join(newInstallRequiresWithQuotes, ", ") + "]"

		if !parsed.foundInstallRequires {
			// there wasn't a install_requires declaration, we need to add it!
			renderedNew = "install_requires=" + renderedNew + ",\n"
		}
		newContents := contents[0:parsed.startIdx] + renderedNew + contents[(parsed.startIdx+parsed.sliceLength):]
		return newContents, nil
		// return strings.Replace(contents, parsed.rawInstallRequires, newContents, 1), nil
	}
	if len(parsed.installRequires) == 1 {
		// if there is only one existing install_requires, add the new one:

		withAdded := make([]string, 0, len(parsed.installRequires)+1)
		withAdded = append(withAdded, parsed.installRequires...)
		withAdded = append(withAdded, newInstallRequires...)

		// sort the resulting install_requires
		sort.Strings(withAdded)

		withAdded = utils.Map(withAdded, addQuotes)

		return strings.Replace(contents, parsed.rawInstallRequires, "["+strings.Join(withAdded, ", ")+"]", 1), nil
	}
	// replace the install_requires array with the new one
	// use the same indentation as the original file

	// to find the separator between elements, we first remove the comments:
	commentsMatch := regexp.MustCompile(`(?m)^\s*[^\s]*(\s*#.*)\n`).FindAllStringSubmatch(parsed.rawInstallRequires, -1)
	rawInstallRequiresWithoutComments := parsed.rawInstallRequires
	for i := 0; i < len(commentsMatch); i++ {
		theComment := commentsMatch[i][1]
		rawInstallRequiresWithoutComments = strings.Replace(rawInstallRequiresWithoutComments, theComment, "", -1)
	}
	separatorMatch := regexp.MustCompile(`(?m)\[[^,]*,(\s*)[^\s]`).FindStringSubmatch(rawInstallRequiresWithoutComments)
	if len(separatorMatch) < 2 {
		return "", errors.New("no separator found")
	}
	separator := separatorMatch[1]

	// insert the new dependencies into the array at position 1:
	joined := separator + strings.Join(utils.Map(newInstallRequires, addQuotes), ","+separator) + ","
	mergedRawInstallRequires := strings.Replace(parsed.rawInstallRequires, "[", "["+joined, 1)
	return strings.Replace(contents, parsed.rawInstallRequires, mergedRawInstallRequires, 1), nil
}

// GetCurrentDependencies parses the install_requires list from the setup.py file.
func (s SetupPyFileWithInstallRequires) GetCurrentDependencies() ([]string, error) {
	contents, err := s.Contents()
	if err != nil {
		return nil, err
	}
	parsed, err := parseInstallRequires(contents)
	if err != nil {
		return nil, err
	}
	return parsed.installRequires, nil
}

// AddDependencies appends new dependencies to install_requires and returns the edits to apply.
func (s SetupPyFileWithInstallRequires) AddDependencies(
	ctx context.Context,
	dependencies []string,
	addDeps AddDependenciesDeps,
) (AddedDependencies, error) {
	prepResult, err := prepareDependenciesForAdding(ctx, s, dependencies, addDeps)
	if err != nil {
		return AddedDependencies{}, err
	}

	if len(prepResult.newDependencies) == 0 || prepResult.info == nil {
		return AddedDependencies{
			Edits: []editcommands.FileEdit{},
			Info:  prepResult.info,
		}, nil
	}
	oldContents, err := s.Contents()
	if err != nil {
		return AddedDependencies{}, err
	}

	depLines := utils.Map(prepResult.newDependencies, func(dep DependencyNameAndVersion) string {
		return fmt.Sprintf("%s==%s", dep.name, dep.version)
	})

	newContents, err := replaceInstallRequires(oldContents, depLines)
	if err != nil {
		return AddedDependencies{}, err
	}

	// Generate edit commands
	edits := replacement.ParseEditCommandsFromContents(oldContents, newContents)

	return AddedDependencies{
		Edits: []editcommands.FileEdit{
			{
				FilePath:     s.file.Path,
				EditCommands: editcommands.NewEditCommands(edits),
			},
		},
		Info: prepResult.info,
	}, nil
}

// GetLanguage returns Python as the language for this dependencies file.
func (s SetupPyFileWithInstallRequires) GetLanguage() utils.Language {
	return utils.LanguagePython
}

// NewSetupPyFileWithInstallRequires constructs a SetupPyFileWithInstallRequires helper for a setup.py file.
func NewSetupPyFileWithInstallRequires(sourceFile codebase.File, ctx context.Context) (*SetupPyFileWithInstallRequires, error) {
	ret := SetupPyFileWithInstallRequires{
		file: &sourceFile,
	}
	// check whether the file can be parsed:
	_, err := sourceFile.ReadContents()
	if err != nil {
		return nil, err
	}
	return &ret, nil
}

// PyprojectTomlFile wraps a pyproject.toml file and exposes dependency operations.
type PyprojectTomlFile struct {
	file *codebase.File
}

// PyprojectTomlDependencies captures the dependency-related sections of pyproject.toml.
type PyprojectTomlDependencies struct {
	Project *struct {
		Dependencies []string `toml:"dependencies"`
	} `toml:"project"`
	Tool *struct {
		Poetry *struct {
			Dependencies map[string]string `toml:"dependencies"`
		} `toml:"poetry"`
		Flit *struct {
			Metadata *struct {
				Requires []string `toml:"requires"`
			} `toml:"metadata"`
		} `toml:"flit"`
	} `toml:"tool"`
}

func (s PyprojectTomlFile) parseTomlFile() (PyprojectTomlDependencies, error) {
	contents, err := s.Contents()
	if err != nil {
		return PyprojectTomlDependencies{}, err
	}
	var dependencies PyprojectTomlDependencies
	if err := toml.Unmarshal([]byte(contents), &dependencies); err != nil {
		return PyprojectTomlDependencies{}, err
	}
	return dependencies, nil
}

var _ IDependenciesFile = &PyprojectTomlFile{} //nolint:exhaustruct

// Contents returns the full contents of the pyproject.toml file.
func (s PyprojectTomlFile) Contents() (string, error) {
	return s.file.ReadContents()
}

// GetCurrentDependencies enumerates currently declared dependencies.
func (s PyprojectTomlFile) GetCurrentDependencies() ([]string, error) {
	parsed, err := s.parseTomlFile()
	if err != nil {
		return nil, err
	}
	if parsed.Project != nil && parsed.Project.Dependencies != nil {
		return parsed.Project.Dependencies, nil
	} else if parsed.Tool != nil && parsed.Tool.Poetry != nil && parsed.Tool.Poetry.Dependencies != nil {
		// poetry dependencies
		deps := make([]string, 0, len(parsed.Tool.Poetry.Dependencies))
		for dep, version := range parsed.Tool.Poetry.Dependencies {
			deps = append(deps, dep+" "+version)
		}
		return deps, nil
	} else if parsed.Tool != nil && parsed.Tool.Flit != nil && parsed.Tool.Flit.Metadata != nil && parsed.Tool.Flit.Metadata.Requires != nil {
		// flit dependencies
		return parsed.Tool.Flit.Metadata.Requires, nil
	} else {
		// no dependencies found
		return []string{}, nil
	}
}

// AddDependencies injects new dependencies into pyproject.toml and returns edits.
func (s PyprojectTomlFile) AddDependencies(
	ctx context.Context,
	dependencies []string,
	addDeps AddDependenciesDeps,
) (AddedDependencies, error) {
	prepResult, err := prepareDependenciesForAdding(ctx, s, dependencies, addDeps)
	if err != nil {
		return AddedDependencies{}, err
	}
	if len(prepResult.newDependencies) == 0 || prepResult.info == nil {
		return AddedDependencies{
			Edits: []editcommands.FileEdit{},
			Info:  prepResult.info,
		}, nil
	}

	oldContents, err := s.Contents()
	if err != nil {
		return AddedDependencies{}, err
	}

	depLines := make([]string, 0, len(prepResult.newDependencies))
	for _, dep := range prepResult.newDependencies {
		depLines = append(depLines, fmt.Sprintf("%s==%s", dep.name, dep.version))
	}

	// Parse the TOML file to determine which section to modify
	parsedFile, err := s.parseTomlFile()
	if err != nil {
		return AddedDependencies{}, err
	}

	var insertAt int = -1
	var insert string

	// Look for dependencies in [project] section
	if parsedFile.Project != nil && parsedFile.Project.Dependencies != nil {
		// Find the array position in the file
		arrayPos := s.findArray("project", "dependencies", oldContents)
		if arrayPos.start != -1 {
			insertAt = arrayPos.start
			insert = ""
			for _, dep := range depLines {
				insert += fmt.Sprintf("%q,%s", dep, arrayPos.sep)
			}
		}
		// Look for dependencies in [tool.poetry.dependencies] section
	} else if parsedFile.Tool != nil && parsedFile.Tool.Poetry != nil && parsedFile.Tool.Poetry.Dependencies != nil {
		// Find the position after [tool.poetry.dependencies]
		re := regexp.MustCompile(`(?m)^\[tool\.poetry\.dependencies\]\s*\n`)
		match := re.FindStringIndex(oldContents)
		if match != nil {
			insertAt = match[1]
			insert = ""
			for _, d := range prepResult.newDependencies {
				insert += fmt.Sprintf("%s = %q\n", d.name, d.version)
			}
		}
		// Look for dependencies in [tool.flit.metadata] section
	} else if parsedFile.Tool != nil && parsedFile.Tool.Flit != nil &&
		parsedFile.Tool.Flit.Metadata != nil && parsedFile.Tool.Flit.Metadata.Requires != nil {
		// Find the array position in the file
		arrayPos := s.findArray("tool\\.flit\\.metadata", "requires", oldContents)
		if arrayPos.start != -1 {
			insertAt = arrayPos.start
			insert = ""
			for _, dep := range depLines {
				insert += fmt.Sprintf("%q,%s", dep, arrayPos.sep)
			}
		}
	}

	if insertAt == -1 || insert == "" {
		return allUnsuccessful(dependencies, "unable to find dependencies in pyproject.toml"), nil
	}

	// Create the new contents by inserting at the target position
	newContents := oldContents[:insertAt] + insert + oldContents[insertAt:]

	// Generate edit commands
	edits := replacement.ParseEditCommandsFromContents(oldContents, newContents)

	return AddedDependencies{
		Edits: []editcommands.FileEdit{
			{
				FilePath:     s.file.Path,
				EditCommands: editcommands.NewEditCommands(edits),
			},
		},
		Info: prepResult.info,
	}, nil
}

type arrayPosition struct {
	start int
	sep   string
}

// findArray locates a TOML array in the file contents and returns its position and separator
func (s PyprojectTomlFile) findArray(section string, name string, contents string) arrayPosition {
	// regexStr := fmt.Sprintf(`(?m)^\[%s\].*?%s\s*=\s*\[(\s*(\n\s*))?`, section, name)
	regexStr := fmt.Sprintf(`(?m)^\[%s\]\s*%s\s*=\s*\[\s*([\n\s]*)`, section, name)
	re := regexp.MustCompile(regexStr)
	match := re.FindStringSubmatchIndex(contents)
	if len(match) < 4 {
		return arrayPosition{start: -1, sep: " "}
	}

	start := match[1]
	sep := " " // Default separator

	// Check if there was a newline separator captured
	if match[2] != -1 && match[3] != -1 {
		sep = contents[match[2]:match[3]]
	}

	return arrayPosition{start: start, sep: sep}
}

// GetLanguage returns Python as the language for this dependencies file.
func (s PyprojectTomlFile) GetLanguage() utils.Language {
	return utils.LanguagePython
}

// NewPythonPyprojectTomlFile constructs a PyprojectTomlFile helper.
func NewPythonPyprojectTomlFile(sourceFile codebase.File, ctx context.Context) *PyprojectTomlFile {
	return &PyprojectTomlFile{
		file: &sourceFile,
	}
}

// FindDependenciesFile locates an appropriate Python dependency file near the source file.
func (d DependencySupportPython) FindDependenciesFile(
	sourceFile codebase.File,
	context context.Context,
) IDependenciesFile {
	PY_REQUIREMENTS_GLOBS := []string{
		"**/requirements.txt",
		"**/Pipfile",
	}

	requirementsFile := findClosestCandidate(context, sourceFile, PY_REQUIREMENTS_GLOBS)
	if requirementsFile != nil {
		return NewPythonRequirementsTxt(*requirementsFile, context)
	}

	SETUP_PY_GLOBS := []string{
		"**/setup.py",
	}

	setuppyFile := findClosestCandidate(context, sourceFile, SETUP_PY_GLOBS)
	if setuppyFile != nil {
		// if the file can not be created, we ignore that - we'll retry creating
		// a file WITHOUT install_requires later if needed.
		setuppyWithInstallRequires, err := NewSetupPyFileWithInstallRequires(*setuppyFile, context)
		// prefer a parsed setup.py to a pyproject.toml
		if err == nil {
			return setuppyWithInstallRequires
		}
	}

	PYPROJECT_TOML_GLOBS := []string{
		"**/pyproject.toml",
	}
	pyprojectToml := findClosestCandidate(context, sourceFile, PYPROJECT_TOML_GLOBS)
	if pyprojectToml != nil {
		return NewPythonPyprojectTomlFile(*pyprojectToml, context)
	}

	if setuppyFile == nil {
		return nil
	} else {
		// this may be nil:
		ret, _ := NewSetupPyFileWithInstallRequires(*setuppyFile, context)
		return ret
	}
}

// GetDependencyName extracts the canonical dependency name from a specification string.
func (d DependencySupportPython) GetDependencyName(spec string) *string {
	// very rough parsing: take the prefix up to the first whitespace or metacharacter to be the dependency's name
	// re := regexp.MustCompile(`[^=<>~;\[\]\s]+`)
	re := regexp.MustCompile(`[\s=<>~;\[\]@]+`)
	parts := re.Split(spec, -1)
	var name string
	if len(parts) == 0 {
		name = spec
	} else {
		name = parts[0]
	}

	if name == "" {
		return nil
	}
	return &name
}

// ////////////////////
// Metadata Fetcher
// ////////////////////

// PyPackageMetadata is a subset of the PyPI JSON response used for metadata extraction.
type PyPackageMetadata struct {
	Info struct {
		Version string `json:"version"`
	} `json:"info"`
	Releases map[string]interface{} `json:"releases"`
}

// PyPIMetadataFetcher fetches metadata for Python packages from PyPI.
type PyPIMetadataFetcher struct {
}

var _ IMetadataFetcher = &PyPIMetadataFetcher{} //nolint:exhaustruct

// GetMetadata retrieves metadata for the provided package from PyPI.
func (f PyPIMetadataFetcher) GetMetadata(ctx context.Context, dependencyName string, latest bool) (fixdata.DependencyMetadata, error) {
	url := "https://pypi.org/pypi/" + dependencyName + "/json"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
	if err != nil {
		return fixdata.DependencyMetadata{}, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "code scanning autofix")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fixdata.DependencyMetadata{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body := ""
		if resp.Body != nil {
			bodyBytes, err := io.ReadAll(resp.Body)
			if err == nil {
				body = string(bodyBytes)
			}
		}
		return fixdata.DependencyMetadata{}, &AddDependencyError{
			reason: fmt.Sprintf("failed to fetch metadata for %s: status=%s, body='%s'", dependencyName, resp.Status, body),
		}
	}

	// Parse the response body
	var metadata PyPackageMetadata
	if err := json.NewDecoder(resp.Body).Decode(&metadata); err != nil {
		return fixdata.DependencyMetadata{}, err
	}
	// Check if the dependency is malicious (using the pip ecosystem, as this is
	// what the API supports!)
	isMalicious, advisories, err := IsMalicious(ctx, dependencyName, NewEcosystemOrPanic("pip"))
	if err != nil {
		return fixdata.DependencyMetadata{}, err
	}
	// Create the DependencyMetadata struct
	metadataResult := fixdata.DependencyMetadata{
		Name:        dependencyName,
		Version:     metadata.Info.Version,
		Ecosystem:   "pypi",
		Description: "",
		Url:         fmt.Sprintf("https://pypi.org/project/%s", dependencyName),
		IsMalicious: isMalicious,
		Advisories:  advisories,
	}

	return metadataResult, nil
}
