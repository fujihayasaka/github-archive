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

// DependencySupportGo implements dependency discovery and modification logic for Go projects.
type DependencySupportGo struct {
}

var _ IDependencySupport = &DependencySupportGo{} //nolint:exhaustruct

// NewDependencySupportGo constructs a new Go dependency support helper.
func NewDependencySupportGo() *DependencySupportGo {
	return &DependencySupportGo{}
}

// IsBuiltIn returns true if the dependency spec appears to reference a standard library package.
func (d DependencySupportGo) IsBuiltIn(spec string) bool {
	// Heuristic: if the first component of the name does not include a dot, it's not a URL
	// and therefore likely to be a built-in package like `strings` or `archive/zip`.
	name, _ := parseDependencySpecGo(spec)
	if name == "" {
		return false
	}
	parts := strings.Split(name, "/")
	if len(parts) == 0 {
		return false
	}
	return !strings.Contains(parts[0], ".")
}

// FindDependenciesFile finds the closest go.mod file relative to the provided source file.
func (d DependencySupportGo) FindDependenciesFile(
	sourceFile codebase.File,
	ctx context.Context,
) IDependenciesFile {
	// Look for go.mod files, which is the main dependency file for Go projects
	goModFile := findClosestCandidate(ctx, sourceFile, []string{
		"**/go.mod",
		"!**/vendor/**", // Exclude vendored dependencies
	})

	if goModFile != nil {
		return NewGoModFile(goModFile)
	}

	return nil
}

// GetDependencyName extracts the module path from a dependency spec.
func (d DependencySupportGo) GetDependencyName(spec string) *string {
	name, _ := parseDependencySpecGo(spec)
	return &name
}

// GoModFile represents a go.mod module file whose dependencies can be read and updated.
type GoModFile struct {
	file *codebase.File
}

var _ IDependenciesFile = &GoModFile{} //nolint:exhaustruct

// NewGoModFile wraps a codebase file as a GoModFile helper.
func NewGoModFile(file *codebase.File) *GoModFile {
	return &GoModFile{
		file: file,
	}
}

// Contents returns the raw contents of the go.mod file.
func (g GoModFile) Contents() (string, error) {
	return g.file.ReadContents()
}

// GetCurrentDependencies parses the go.mod file and returns module requirements.
func (g GoModFile) GetCurrentDependencies() ([]string, error) {
	contents, err := g.Contents()
	if err != nil {
		return nil, err
	}

	requiresSectionRegex := regexp.MustCompile(`(?m)^require\s*\(([^)]*)\)`)
	ret := make([]string, 0)

	matchesAll := requiresSectionRegex.FindAllStringSubmatch(contents, -1)

	for m := 0; m < len(matchesAll); m++ {
		matches := matchesAll[m]
		if len(matches) < 2 {
			return nil, nil
		}
		requiresSection := matches[1]

		for _, line := range strings.Split(requiresSection, "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			name, version := parseDependencySpecGo(line)
			ret = append(ret, fmt.Sprintf("%s %s", name, *version))
		}
	}

	return ret, nil
}

// AddDependencies adds the provided dependencies to the existing require block and returns edits.
func (g GoModFile) AddDependencies(ctx context.Context, dependencies []string, addDeps AddDependenciesDeps) (AddedDependencies, error) {
	// sometimes the model writes a dependency `github.com/x/y` as `github.com/x/y/tree`, so we delete the `/tree` part
	reg := regexp.MustCompile(`^^github\.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9\.-]+`)
	dependencies = utils.Map(dependencies, func(dep string) string {
		return reg.FindString(dep)
	})

	newDependencies, err := prepareDependenciesForAdding(ctx, g, dependencies, addDeps)
	if err != nil {
		return AddedDependencies{}, err
	}
	if len(newDependencies.newDependencies) == 0 {
		return AddedDependencies{
			Edits: []editcommands.FileEdit{},
			Info:  newDependencies.info,
		}, nil
	}

	depString := strings.Join(utils.Map(newDependencies.newDependencies, func(dep DependencyNameAndVersion) string {
		return fmt.Sprintf("\t%s %s", dep.name, dep.version)
	}), "\n")

	oldContents, err := g.Contents()
	if err != nil {
		return AddedDependencies{}, err
	}

	// find the top `require` section, and replace it:
	requireRegex := regexp.MustCompile(`(?m)^require\s*\(`)
	match := requireRegex.FindStringIndex(oldContents)

	if len(match) == 0 {
		return AddedDependencies{}, errors.New("no require section found")
	}
	end := match[1]

	newContents := oldContents[:end] + fmt.Sprintf("\n%s", depString) + oldContents[end:]

	editCommands := replacement.ParseEditCommandsFromContents(
		oldContents,
		newContents,
	)

	fileEdits := utils.Map(editCommands, func(edit editcommands.EditCommand) editcommands.FileEdit {
		return editcommands.FileEdit{
			FilePath:     g.file.Path,
			EditCommands: editcommands.NewEditCommands(editCommands),
		}
	})

	return AddedDependencies{
		Edits: fileEdits,
		Info:  newDependencies.info,
	}, nil
}

// GetLanguage returns the programming language (Go) for this dependencies file.
func (g GoModFile) GetLanguage() utils.Language {
	return utils.LanguageGo
}

// helper implementations

// parseDependencySpec parses a dependency specification string and returns the dependency name and version (if specified).
// The spec is assumed to be in the format "package v1.2.3" or "package@1.2.3".
// Optionally a comment can be added after the version number.
func parseDependencySpecGo(spec string) (string, *string) {
	// Remove any leading or trailing whitespace
	spec = strings.TrimSpace(spec)
	// Remove any comments
	if idx := strings.Index(spec, "//"); idx != -1 {
		spec = spec[:idx]
	}

	// Use regex to extract the package name and version after preprocessing
	re := regexp.MustCompile(`^(.+?)[ @]v?(.+)$`)
	matches := re.FindStringSubmatch(spec)

	if len(matches) > 2 {
		// Add "v" prefix to version if it doesn't have one already
		version := strings.TrimSpace(matches[2])
		// Trim spaces from the package name
		name := strings.TrimSpace(matches[1])
		if !strings.HasPrefix(version, "v") {
			version = "v" + version
		}
		return name, &version
	}

	return spec, nil
}

// MetadataFetcher

// GoPackagesMetadataFetcher fetches module metadata from the Go proxy.
type GoPackagesMetadataFetcher struct {
}

var _ IMetadataFetcher = &GoPackagesMetadataFetcher{} //nolint:exhaustruct

// NewGoPackagesMetadataFetcher constructs a GoPackagesMetadataFetcher.
func NewGoPackagesMetadataFetcher() GoPackagesMetadataFetcher {
	return GoPackagesMetadataFetcher{}
}

// GetMetadata retrieves metadata for the given module dependency, optionally resolving the latest version.
func (g GoPackagesMetadataFetcher) GetMetadata(ctx context.Context, dependency string, latest bool) (fixdata.DependencyMetadata, error) {
	name, version := parseDependencySpecGo(dependency)

	if latest || version == nil {
		// If the version is not specified, we need to get the latest version
		latestURL := fmt.Sprintf("https://proxy.golang.org/%s/@latest", strings.ToLower(name))

		type LatestVersion struct {
			Version string `json:"Version"`
		}
		var latestVersionResponse LatestVersion
		resp, err := http.Get(latestURL) //nolint:gosec // since we define prefix of url, safe from SSRF
		if err != nil {
			return fixdata.DependencyMetadata{}, err
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			return fixdata.DependencyMetadata{}, errors.Errorf("failed to get latest version: %s", resp.Status)
		}

		if err := json.NewDecoder(resp.Body).Decode(&latestVersionResponse); err != nil {
			return fixdata.DependencyMetadata{}, err
		}
		version = &latestVersionResponse.Version
	}

	if !latest {
		// make sure the version exists:
		listURL := fmt.Sprintf("https://proxy.golang.org/%s/@v/list", strings.ToLower(name))
		resp, err := http.Get(listURL) //nolint:gosec // since we define prefix of url, safe from SSRF
		if err != nil {
			return fixdata.DependencyMetadata{}, err
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return fixdata.DependencyMetadata{}, errors.Errorf("failed to get version list: %s", resp.Status)
		}
		var versions []string
		if err := json.NewDecoder(resp.Body).Decode(&versions); err != nil {
			return fixdata.DependencyMetadata{}, st.EnsureStackTracef(err, "failed to decode version list for %s", name)
		}
		if !utils.Contains(versions, *version) {
			return fixdata.DependencyMetadata{}, errors.Errorf("version %s not found for %s", *version, name)
		}
	}

	webURL := fmt.Sprintf("https://pkg.go.dev/%s", strings.ToLower(name))
	if version != nil {
		webURL += "@" + *version
	}

	isMalicious, advisories, err := IsMalicious(ctx, name, NewEcosystemOrPanic("go"))
	if err != nil {
		return fixdata.DependencyMetadata{}, err
	}

	return fixdata.DependencyMetadata{
		Name:        name,
		Version:     *version,
		Ecosystem:   "go",
		Description: "", // not available from the API
		Url:         webURL,
		IsMalicious: isMalicious,
		Advisories:  advisories,
	}, nil
}
