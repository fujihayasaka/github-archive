package dependencies

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"slices"
	"strings"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/pkg/errors"
)

// DependencySupportRust implements IDependencySupport for Rust projects using Cargo.toml.
type DependencySupportRust struct{}

var _ IDependencySupport = DependencySupportRust{} //nolint:exhaustruct

// NewDependencySupportRust creates a Rust dependency support instance.
func NewDependencySupportRust() *DependencySupportRust {
	return &DependencySupportRust{}
}

var rustBuiltins = map[string]bool{
	"std":        true,
	"core":       true,
	"alloc":      true,
	"proc_macro": true,
	"test":       true,
}

// IsBuiltIn returns true if the dependency is a Rust standard library crate
func (d DependencySupportRust) IsBuiltIn(spec string) bool {
	name := d.GetDependencyName(spec)
	if name == nil {
		return false
	}
	return rustBuiltins[*name]
}

// FindDependenciesFile locates the Cargo.toml file for the given source file
func (d DependencySupportRust) FindDependenciesFile(sourceFile codebase.File, ctx context.Context) IDependenciesFile {
	cargoToml := findClosestCandidate(ctx, sourceFile, []string{"**/Cargo.toml"})
	if cargoToml != nil {
		return NewCargoTomlFile(cargoToml)
	}
	return nil
}

// GetDependencyName extracts the crate name from a dependency specification
func (d DependencySupportRust) GetDependencyName(spec string) *string {
	spec = strings.TrimSpace(spec)
	fields := strings.Fields(spec)
	if len(fields) == 0 {
		return nil
	}
	return &fields[0]
}

// CargoTomlFile represents a Cargo.toml file.
type CargoTomlFile struct {
	file *codebase.File
}

var _ IDependenciesFile = &CargoTomlFile{} //nolint:exhaustruct

// NewCargoTomlFile constructs a CargoTomlFile wrapper.
func NewCargoTomlFile(file *codebase.File) *CargoTomlFile {
	return &CargoTomlFile{file: file}
}

// Contents returns the raw Cargo.toml content.
func (c CargoTomlFile) Contents() (string, error) {
	return c.file.ReadContents()
}

// findDependenciesSection returns the index of the [dependencies] section header and the lines of the file.
func findDependenciesSection(lines []string) (depSectionIdx *int) {
	for i, line := range lines {
		if strings.TrimSpace(line) == "[dependencies]" {
			idx := i
			return &idx
		}
	}
	return nil
}

// GetLinesOfCargoFile returns the Cargo.toml contents split into lines. It is
// exported for use in tests asserting dependency modifications.
func GetLinesOfCargoFile(c CargoTomlFile) ([]string, error) {
	contents, err := c.Contents()
	if err != nil {
		return []string{}, err
	}
	lines := strings.Split(contents, "\n")
	return lines, nil
}

// GetCurrentDependencies parses the [dependencies] section collecting crate specs.
func (c CargoTomlFile) GetCurrentDependencies() ([]string, error) {
	lines, err := GetLinesOfCargoFile(c)
	if err != nil {
		return nil, err
	}

	depSectionIdx := findDependenciesSection(lines)
	if depSectionIdx == nil {
		// No [dependencies] section: treat as no dependencies
		return []string{}, nil
	}
	inDeps := false
	var deps []string
	for i, line := range lines {
		line = strings.TrimSpace(line)
		if i == *depSectionIdx {
			inDeps = true
			continue
		}
		if inDeps {
			if line == "" || strings.HasPrefix(line, "[") {
				break
			}
			deps = append(deps, line)
		}
	}
	return deps, nil
}

// AddDependencies inserts crate lines into (or creates) the [dependencies] section.
func (c CargoTomlFile) AddDependencies(ctx context.Context, dependencies []string, addDeps AddDependenciesDeps) (AddedDependencies, error) {
	newDependencies, err := prepareDependenciesForAdding(ctx, c, dependencies, addDeps)
	if err != nil {
		return AddedDependencies{}, err
	}
	var toAdd []string
	for _, dep := range newDependencies.newDependencies {
		// Avoid adding the same dependency multiple times
		if slices.Contains(toAdd, dep.name) {
			continue
		}
		toAdd = append(toAdd, dep.name)
	}

	lines, err := GetLinesOfCargoFile(c)

	if err != nil {
		return AddedDependencies{}, err
	}
	depSectionIdx := findDependenciesSection(lines)
	insertPosition := 0

	if depSectionIdx == nil {
		insertPosition = len(lines) - 1
		if len(toAdd) > 0 {
			toAdd = append([]string{"[dependencies]"}, toAdd...)
		}
	} else {
		insertPosition = 1 + *depSectionIdx
	}

	edits := []editcommands.FileEdit{}
	if len(toAdd) > 0 {
		edits = append(edits,
			editcommands.FileEdit{
				FilePath: c.file.Path,
				EditCommands: editcommands.NewEditCommands([]editcommands.EditCommand{
					editcommands.NewInsertAfter(codebase.LineNumber(insertPosition), toAdd),
				}),
			},
		)
	}
	return AddedDependencies{
		Edits: edits,
		Info:  newDependencies.info,
	}, nil
}

// GetLanguage returns the Rust language constant.
func (c CargoTomlFile) GetLanguage() utils.Language {
	return utils.LanguageRust
}

// MetadataFetcher

// CrateMetadataFetcher fetches crate metadata from crates.io.
type CrateMetadataFetcher struct {
}

var _ IMetadataFetcher = CrateMetadataFetcher{} //nolint:exhaustruct

// NewCrateMetadataFetcher creates a new crates.io metadata fetcher.
func NewCrateMetadataFetcher() IMetadataFetcher {
	return &CrateMetadataFetcher{}
}

// GetMetadata fetches metadata for a Rust crate from crates.io
func (c CrateMetadataFetcher) GetMetadata(ctx context.Context, dependencyName string, latest bool) (fixdata.DependencyMetadata, error) {
	url := fmt.Sprintf("https://crates.io/api/v1/crates/%s", dependencyName)
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
			b, err := io.ReadAll(resp.Body)
			if err == nil {
				body = string(b)
			}
		}
		return fixdata.DependencyMetadata{}, errors.Errorf(
			"failed to fetch metadata for %s: status=%s, body='%s'", dependencyName, resp.Status, body,
		)
	}

	var result struct {
		Crate struct {
			Name        string `json:"name"`
			Description string `json:"description"`
			Repository  string `json:"repository"`
			MaxVersion  string `json:"max_version"`
			Homepage    string `json:"homepage"`
		} `json:"crate"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return fixdata.DependencyMetadata{}, err
	}

	// Attempt to construct a URL for the crate
	// Prefer homepage, then repository, then fallback to crates.io URL
	urlField := result.Crate.Homepage
	if urlField == "" {
		urlField = result.Crate.Repository
	}
	if urlField == "" {
		urlField = fmt.Sprintf("https://crates.io/crates/%s", dependencyName)
	}

	isMalicious, advisories, err := IsMalicious(ctx, result.Crate.Name, NewEcosystemOrPanic("rust"))
	if err != nil {
		return fixdata.DependencyMetadata{}, err
	}

	return fixdata.DependencyMetadata{
		Name:        result.Crate.Name,
		Version:     result.Crate.MaxVersion,
		Ecosystem:   "rust",
		Description: result.Crate.Description,
		Url:         urlField,
		IsMalicious: isMalicious,
		Advisories:  advisories,
	}, nil
}
