package dependencies

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"io"
	"net/http"
	"regexp"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/replacement"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
)

// DependencySupportCSharp implements dependency discovery and modification for C# projects.
type DependencySupportCSharp struct {
}

// NewDependencySupportCSharp creates a new C# dependency support helper.
func NewDependencySupportCSharp() IDependencySupport {
	return &DependencySupportCSharp{}
}

var _ IDependencySupport = DependencySupportCSharp{} //nolint:exhaustruct

// IsBuiltIn returns true if the spec looks like a built-in .NET framework dependency.
func (d DependencySupportCSharp) IsBuiltIn(spec string) bool {
	return strings.HasPrefix(spec, "System.")
}

// FindDependenciesFile locates the nearest .csproj file relative to the source file.
func (d DependencySupportCSharp) FindDependenciesFile(
	sourceFile codebase.File,
	context context.Context,
) IDependenciesFile {
	csproj := findClosestCandidate(context, sourceFile, []string{"**/*.csproj"})
	if csproj == nil {
		return nil
	} else {
		return NewCsprojFile(csproj, context)
	}
}

// GetDependencyName extracts the dependency name (without version) from a spec.
func (d DependencySupportCSharp) GetDependencyName(spec string) *string {
	name, _ := parseCsharpDependencySpec(spec)
	return &name
}

// NewCsprojFile wraps a codebase file representing a .csproj file as an IDependenciesFile.
func NewCsprojFile(file *codebase.File, context context.Context) IDependenciesFile {
	return &CsprojFile{
		file: file,
	}
}

// CsprojFile represents a .csproj project file whose dependencies can be read and modified.
type CsprojFile struct {
	file *codebase.File
}

var _ IDependenciesFile = &CsprojFile{} //nolint:exhaustruct

// AddDependencies adds the given dependencies to the .csproj file, returning edits to apply.
func (c *CsprojFile) AddDependencies(ctx context.Context, dependencies []string, addDeps AddDependenciesDeps) (AddedDependencies, error) {
	prepped, err := prepareDependenciesForAdding(ctx, c, dependencies, addDeps)
	if err != nil {
		return AddedDependencies{}, err
	}
	newDependencies := prepped.newDependencies
	info := prepped.info

	if len(newDependencies) == 0 {
		return AddedDependencies{
			Edits: []editcommands.FileEdit{},
			Info:  info,
		}, nil
	}

	newDepsStr := "  <ItemGroup>\n"
	for _, dep := range newDependencies {
		newDepsStr += "    <PackageReference Include=\"" + dep.name + "\" Version=\"" + dep.version + "\" />\n"
	}
	newDepsStr += "  </ItemGroup>\n"

	oldContents, err := c.file.ReadContents()
	if err != nil {
		// this should never happen, as the file was found by
		// `findClosestCandidate`.
		return AddedDependencies{}, st.EnsureStackTrace(err, "error reading file contents")
	}
	endProjectRegex := regexp.MustCompile(`(?i)</Project>`)
	if !endProjectRegex.MatchString(oldContents) {
		return AddedDependencies{}, errors.New("could not find end of project tag")
	}

	newContents := endProjectRegex.ReplaceAllString(oldContents, newDepsStr+"\n</Project>")

	editCommands := replacement.ParseEditCommandsFromContents(
		oldContents,
		newContents,
	)

	fileEdits := utils.Map(editCommands, func(edit editcommands.EditCommand) editcommands.FileEdit {
		return editcommands.FileEdit{
			FilePath:     c.file.Path,
			EditCommands: editcommands.NewEditCommands(editCommands),
		}
	})

	return AddedDependencies{
		Edits: fileEdits,
		Info:  info,
	}, nil
}

// Contents returns the raw contents of the .csproj file.
func (c *CsprojFile) Contents() (string, error) {
	return c.file.ReadContents()
}

// GetCurrentDependencies returns the dependencies currently declared in the .csproj file.
func (c *CsprojFile) GetCurrentDependencies() ([]string, error) {
	csprojContents, err := c.Contents()
	if err != nil {
		// this should never happen, as the file was found by
		// `findClosestCandidate`.
		return nil, st.EnsureStackTrace(err, "error reading file contents")
	}

	// parse the file and read the `packagereferences`` from the csproj file
	type PackageReference struct {
		Include string `xml:"Include,attr"`
		Version string `xml:"Version,attr"`
	}
	type Proj struct {
		Sdk         string             `xml:"Sdk,attr"`
		PackageRefs []PackageReference `xml:"ItemGroup>PackageReference"`
	}

	parsedProj := Proj{} //nolint:exhaustruct

	err = xml.Unmarshal([]byte(csprojContents), &parsedProj)
	if err != nil {
		return nil, st.EnsureStackTracef(err, "error unmarshalling csproj file")
	}

	return utils.Map(parsedProj.PackageRefs, func(ref PackageReference) string {
		if ref.Version != "" {
			return ref.Include + "@" + ref.Version
		} else {
			return ref.Include
		}
	}), nil
}

// GetLanguage returns the language represented by this dependencies file (C#).
func (c *CsprojFile) GetLanguage() utils.Language {
	return utils.LanguageCsharp
}

func parseCsharpDependencySpec(spec string) (string, *string) {
	// there is no standard format to specify nuget packages with version
	// numbers. So we assume a formar similar to npm: "package@version" (or
	// "package version", because Copilot suggested it)
	packageVersionRegex := regexp.MustCompile(`^([^@ ]+)[@ ](.*)$`)
	matches := packageVersionRegex.FindStringSubmatch(spec)
	if len(matches) == 0 {
		return spec, nil
	}
	return matches[1], &matches[2]
}

// ///////
// MetadataFetcher

// NugetMetadataFetcher fetches dependency metadata from the NuGet registry.
type NugetMetadataFetcher struct {
	// TODO consider caching responses - original implementation does that
	// Is it worth it?
}

var _ IMetadataFetcher = &NugetMetadataFetcher{} //nolint:exhaustruct

// GetMetadata returns metadata information for a given NuGet package.
func (c NugetMetadataFetcher) GetMetadata(ctx context.Context, name string, latest bool) (fixdata.DependencyMetadata, error) {
	_, version, err := c.getVersion(name, latest)
	if err != nil {
		return fixdata.DependencyMetadata{}, st.EnsureStackTracef(err, "could not get version for %s", name)
	}

	if version == nil {
		return fixdata.DependencyMetadata{}, errors.Errorf("version not found for %s", name)
	}

	isMalicious, advisories, err := IsMalicious(ctx, name, NewEcosystemOrPanic("nuget"))
	if err != nil {
		return fixdata.DependencyMetadata{}, err
	}

	metadata := fixdata.DependencyMetadata{
		Advisories:  advisories,
		Name:        name,
		Version:     *version,
		Ecosystem:   "nuget",
		Description: "",
		Url:         "",
		IsMalicious: isMalicious,
	}

	return metadata, nil
}

func (c NugetMetadataFetcher) getVersion(dep string, latest bool) (string, *string, error) {
	url := "https://api.nuget.org/v3-flatcontainer/" + strings.ToLower(dep) + "/index.json"

	name, version := parseCsharpDependencySpec(dep)

	resp, err := http.Get(url) //nolint:gosec // since we define prefix of url, safe from SSRF
	if err != nil {
		return "", nil, st.EnsureStackTracef(err, "could not get latest version for %s", name)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", nil, st.EnsureStackTracef(err, "could not read response for %s", name)
	}

	var data struct {
		Versions []string `json:"versions"`
	}
	if err := json.Unmarshal(body, &data); err != nil {
		return "", nil, st.EnsureStackTracef(err, "could not parse response for %s", name)
	}

	if !latest && version != nil {
		// a version was provided, make sure it exists
		if utils.Contains(data.Versions, *version) {
			return name, version, nil
		} else {
			return "", nil, errors.Errorf("version %s not found for %s", *version, name)
		}
	}
	if len(data.Versions) == 0 {
		return "", nil, errors.Errorf("no versions found for %s", name)
	}
	return name, &data.Versions[len(data.Versions)-1], nil
}
