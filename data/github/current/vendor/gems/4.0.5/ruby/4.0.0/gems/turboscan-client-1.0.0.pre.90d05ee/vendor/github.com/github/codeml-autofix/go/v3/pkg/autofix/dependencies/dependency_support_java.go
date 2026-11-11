package dependencies

import (
	"context"
	"encoding/xml"
	"fmt"
	"net/http"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/github/code-scanning-ai-libraries/v3/st"
	"github.com/github/codeml-autofix/go/v3/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v3/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v3/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v3/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v3/pkg/autofix/replacement"
	"github.com/github/codeml-autofix/go/v3/pkg/autofix/utils"
	"github.com/pkg/errors"
)

// DependencySupportJava implements IDependencySupport for Java projects.
// It supports both Maven (pom.xml) and Gradle (build.gradle / build.gradle.kts)
// build systems for discovering and adding dependencies.
type DependencySupportJava struct {
}

// NewDependencySupportJava creates a new Java dependency support instance.
func NewDependencySupportJava() IDependencySupport {
	return &DependencySupportJava{}
}

var _ IDependencySupport = DependencySupportJava{} //nolint:exhaustruct // We don't need all properties
// IsBuiltIn returns true for standard library packages (java.* / javax.*).
func (d DependencySupportJava) IsBuiltIn(spec string) bool {
	return strings.HasPrefix(spec, "java.") || strings.HasPrefix(spec, "javax.")
}

// FindDependenciesFile locates the nearest pom.xml or Gradle build file for
// the given source file (ignoring build output directories). Returns nil if
// no appropriate file is found.
func (d DependencySupportJava) FindDependenciesFile(
	ctx context.Context,
	sourceFile codebase.File,
) IDependenciesFile {
	// Look for pom.xml files
	pomFile := findClosestCandidate(ctx, sourceFile, []string{
		"**/pom.xml",
		// TODO: Investigate whether go supports the `!` operator in globs
		"!**/target/**", // Exclude build directories
		"!**/build/**",  // Exclude build directories
	})
	if pomFile != nil {
		return NewPomXMLFile(ctx, pomFile)
	}

	// Look for build.gradle files
	gradleFile := findClosestCandidate(ctx, sourceFile, []string{
		"**/build.gradle",
		"**/build.gradle.kts",
		"!**/build/**", // Exclude build directories
	})
	if gradleFile != nil {
		return NewGradleBuildFile(ctx, gradleFile)
	}

	return nil
}

// GetDependencyName returns the canonical group:artifact portion of a spec
// (dropping any version) or nil if parsing fails.
func (d DependencySupportJava) GetDependencyName(spec string) *string {
	name, _ := parseJavaDependencySpec(spec)
	if name == "" {
		return nil
	}
	return &name
}

// PomXMLFile represents a Maven pom.xml file
type PomXMLFile struct {
	file *codebase.File
}

var _ IDependenciesFile = &PomXMLFile{} //nolint:exhaustruct // We don't need all properties
// NewPomXMLFile constructs a Maven pom.xml dependencies file abstraction.
func NewPomXMLFile(ctx context.Context, file *codebase.File) IDependenciesFile {
	return &PomXMLFile{
		file: file,
	}
}

// Contents returns the raw pom.xml contents.
func (p *PomXMLFile) Contents() (string, error) {
	return p.file.ReadContents()
}

// Dependency represents a dependency element in a Maven POM file.
type Dependency struct {
	GroupID    string `xml:"groupId"`
	ArtifactID string `xml:"artifactId"`
	Version    string `xml:"version"`
	Scope      string `xml:"scope"`
}

// Dependencies represents the <dependencies> section of a pom.xml.
type Dependencies struct {
	Dependency []Dependency `xml:"dependency"`
}

// Project is a partial representation of a pom.xml capturing dependency info.
type Project struct {
	Dependencies Dependencies `xml:"dependencies"`
}

// GetCurrentDependencies extracts the current Maven dependencies, ignoring
// those with test scope. Each dependency is represented as group:artifact or
// group:artifact@version.
func (p *PomXMLFile) GetCurrentDependencies() ([]string, error) {
	pomContents, err := p.Contents()
	if err != nil {
		return nil, st.EnsureStackTrace(err, "error reading file contents")
	}

	var project Project
	err = xml.Unmarshal([]byte(pomContents), &project)
	if err != nil {
		return nil, st.EnsureStackTrace(err, "error unmarshalling pom.xml file")
	}

	deps := []string{}
	for _, dep := range project.Dependencies.Dependency {
		// Skip "test" scope dependencies as they're not runtime dependencies
		if dep.Scope == "test" {
			continue
		}

		if dep.Version != "" {
			deps = append(deps, fmt.Sprintf("%s:%s@%s", dep.GroupID, dep.ArtifactID, dep.Version))
		} else {
			deps = append(deps, fmt.Sprintf("%s:%s", dep.GroupID, dep.ArtifactID))
		}
	}

	return deps, nil
}

// AddDependencies inserts the provided dependencies into the pom.xml creating
// a <dependencies> section if necessary. Returns edit commands and metadata
// about each attempted addition.
func (p *PomXMLFile) AddDependencies(ctx context.Context, dependencies []string, addDeps AddDependenciesDeps) (AddedDependencies, error) {
	prepped, err := prepareDependenciesForAdding(ctx, p, dependencies, addDeps)
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

	oldContents, err := p.file.ReadContents()
	if err != nil {
		return AddedDependencies{}, st.EnsureStackTrace(err, "error reading file contents")
	}

	// Look for the dependencies section
	dependenciesRegex := regexp.MustCompile(`(?i)<dependencies>[\s\S]*?</dependencies>`)
	dependenciesEndRegex := regexp.MustCompile(`(?i)</dependencies>`)

	var newContents string

	if dependenciesRegex.MatchString(oldContents) {
		// If dependencies section exists, add to it
		newDepsStr := ""
		for _, dep := range newDependencies {
			newDepsStr += fmt.Sprintf("    <dependency>\n        <groupId>%s</groupId>\n        <artifactId>%s</artifactId>\n        <version>%s</version>\n    </dependency>\n",
				getGroupID(dep.name), getArtifactID(dep.name), dep.version)
		}

		newContents = dependenciesEndRegex.ReplaceAllString(oldContents, newDepsStr+"</dependencies>")
	} else {
		// If no dependencies section exists, create one
		projectEndRegex := regexp.MustCompile(`(?i)</project>`)

		if !projectEndRegex.MatchString(oldContents) {
			return AddedDependencies{}, errors.New("could not find </project> tag in pom.xml")
		}

		newDepsStr := "  <dependencies>\n"
		for _, dep := range newDependencies {
			newDepsStr += fmt.Sprintf("    <dependency>\n        <groupId>%s</groupId>\n        <artifactId>%s</artifactId>\n        <version>%s</version>\n    </dependency>\n",
				getGroupID(dep.name), getArtifactID(dep.name), dep.version)
		}
		newDepsStr += "  </dependencies>\n"

		newContents = projectEndRegex.ReplaceAllString(oldContents, newDepsStr+"\n</project>")
	}

	editCommands := replacement.ParseEditCommandsFromContents(
		oldContents,
		newContents,
	)

	fileEdits := utils.Map(editCommands, func(edit editcommands.EditCommand) editcommands.FileEdit {
		return editcommands.FileEdit{
			FilePath:     p.file.Path,
			EditCommands: editcommands.NewEditCommands(editCommands),
		}
	})

	return AddedDependencies{
		Edits: fileEdits,
		Info:  info,
	}, nil
}

// GetLanguage returns the Java language constant.
func (p *PomXMLFile) GetLanguage() utils.Language {
	return utils.LanguageJava
}

// GradleBuildFile represents a Gradle build.gradle file
type GradleBuildFile struct {
	file *codebase.File
}

var _ IDependenciesFile = &GradleBuildFile{} //nolint:exhaustruct // We don't need all properties
// NewGradleBuildFile constructs a Gradle dependency file abstraction.
func NewGradleBuildFile(ctx context.Context, file *codebase.File) IDependenciesFile {
	return &GradleBuildFile{
		file: file,
	}
}

// Contents returns the raw build file contents.
func (g *GradleBuildFile) Contents() (string, error) {
	return g.file.ReadContents()
}

// GetCurrentDependencies parses existing Gradle dependencies of the forms
// implementation 'group:artifact:version' or implementation("group:artifact:version").
func (g *GradleBuildFile) GetCurrentDependencies() ([]string, error) {
	contents, err := g.Contents()
	if err != nil {
		return nil, st.EnsureStackTrace(err, "error reading file contents")
	}

	// Regular expression to find dependencies of format:
	// implementation 'com.example:artifact:1.0.0'
	// or
	// implementation("com.example:artifact:1.0.0")
	depRegex := regexp.MustCompile(`(?:implementation|api|compile)\s*(?:[(]?["|'])([^:"']+):([^:"']+)(?::([^"']+))?(?:["|'][)]?)`)

	matches := depRegex.FindAllStringSubmatch(contents, -1)

	deps := []string{}
	for _, match := range matches {
		if len(match) >= 3 {
			groupID := match[1]
			artifactID := match[2]
			version := ""
			if len(match) >= 4 && match[3] != "" {
				version = match[3]
				deps = append(deps, fmt.Sprintf("%s:%s@%s", groupID, artifactID, version))
			} else {
				deps = append(deps, fmt.Sprintf("%s:%s", groupID, artifactID))
			}
		}
	}

	return deps, nil
}

// AddDependencies inserts dependency declarations into the existing
// dependencies block (or creates one) for both Groovy and Kotlin DSL files.
func (g *GradleBuildFile) AddDependencies(ctx context.Context, dependencies []string, addDeps AddDependenciesDeps) (AddedDependencies, error) {
	prepped, err := prepareDependenciesForAdding(ctx, g, dependencies, addDeps)
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

	oldContents, err := g.file.ReadContents()
	if err != nil {
		return AddedDependencies{}, st.EnsureStackTrace(err, "error reading file contents")
	}

	// Check if this is a Kotlin build file (.kts)
	isKotlinDSL := strings.HasSuffix(g.file.Path, ".kts")

	// Look for the dependencies block
	dependenciesRegex := regexp.MustCompile(`dependencies\s*\{[\s\S]*?\}`)

	var newContents string

	if dependenciesRegex.MatchString(oldContents) {
		// If dependencies block exists, add to it
		dependenciesEndRegex := regexp.MustCompile(`(\s*)\}(\s*)$`)

		newDepsStr := "\n"
		for _, dep := range newDependencies {
			if isKotlinDSL {
				newDepsStr += fmt.Sprintf("    implementation(\"%s:%s:%s\")\n",
					getGroupID(dep.name), getArtifactID(dep.name), dep.version)
			} else {
				newDepsStr += fmt.Sprintf("    implementation '%s:%s:%s'\n",
					getGroupID(dep.name), getArtifactID(dep.name), dep.version)
			}
		}

		// Find the dependencies block
		depBlock := dependenciesRegex.FindString(oldContents)
		updatedDepBlock := dependenciesEndRegex.ReplaceAllString(depBlock, newDepsStr+"$1}$2")

		newContents = dependenciesRegex.ReplaceAllString(oldContents, updatedDepBlock)
	} else {
		// If no dependencies block exists, create one
		newDepsStr := "\ndependencies {\n"
		for _, dep := range newDependencies {
			if isKotlinDSL {
				newDepsStr += fmt.Sprintf("    implementation(\"%s:%s:%s\")\n",
					getGroupID(dep.name), getArtifactID(dep.name), dep.version)
			} else {
				newDepsStr += fmt.Sprintf("    implementation '%s:%s:%s'\n",
					getGroupID(dep.name), getArtifactID(dep.name), dep.version)
			}
		}
		newDepsStr += "}\n"

		newContents = oldContents + newDepsStr
	}

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
		Info:  info,
	}, nil
}

// GetLanguage returns the Java language constant.
func (g *GradleBuildFile) GetLanguage() utils.Language {
	return utils.LanguageJava
}

// Utility functions

// parseJavaDependencySpec parses a Java dependency specification into group ID, artifact ID, and version.
// Format: "group:artifact@version" or "group:artifact"
func parseJavaDependencySpec(spec string) (string, *string) {
	if spec == "" {
		return "", nil
	}

	// Check for version specified as @version
	versionRegex := regexp.MustCompile(`^(.+)@(.+)$`)
	matches := versionRegex.FindStringSubmatch(spec)
	if len(matches) > 0 {
		name := matches[1]
		version := matches[2]
		return name, &version
	}

	// Check for version specified as :version
	colonVersionRegex := regexp.MustCompile(`^(.+?):([^:]+):([^:]+)$`)
	matches = colonVersionRegex.FindStringSubmatch(spec)
	if len(matches) > 0 {
		name := matches[1] + ":" + matches[2]
		version := matches[3]
		return name, &version
	}

	// No version specified
	return spec, nil
}

// getGroupID extracts the group ID from a dependency name in the format "group:artifact"
func getGroupID(name string) string {
	parts := strings.Split(name, ":")
	if len(parts) > 0 {
		return parts[0]
	}
	return name
}

// getArtifactID extracts the artifact ID from a dependency name in the format "group:artifact"
func getArtifactID(name string) string {
	parts := strings.Split(name, ":")
	if len(parts) > 1 {
		return parts[1]
	}
	return ""
}

// MavenMetadataFetcher implements IMetadataFetcher for Maven packages
type MavenMetadataFetcher struct {
	// We could add a cache here in the future if needed
}

var _ IMetadataFetcher = &MavenMetadataFetcher{} //nolint:exhaustruct // We don't need all properties
// Repository represents a Maven repository
type Repository string

// RepositoryInfo contains details about a Maven repository
type RepositoryInfo struct {
	URL             string
	Name            string
	Priority        int
	AlternativeURLs []string
}

// Maven repositories in priority order
var repositories = []Repository{
	"maven",
	"atlassian",
	"hortonworks",
	"sonatype",
	"google",
}

// DefaultRepository is the default Maven repository
const DefaultRepository = Repository("maven")

// Repositories provides information about Maven repositories
var Repositories = map[Repository]RepositoryInfo{
	"maven": {
		URL:             "https://repo1.maven.org/maven2/",
		Name:            "Central Repository",
		Priority:        1,
		AlternativeURLs: nil,
	},
	"atlassian": {
		URL:             "https://packages.atlassian.com/mvn/maven-atlassian-external/",
		Name:            "Atlassian Repository",
		Priority:        3,
		AlternativeURLs: nil,
	},
	"hortonworks": {
		URL:             "https://repo.hortonworks.com/content/repositories/releases/",
		Name:            "Hortonworks Repository",
		Priority:        3,
		AlternativeURLs: nil,
	},
	"sonatype": {
		URL:             "https://oss.sonatype.org/content/repositories/releases/",
		Name:            "Sonatype Repository",
		Priority:        3,
		AlternativeURLs: nil,
	},
	"google": {
		URL:             "https://maven.google.com/",
		Name:            "Google Repository",
		Priority:        2,
		AlternativeURLs: []string{"https://dl.google.com/dl/android/maven2/"},
	},
}

// NewMavenMetadataFetcher creates a new MavenMetadataFetcher
func NewMavenMetadataFetcher() IMetadataFetcher {
	return &MavenMetadataFetcher{}
}

// buildMetadataURL constructs a URL for fetching Maven metadata
func buildMetadataURL(repository Repository, groupID, artifactID string) string {
	repoInfo := Repositories[repository]

	// Build the URL path
	groupPath := strings.ReplaceAll(groupID, ".", "/")
	path := fmt.Sprintf("%s%s/%s/maven-metadata.xml", repoInfo.URL, groupPath, artifactID)

	// Ensure the URL has the proper format
	if !strings.HasSuffix(repoInfo.URL, "/") && !strings.HasPrefix(groupPath, "/") {
		path = fmt.Sprintf("%s/%s/%s/maven-metadata.xml", repoInfo.URL, groupPath, artifactID)
	}

	return path
}

// getMetadataFromRepo fetches metadata from a specific repository
func (f *MavenMetadataFetcher) getMetadataFromRepo(ctx context.Context, repository Repository, groupID, artifactID string) (*MavenMetadata, error) {
	metadataURL := buildMetadataURL(repository, groupID, artifactID)

	// Create a request with timeout context
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, metadataURL, http.NoBody)
	if err != nil {
		return nil, err
	}

	req.Header.Set("User-Agent", "\"code scanning autofix\"")

	// Try up to 3 times with exponential backoff
	var resp *http.Response
	var lastErr error

	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			// Wait with exponential backoff (1s, 2s, 4s)
			backoffTime := time.Duration(1<<(attempt-1)) * time.Second
			time.Sleep(backoffTime)
		}

		resp, err = http.DefaultClient.Do(req)
		if err == nil && resp.StatusCode == http.StatusOK {
			break
		}

		lastErr = err
		if resp != nil && resp.Body != nil {
			if closeErr := resp.Body.Close(); closeErr != nil {
				return nil, st.EnsureStackTrace(closeErr, "failed to close response body")
			}
		}

		// Don't retry for certain status codes
		if resp != nil && (resp.StatusCode == http.StatusNotFound ||
			resp.StatusCode == http.StatusForbidden) {
			return nil, errors.Errorf("repository %s returned status %d", repository, resp.StatusCode)
		}
	}

	if err != nil {
		return nil, st.EnsureStackTrace(lastErr, "failed to fetch metadata after retries")
	}

	if resp == nil || resp.StatusCode != http.StatusOK {
		if resp != nil && resp.Body != nil {
			if closeErr := resp.Body.Close(); closeErr != nil {
				return nil, st.EnsureStackTrace(closeErr, "failed to close response body")
			}
		}
		statusCode := 0
		if resp != nil {
			statusCode = resp.StatusCode
		}
		return nil, errors.Errorf("failed to fetch metadata, status code: %d", statusCode)
	}

	defer func() {
		if closeErr := resp.Body.Close(); closeErr != nil {
			enhancedctx.Logger(ctx).WithError(closeErr).Warn("failed to close response body in MavenMetadataFetcher.getMetadataFromRepo")
		}
	}()

	// Parse the XML response
	var metadata MavenMetadata
	decoder := xml.NewDecoder(resp.Body)
	if err := decoder.Decode(&metadata); err != nil {
		return nil, st.EnsureStackTrace(err, "failed to decode Maven metadata")
	}

	return &metadata, nil
}

// GetMetadata fetches metadata for a Maven package from multiple repositories in priority order
func (f *MavenMetadataFetcher) GetMetadata(ctx context.Context, dependencyName string, latest bool) (fixdata.DependencyMetadata, error) {
	// Extract group ID and artifact ID
	groupID := getGroupID(dependencyName)
	artifactID := getArtifactID(dependencyName)

	if groupID == "" || artifactID == "" {
		return fixdata.DependencyMetadata{}, errors.Errorf("invalid Maven dependency format: %s, expected 'group:artifact'", dependencyName)
	}

	// Try repositories in priority order
	var metadataResults []struct {
		repository Repository
		metadata   *MavenMetadata
	}

	// Create a context with timeout
	timeoutCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	for _, repo := range repositories {
		metadata, err := f.getMetadataFromRepo(timeoutCtx, repo, groupID, artifactID)
		if err == nil && metadata != nil {
			metadataResults = append(metadataResults, struct {
				repository Repository
				metadata   *MavenMetadata
			}{
				repository: repo,
				metadata:   metadata,
			})
		}
	}

	// Sort results by repository priority
	sort.Slice(metadataResults, func(i, j int) bool {
		return Repositories[metadataResults[i].repository].Priority <
			Repositories[metadataResults[j].repository].Priority
	})

	if len(metadataResults) == 0 {
		return fixdata.DependencyMetadata{}, errors.Errorf("failed to fetch metadata from any repository for %s:%s", groupID, artifactID)
	}

	// Use the first (highest priority) result
	bestResult := metadataResults[0]
	metadata := bestResult.metadata

	// Determine version to use
	version, err := f.determineVersion(metadata, latest)
	if err != nil {
		return fixdata.DependencyMetadata{}, err
	}

	// Check if the dependency is malicious
	advisories, err := GetAdvisories(ctx, dependencyName, version, NewEcosystemOrPanic("maven"))
	if err != nil {
		return fixdata.DependencyMetadata{}, err
	}

	// Create URL for Maven Central artifact page
	artifactURL := fmt.Sprintf("https://mvnrepository.com/artifact/%s/%s", groupID, artifactID)

	// Build the final metadata
	result := fixdata.DependencyMetadata{
		Name:        dependencyName,
		Version:     version,
		Ecosystem:   "maven",
		Description: "", // Maven metadata doesn't typically include descriptions
		URL:         artifactURL,
		IsMalicious: len(advisories) > 0,
		Advisories:  advisories,
	}

	return result, nil
}

// determineVersion selects the appropriate version from metadata
func (f *MavenMetadataFetcher) determineVersion(metadata *MavenMetadata, preferLatest bool) (string, error) {
	// First try to use release version, which is generally more stable
	if !preferLatest && metadata.Versioning.Release != "" {
		return metadata.Versioning.Release, nil
	}

	// Then try latest, which might include pre-release versions
	if metadata.Versioning.Latest != "" {
		return metadata.Versioning.Latest, nil
	}

	// If neither is available, use the most recent version
	if len(metadata.Versioning.Versions.Version) > 0 {
		versions := metadata.Versioning.Versions.Version
		// Return the last version in the list (usually the most recent)
		return versions[len(versions)-1], nil
	}

	return "", errors.New("no version information found")
}

// MavenVersioning represents versioning information in Maven repository metadata.
type MavenVersioning struct {
	Latest           string                 `xml:"latest"`
	Release          string                 `xml:"release"`
	Versions         MavenVersions          `xml:"versions"`
	LastUpdated      string                 `xml:"lastUpdated"`
	Snapshot         MavenSnapshot          `xml:"snapshot"`
	SnapshotVersions []MavenSnapshotVersion `xml:"snapshotVersions>snapshotVersion"`
}

// MavenVersions is a list of available versions.
type MavenVersions struct {
	Version []string `xml:"version"`
}

// MavenSnapshot describes a snapshot build.
type MavenSnapshot struct {
	Timestamp   string `xml:"timestamp"`
	BuildNumber int    `xml:"buildNumber"`
	LocalCopy   bool   `xml:"localCopy"`
}

// MavenSnapshotVersion represents a classifier-specific snapshot version.
type MavenSnapshotVersion struct {
	Classifier string `xml:"classifier"`
	Extension  string `xml:"extension"`
	Value      string `xml:"value"`
	Updated    string `xml:"updated"`
}

// MavenPlugin is a plugin entry in metadata.
type MavenPlugin struct {
	Name       string `xml:"name"`
	Prefix     string `xml:"prefix"`
	ArtifactID string `xml:"artifactId"`
}

// MavenMetadata is the top-level structure for maven-metadata.xml.
type MavenMetadata struct {
	GroupID    string          `xml:"groupId"`
	ArtifactID string          `xml:"artifactId"`
	Version    string          `xml:"version"`
	Versioning MavenVersioning `xml:"versioning"`
	Plugins    []MavenPlugin   `xml:"plugins>plugin"`
}
