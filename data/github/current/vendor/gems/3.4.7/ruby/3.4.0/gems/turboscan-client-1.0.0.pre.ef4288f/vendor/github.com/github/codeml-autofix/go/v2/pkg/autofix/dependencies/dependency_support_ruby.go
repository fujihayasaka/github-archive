package dependencies

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/replacement"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/pkg/errors"
)

// DependencySupportRuby implements IDependencySupport for Ruby projects
// supporting Gemfile and .gemspec files.
type DependencySupportRuby struct {
}

var _ IDependencySupport = &DependencySupportRuby{} //nolint:exhaustruct

// NewDependencySupportRuby creates a Ruby dependency support instance.
func NewDependencySupportRuby() DependencySupportRuby {
	return DependencySupportRuby{}
}

// IsBuiltIn determines if a dependency is built into Ruby.
func (d DependencySupportRuby) IsBuiltIn(spec string) bool {
	// NB: copy of the ts implementation
	return false // Haven't seen a problem related to this yet.
}

// FindDependenciesFile locates the Ruby dependency file for the given source file
func (d DependencySupportRuby) FindDependenciesFile(
	sourceFile codebase.File,
	ctx context.Context,
) IDependenciesFile {
	// Ruby dependency file patterns
	RUBY_DEPENDENCY_GLOBS := []string{
		"**/Gemfile",   // Bundler dependency file
		"**/*.gemspec", // Gem specification file
	}

	// Find the closest dependency file
	dependencyFile := findClosestCandidate(ctx, sourceFile, RUBY_DEPENDENCY_GLOBS)
	if dependencyFile == nil {
		return nil
	}

	// Return the dependency file
	// Currently just a stub that doesn't parse files
	// A complete implementation would include parsing and manipulation of Ruby dependency files
	return NewGemFile(dependencyFile)
}

// GetDependencyName extracts the package name from a dependency specification
func (d DependencySupportRuby) GetDependencyName(spec string) *string {
	name, _ := parseDependencySpecRuby(spec)
	if name == "" {
		return nil
	}
	return &name
}

func parseDependencySpecRuby(spec string) (string, *string) {
	// same as Go, except without the leading "v"
	name, version := parseDependencySpecGo(spec)
	if name == "" {
		return name, nil
	}

	if version != nil {
		// Remove the leading "v" from the version string
		newVersion := strings.TrimPrefix(*version, "v")
		version = &newVersion
	}
	return name, version
}

// GemFile wraps a Gemfile or gemspec and implements IDependenciesFile.
type GemFile struct {
	file *codebase.File
}

var _ IDependenciesFile = &GemFile{} //nolint:exhaustruct

// NewGemFile constructs a GemFile wrapper.
func NewGemFile(file *codebase.File) *GemFile {
	return &GemFile{
		file: file,
	}
}

// Contents returns the raw Gemfile contents.
func (g GemFile) Contents() (string, error) {
	return g.file.ReadContents()
}

// GetCurrentDependencies parses gem declarations returning name or name + version.
func (g GemFile) GetCurrentDependencies() ([]string, error) {
	contents, err := g.Contents()
	if err != nil {
		return nil, err
	}
	// Parse the contents to extract dependencies
	ret := []string{}

	lines := strings.Split(contents, "\n")
	// Current regex that has some limitations:
	regex := regexp.MustCompile(`^\s*gem\s+["']([^"']+)['"](?:\s*,\s*["'](.+)['"])?`)
	//                                                          careful! ^^^^
	// We're matching any character here, so we can capture versions like:
	//   `gem 'redis', '>= 4.0', '< 5'`
	// But this also means that we'll capture extra quotes, that we'll remove later.
	// The regex captures: ">= 4.0', '<5". Note the two single quotes.

	for _, line := range lines {
		line = strings.TrimSpace(line)
		// Match lines like `gem "foo", "~> 1.2.3", require: false, whatever: "else"`
		// everything after the name is optional
		matches := regex.FindStringSubmatch(line)
		if len(matches) > 2 {
			name := matches[1]
			version := matches[2]
			// remove quotes from the version if they exist:
			version = strings.ReplaceAll(version, "'", "")
			version = strings.ReplaceAll(version, "\"", "")
			if version == "" {
				// If no version is specified, we just use the name
				ret = append(ret, name)
			} else {
				// If a version is specified, we include it in the format "name version"
				ret = append(ret, name+" "+version)
			}
		}
	}
	return ret, nil
}

// GetLanguage returns the Ruby language constant.
func (g GemFile) GetLanguage() utils.Language {
	return utils.LanguageRuby
}

// AddDependencies appends gem declarations to the Gemfile and returns edits
// and per-dependency result metadata.
func (g GemFile) AddDependencies(ctx context.Context, newDependencies []string, addDeps AddDependenciesDeps) (AddedDependencies, error) {
	prepResult, err := prepareDependenciesForAdding(ctx, g, newDependencies, addDeps)
	if err != nil {
		return AddedDependencies{}, err
	}

	if len(prepResult.newDependencies) == 0 {
		return AddedDependencies{
			Edits: []editcommands.FileEdit{},
			Info:  prepResult.info,
		}, nil
	}

	oldContents, err := g.Contents()
	if err != nil {
		return AddedDependencies{}, err
	}

	var depLines []string
	for _, dep := range prepResult.newDependencies {
		depLines = append(depLines, fmt.Sprintf("gem \"%s\", \"%s\"", dep.name, dep.version))
	}

	// Append new dependencies to the end of the file with a newline
	newContents := oldContents + "\n" + strings.Join(depLines, "\n")

	// Generate edit commands
	commands := replacement.ParseEditCommandsFromContents(oldContents, newContents)

	// Create the edit
	fileEdit := editcommands.FileEdit{
		FilePath:     g.file.Path,
		EditCommands: editcommands.NewEditCommands(commands),
	}

	return AddedDependencies{
		Edits: []editcommands.FileEdit{fileEdit},
		Info:  prepResult.info,
	}, nil
}

// RubyGemsMetadataFetcher fetches gem metadata from rubygems.org.
type RubyGemsMetadataFetcher struct{}

var _ IMetadataFetcher = RubyGemsMetadataFetcher{} //nolint:exhaustruct

// NewRubyGemsMetadataFetcher creates a new metadata fetcher for RubyGems.
func NewRubyGemsMetadataFetcher() RubyGemsMetadataFetcher {
	return RubyGemsMetadataFetcher{}
}

// GetMetadata fetches gem metadata and determines advisory status.
func (f RubyGemsMetadataFetcher) GetMetadata(ctx context.Context, packageName string, latest bool) (fixdata.DependencyMetadata, error) {
	url := "https://rubygems.org/api/v1/versions/" + packageName + ".json"

	// fetch the metadata from the RubyGems API:
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
	if err != nil {
		return fixdata.DependencyMetadata{}, st.EnsureStackTrace(err, "failed to create request")
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fixdata.DependencyMetadata{}, st.EnsureStackTrace(err, "failed to fetch metadata")
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fixdata.DependencyMetadata{}, errors.Errorf("failed to fetch metadata: %s", resp.Status)
	}

	type VersionInfo struct {
		Description string `json:"description"`
		Number      string `json:"number"`
	}

	var versions []VersionInfo
	if err := json.NewDecoder(resp.Body).Decode(&versions); err != nil {
		return fixdata.DependencyMetadata{}, err
	}

	packageName, packageVersion := parseDependencySpecRuby(packageName)

	var theVersion *VersionInfo

	if latest || packageVersion == nil {
		theVersion = &versions[0]
		packageVersion = &versions[0].Number
	} else {
		// make sure that the version exists in the list
		if packageName == "" {
			return fixdata.DependencyMetadata{}, errors.Errorf("invalid package name: %s", packageName)
		}
		idx := utils.FindIdx(versions, func(v VersionInfo) bool {
			return v.Number == *packageVersion
		})

		if idx < 0 {
			// version not found, return an error
			return fixdata.DependencyMetadata{}, errors.Errorf("version %s not found for package %s", *packageVersion, packageName)
		}
		theVersion = &versions[idx]
	}

	isMalicious, advisories, err := IsMalicious(ctx, packageName, NewEcosystemOrPanic("rubygems"))
	if err != nil {
		return fixdata.DependencyMetadata{}, st.EnsureStackTrace(err, "failed to check if package is malicious")
	}

	ret := fixdata.DependencyMetadata{
		Name:        packageName,
		Version:     theVersion.Number,
		Ecosystem:   "rubygems",
		Description: theVersion.Description,
		Url:         "https://rubygems.org/gems/" + packageName,
		IsMalicious: isMalicious,
		Advisories:  advisories,
	}

	return ret, nil
}
