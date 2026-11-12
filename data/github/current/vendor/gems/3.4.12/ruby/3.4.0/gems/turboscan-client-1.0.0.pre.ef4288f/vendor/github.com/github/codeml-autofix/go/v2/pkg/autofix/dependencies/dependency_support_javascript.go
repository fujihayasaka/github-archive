package dependencies

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"unicode"

	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/replacement"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	orderedmap "github.com/iancoleman/orderedmap"
	"github.com/pkg/errors"
)

// DependencySupportJavascript implements IDependencySupport for JavaScript /
// TypeScript projects using package.json and the npm ecosystem.
type DependencySupportJavascript struct {
}

var _ IDependencySupport = DependencySupportJavascript{} //nolint:exhaustruct

// NewDependencySupportJavascript creates a JavaScript dependency support instance.
func NewDependencySupportJavascript() IDependencySupport {
	return &DependencySupportJavascript{}
}

// IsBuiltIn checks if a dependency is built-in to Node.js
func (d DependencySupportJavascript) IsBuiltIn(spec string) bool {
	name := d.GetDependencyName(spec)
	if name == nil {
		return false
	}

	builtIns := []string{
		"assert", "buffer", "child_process", "cluster", "console", "constants",
		"crypto", "dgram", "dns", "domain", "events", "fs", "http", "https",
		"module", "net", "os", "path", "punycode", "querystring", "readline",
		"repl", "stream", "string_decoder", "sys", "timers", "tls", "tty",
		"url", "util", "v8", "vm", "zlib",
	}

	for _, builtin := range builtIns {
		if builtin == *name {
			return true
		}
	}
	return false
}

// FindDependenciesFile attempts to find the package.json file closest to the provided source file
func (d DependencySupportJavascript) FindDependenciesFile(
	sourceFile codebase.File,
	ctx context.Context,
) IDependenciesFile {
	// TODO: Make sure that we don't find a package.json in vendored code (write test)
	JS_DEPENDENCIES_GLOBS := []string{
		"**/package.json",
		"!**/node_modules/**",
		"!**/dist/**",
	}

	packageJsonFile := findClosestCandidate(ctx, sourceFile, JS_DEPENDENCIES_GLOBS)
	if packageJsonFile != nil {
		packageJSON, err := NewJavaScriptPackageJSON(*packageJsonFile, ctx)
		if err == nil {
			return packageJSON
		}
	}

	return nil
}

// GetDependencyName extracts the dependency name from a specification
// In JavaScript/npm, this might be something like "react", "react@18.2.0", or "@angular/core"
func (d DependencySupportJavascript) GetDependencyName(spec string) *string {
	return getDependencyNameImpl(spec)
}

// Allows us to test without needing a mock dependency support for JavaScript
func getDependencyNameImpl(spec string) *string {
	if spec == "" {
		return nil
	}

	// Handle scoped packages like @angular/core
	if strings.HasPrefix(spec, "@") {
		parts := strings.Split(spec, "/")
		if len(parts) >= 2 {
			scope := parts[0]
			name := parts[1]
			// Remove version if present
			name = strings.Split(name, "@")[0]
			fullName := scope + "/" + name
			return &fullName
		}
	}

	// Handle packages with a hostname like npm:@scope/private-package
	if strings.Contains(spec, ":") {
		parts := strings.Split(spec, ":")
		if len(parts) >= 2 {
			rest := getDependencyNameImpl(parts[1])
			if rest == nil {
				return nil
			}
			name := parts[0] + ":" + *rest
			return &name
		}
	}

	// Handle regular packages
	re := regexp.MustCompile(`^([^@\s]+)(?:@.*)?$`)
	match := re.FindStringSubmatch(spec)
	if len(match) > 1 {
		return &match[1]
	}

	// If we couldn't parse it in a specific way, just return the entire spec
	return &spec
}

// JavaScriptPackageJson represents a package.json file
type JavaScriptPackageJson struct {
	file *codebase.File
}

var _ IDependenciesFile = &JavaScriptPackageJson{} //nolint:exhaustruct

// NewJavaScriptPackageJSON constructs a package.json abstraction after
// confirming the file can be read.
func NewJavaScriptPackageJSON(sourceFile codebase.File, ctx context.Context) (*JavaScriptPackageJson, error) {
	// Ensure we can read the file content
	_, err := sourceFile.ReadContents()
	if err != nil {
		return nil, err
	}

	return &JavaScriptPackageJson{
		file: &sourceFile,
	}, nil
}

// Contents returns the raw package.json contents.
func (s JavaScriptPackageJson) Contents() (string, error) {
	return s.file.ReadContents()
}

// GetCurrentDependencies returns the names of dependencies listed in the
// dependencies section of package.json.
func (s JavaScriptPackageJson) GetCurrentDependencies() ([]string, error) {
	contents, err := s.Contents()
	if err != nil {
		return nil, err
	}
	return getCurrentDependenciesImpl(contents)
}

func getCurrentDependenciesImpl(fileContents string) ([]string, error) {
	// Parse `dependencies` section of package.json only
	type packageDataType struct {
		Dependencies map[string]interface{} `json:"dependencies"`
	}
	packageData := packageDataType{} //nolint:exhaustruct
	err := json.Unmarshal([]byte(fileContents), &packageData)
	if err != nil {
		return nil, st.EnsureStackTrace(err, "failed to parse package.json")
	}

	allDeps := []string{}

	// Extract regular dependencies
	if packageData.Dependencies != nil {
		for name := range packageData.Dependencies {
			allDeps = append(allDeps, name)
		}
	}

	return allDeps, nil
}

// stringifyAndPreserveWs tries to preserve the original whitespace formatting when updating JSON.
// It walks over old and new lines in parallel, copying indentation from the old line to the new line
// when their content matches after trimming whitespace.
func stringifyAndPreserveWs(newContents string, oldText string) string {
	oldLines := strings.Split(oldText, "\n")
	newLines := strings.Split(newContents, "\n")

	i, j := 0, 0
	for i < len(newLines) {
		var oldLine, newLine string
		if j < len(oldLines) {
			oldLine = strings.TrimSpace(oldLines[j])
		}
		newLine = strings.TrimSpace(newLines[i])

		if oldLine == newLine {
			// Match modulo whitespace
			if j == len(oldLines)-1 && i < len(newLines)-1 {
				// If this is the closing brace of the old text, but not the new text,
				// don't copy it over (likely an added closing brace which shouldn't be outdented)
			} else {
				// Otherwise, copy over the old line
				newLines[i] = oldLines[j]
				j++
			}
		} else if oldLine+"," == newLine {
			// Match modulo whitespace and comma, so copy over old line and add comma
			// Replace end whitespace with comma + that same whitespace (like TypeScript's replace(/(\s*)$/, ",$1"))
			trailingWs := ""
			trimmedOldLine := strings.TrimRight(oldLines[j], " \t\n\r")
			if len(oldLines[j]) > len(trimmedOldLine) {
				trailingWs = oldLines[j][len(trimmedOldLine):]
			}
			newLines[i] = trimmedOldLine + "," + trailingWs
			j++
		} else {
			// This is a new line; match the indentation of the previous line if it ends with a comma
			if i > 0 {
				prevLine := strings.TrimRight(newLines[i-1], " \t\n\r")
				if strings.HasSuffix(prevLine, ",") {
					prevLineIndent := getIndentation(prevLine)
					if prevLineIndent != "" {
						newLines[i] = prevLineIndent + strings.TrimLeft(newLines[i], " \t")
					}
				}
			}
		}

		i++
	}

	updatedText := strings.Join(newLines, "\n")

	// Verify that we didn't break anything by trying to parse the JSON
	var testObj interface{}
	if err := json.Unmarshal([]byte(updatedText), &testObj); err == nil {
		// If we can successfully parse the JSON, return the updated text
		return updatedText
	}

	// If parsing failed, return the original stringified JSON
	return newContents
}

// AddDependencies writes new dependency entries (with caret-prefixed versions)
// into the dependencies section, preserving existing formatting where possible.
func (s JavaScriptPackageJson) AddDependencies(
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

	// Parse the package.json // TODO: use a more precise type
	packageData := createOrderedMap()
	err = json.Unmarshal([]byte(oldContents), &packageData)
	if err != nil {
		return AddedDependencies{}, st.EnsureStackTrace(err, "failed to parse package.json")
	}

	// Get or create the dependencies section
	x, ok := packageData.Get("dependencies")
	var depsI orderedmap.OrderedMap
	if ok {
		depsI, ok = x.(orderedmap.OrderedMap)
		if !ok {
			return AddedDependencies{}, errors.New("dependencies section is not an object in package.json")
		}
	} else {
		depsI = *createOrderedMap()
		depsI.SetEscapeHTML(false)
		packageData.Set("dependencies", depsI)
	}

	deps := depsI
	deps.SetEscapeHTML(false)

	// Add the new dependencies
	for _, dep := range prepResult.newDependencies {
		deps.Set(dep.name, "^"+dep.version)
	}

	// Format with indentation that matches the original file
	// Guess the indentation style from the old contents. This
	// assumes that the package.json file uses consistent indentation.
	indentation := guessIndentationForFile(oldContents)

	// Marshal back to JSON
	packageData.Set("dependencies", deps)
	var buf bytes.Buffer
	encoder := json.NewEncoder(&buf)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", indentation)
	err = encoder.Encode(packageData)
	if err != nil {
		return AddedDependencies{}, st.EnsureStackTrace(err, "failed to encode package.json")
	}
	newContents := buf.String()
	newContents = stringifyAndPreserveWs(newContents, oldContents)

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

// GetLanguage returns the JavaScript language constant.
func (s JavaScriptPackageJson) GetLanguage() utils.Language {
	return utils.LanguageJavascript
}

// NpmMetadataFetcher implements IMetadataFetcher for npm packages
type NpmMetadataFetcher struct{}

var _ IMetadataFetcher = &NpmMetadataFetcher{} //nolint:exhaustruct

// NpmPackageMetadata represents the metadata returned by the npm registry API
type NpmPackageMetadata struct {
	Homepage    string            `json:"homepage"`
	Description string            `json:"description"`
	Repository  map[string]string `json:"repository"`
	DistTags    struct {
		Latest string `json:"latest"`
	} `json:"dist-tags"`
}

// NewNpmMetadataFetcher creates a new NpmMetadataFetcher
func NewNpmMetadataFetcher() IMetadataFetcher {
	return &NpmMetadataFetcher{}
}

// GetMetadata fetches metadata for an npm package
func (f NpmMetadataFetcher) GetMetadata(ctx context.Context, dependencyName string, latest bool) (fixdata.DependencyMetadata, error) {
	url := "https://registry.npmjs.org/" + dependencyName
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
	var metadata NpmPackageMetadata
	if err := json.NewDecoder(resp.Body).Decode(&metadata); err != nil {
		return fixdata.DependencyMetadata{}, err
	}

	// Check if the dependency is malicious
	isMalicious, advisories, err := IsMalicious(ctx, dependencyName, NewEcosystemOrPanic("npm"))
	if err != nil {
		return fixdata.DependencyMetadata{}, err
	}

	// Determine package URL
	packageURL := ""
	if metadata.Homepage != "" {
		packageURL = metadata.Homepage
	} else if metadata.Repository != nil && metadata.Repository["url"] != "" {
		packageURL = metadata.Repository["url"]
	} else {
		packageURL = "https://www.npmjs.com/package/" + dependencyName
	}

	// Create the DependencyMetadata struct
	metadataResult := fixdata.DependencyMetadata{
		Name:        dependencyName,
		Version:     metadata.DistTags.Latest,
		Ecosystem:   "npm",
		Description: metadata.Description,
		Url:         packageURL,
		IsMalicious: isMalicious,
		Advisories:  advisories,
	}

	return metadataResult, nil
}

var getIndentationRegex = regexp.MustCompile("^[ \t]*")

// getIndentation extracts the leading whitespace from a string
func getIndentation(text string) string {
	return getIndentationRegex.FindString(text)
}

// guessIndentationForFile tries to guess the indentation style of a file based on its contents
func guessIndentationForFile(fileContents string) string {
	lines := strings.Split(fileContents, "\n")
	if len(lines) == 0 {
		return "  " // Default to 2 spaces if the file is empty
	}

	// Find the first non-empty line that starts with whitespace
	for _, line := range lines {
		if strings.TrimSpace(line) != "" && unicode.IsSpace(rune(line[0])) {
			return getIndentation(line)
		}
	}

	return "  " // Default to 2 spaces if no non-empty lines found
}

func createOrderedMap() *orderedmap.OrderedMap {
	om := orderedmap.New()
	om.SetEscapeHTML(false)
	return om
}
