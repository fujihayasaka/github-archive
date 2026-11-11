// Package dependencies contains logic for discovering, preparing and adding dependency
// declarations as part of autofix operations, including ecosystem metadata lookups and
// advisory (malicious package) checks.
package dependencies

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/github/code-scanning-ai-libraries/v2/utils"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/config"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

// AddedDependencyInfo maps a dependency specification to the result of attempting to
// add that dependency (success metadata or an error).
type AddedDependencyInfo = map[string]AddedDependencyResult

// AddedDependencies is the result of adding dependencies to a file.
type AddedDependencies struct {
	Edits []editcommands.FileEdit
	Info  AddedDependencyInfo
}

// Gets all the files contained in `folder` (or a parent) that match `globs`.
func findAllMatchingInParentFolders(
	cb codebase.VirtualCodebase,
	folder string,
	globs []string,
) ([]*codebase.File, error) {
	candidateDependencyFiles, err := cb.FindFiles(globs)
	if err != nil {
		return nil, err
	}

	// Join with the root of the codebase to get an absolutish path
	folderContainingSourceFile := resolveWithBase(cb.GetRoot(), folder)
	parentMatchingPaths := utils.Filter(candidateDependencyFiles, func(candidate string) bool {
		candidateDir := resolveWithBase(cb.GetRoot(), filepath.Dir(candidate))
		return isPathPrefix(candidateDir, folderContainingSourceFile)
	})
	ret := make([]*codebase.File, 0, len(parentMatchingPaths))
	for _, path := range parentMatchingPaths {
		file, err := cb.GetFile(path)
		if err != nil {
			// path was returned by FindFiles, so it should be valid
			return nil, err
		}
		ret = append(ret, &file)
	}
	return ret, nil
}

func findClosestCandidate(
	ctx context.Context,
	sourceFile codebase.File,
	globs []string,
) *codebase.File {
	dirName := filepath.Dir(sourceFile.Path)
	if !isInsideOfRoot(dirName) {
		// The directory is not within the codebase root, so we cannot find a candidate.
		return nil
	}

	allMatching, err := findAllMatchingInParentFolders(
		sourceFile.Codebase,
		dirName,
		globs,
	)
	if err != nil {
		enhancedctx.Logger(ctx).WithError(err).Warn("unable to find closest candidate")
		return nil
	}

	// Validate there is no zipslip. Filter any files that are not in the same directory
	// or a subdirectory of the source file's directory.
	allMatching = utils.Filter(allMatching, func(file *codebase.File) bool {
		return isInsideOfRoot(file.Path)
	})

	sort.Slice(allMatching, func(i, j int) bool {
		return len(allMatching[i].Path) > len(allMatching[j].Path)
	})
	if len(allMatching) == 0 {
		return nil
	}
	return allMatching[0]
}

func getCurrentDependencyNames(depFile IDependenciesFile, addDeps AddDependenciesDeps) ([]string, error) {
	depNames := map[string]bool{}

	depSupport, err := addDeps.GetDependencySupport(depFile.GetLanguage())
	if err != nil {
		return nil, err
	}
	currentDependencies, err := depFile.GetCurrentDependencies()
	if err != nil {
		return nil, err
	}
	for _, dep := range currentDependencies {
		name := depSupport.GetDependencyName(dep)
		if name != nil {
			depNames[*name] = true
		}
	}
	ret := utils.Keys(depNames)
	slices.Sort(ret)
	return ret, nil
}

// DependencyNameAndVersion pairs a dependency name with the version that should be
// inserted into the dependency file.
type DependencyNameAndVersion struct {
	name    string
	version string
}

// PrepareDependenciesForAddingResult is the output of prepareDependenciesForAdding.
type PrepareDependenciesForAddingResult struct {
	newDependencies []DependencyNameAndVersion
	info            AddedDependencyInfo
}

// Prepare the given dependencies for adding to this file.
//
// Filters out dependencies that are already present in the file, and
// determines the version to use for each dependency.
func prepareDependenciesForAdding(
	ctx context.Context,
	depFile IDependenciesFile,
	dependencies []string,
	addDeps AddDependenciesDeps,
) (PrepareDependenciesForAddingResult, error) {
	currentDependencyNames, err := getCurrentDependencyNames(depFile, addDeps)
	if err != nil {
		return PrepareDependenciesForAddingResult{}, err //nolint:exhaustruct // We don't need all properties
	}

	newDependencies := PrepareDependenciesForAddingResult{
		newDependencies: []DependencyNameAndVersion{},
		info:            AddedDependencyInfo{},
	}

	depSupport, err := addDeps.GetDependencySupport(depFile.GetLanguage())
	if err != nil {
		return PrepareDependenciesForAddingResult{}, err //nolint:exhaustruct // We don't need all properties
	}
	for _, dep := range dependencies {
		depName := depSupport.GetDependencyName(dep)
		if depName == nil {
			newDependencies.info[dep] = AddedDependencyResult{
				SuccessDependencyMetadata: nil,
				Err:                       &AddDependencyError{reason: "unable to parse dependency name"},
			}
			continue
		}
		if utils.Contains(currentDependencyNames, *depName) {
			// already a dependency
			continue
		}

		// get metadata for the new dependency, always using the latest version since
		// we don't want to rely on the LLM's knowledge of version numbers
		metadata, err := addDeps.MetadataFetcher(depFile.GetLanguage()).GetMetadata(ctx, *depName, true)
		if err != nil {
			newDependencies.info[dep] = AddedDependencyResult{
				SuccessDependencyMetadata: nil,
				Err:                       &AddDependencyError{reason: fmt.Sprintf("unable to get metadata: %s", err.Error())},
			}
			continue
		}

		if metadata.IsMalicious {
			newDependencies.info[dep] = AddedDependencyResult{
				SuccessDependencyMetadata: nil,
				Err:                       &AddDependencyError{reason: "cannot add malicious package as dependency (" + *depName + ")"},
			}
			continue
		}

		newDependencies.newDependencies = append(newDependencies.newDependencies, DependencyNameAndVersion{
			name:    *depName,
			version: metadata.Version,
		})
		newDependencies.info[dep] = AddedDependencyResult{
			SuccessDependencyMetadata: &metadata,
			Err:                       nil,
		}
	}
	return newDependencies, nil
}

// IEcoSystem represents a dependency ecosystem supported by the GitHub
// advisories API (e.g. npm, pip, maven, go).
type IEcoSystem interface {
	sealedEcosystem()
	String() string
}

type ecoSystem struct {
	ecosystem string
}

func (e ecoSystem) sealedEcosystem() {}

func (e ecoSystem) String() string {
	return e.ecosystem
}

var _ IEcoSystem = ecoSystem{} //nolint:exhaustruct // We don't need all properties
// NewEcosystem creates a new ecosystem object. The ecosystem must be one of the
// values listed in the GitHub API documentation:
// https://docs.github.com/en/rest/security-advisories/global-advisories?apiVersion=2022-11-28#list-global-security-advisories
func NewEcosystem(ecosystem string) (IEcoSystem, error) {
	if ecosystem == "rubygems" ||
		ecosystem == "npm" ||
		ecosystem == "pip" ||
		ecosystem == "maven" ||
		ecosystem == "nuget" ||
		ecosystem == "composer" ||
		ecosystem == "go" ||
		ecosystem == "rust" ||
		ecosystem == "erlang" ||
		ecosystem == "actions" ||
		ecosystem == "pub" ||
		ecosystem == "other" ||
		ecosystem == "swift" {
	} else {
		return nil, errors.Errorf("invalid ecosystem: %s", ecosystem)
	}

	return ecoSystem{ecosystem: ecosystem}, nil
}

// NewEcosystemOrPanic creates an ecosystem value and panics if the input is not an allowed value.
// This is useful for hard-coded inputs, or inputs that have been checked before.
// It is not recommended to use this function for user input, use NewEcosystem
// for that, and handle the errors.
func NewEcosystemOrPanic(ecosystem string) IEcoSystem {
	e, err := NewEcosystem(ecosystem)
	if err != nil {
		panic(err)
	}
	return e
}

var advisoriesCache = utils.NewCacheFactory[[]fixdata.Advisory, autofix.AutofixError]("advisories").GetCache("advisories", 7*24*time.Hour, "0.0.1")
var origAdvisoriesCache = advisoriesCache // for tests

// InitMockAdvisoriesCache initializes a long-lived advisories cache rooted at
// the given directory. It is used by tests to avoid network calls and enable
// deterministic advisory lookups.
func InitMockAdvisoriesCache(dir string) {
	advisoriesCache = utils.NewCacheFactory[[]fixdata.Advisory, autofix.AutofixError](dir+"advisories").GetCache("advisories", 50000*time.Hour, "0.0.1")
}

// ResetAdvisoriesCache restores the global advisories cache to the original
// production configuration (undoing InitMockAdvisoriesCache). Intended for
// test cleanup.
func ResetAdvisoriesCache() {
	advisoriesCache = origAdvisoriesCache
}

// getAdvisoriesInternal fetches security advisories for a given dependency name, version,
// and ecosystem. The `types` parameter specifies the types of advisories to fetch,
// e.g. "malware", "reviewed", "unreviewed". It returns a slice of advisories or
// an error if the request fails.
//
// Note that this function makes multiple calls to the advisories DB, one for each
// type and severity combination. If severities is empty, we treat it as a request for all severities.
func getAdvisoriesInternal(ctx context.Context, depName string, ecosystem IEcoSystem, types, severities []string) ([]fixdata.Advisory, autofix.AutofixError) {
	if err := checkTypesAndSeverities(types, severities); err != nil {
		return nil, err
	}

	// Handle the case of empty severities.
	// This ensures we hit the inner loop.
	if len(severities) == 0 {
		severities = []string{""}
	}
	advisories := []fixdata.Advisory{}
	for _, t := range types {
		for _, s := range severities {
			a1, err := getAdvisoriesCached(ctx, depName, ecosystem, t, s)
			if err != nil {
				return nil, err
			}
			advisories = append(advisories, a1...)
		}
	}
	return advisories, nil
}

func getAdvisoriesCached(ctx context.Context, depName string, ecosystem IEcoSystem, typ string, severity string) ([]fixdata.Advisory, autofix.AutofixError) {
	githubToken := config.GetGitHubToken(ctx)

	advisoriesCacheKey := utils.HashableString(fmt.Sprintf("%s/%s/%s/%s", depName, ecosystem, typ, severity))
	_, advisories, err := advisoriesCache.Get(advisoriesCacheKey, func() ([]fixdata.Advisory, autofix.AutofixError) {
		params := url.Values{}
		params.Add("affects", depName)
		params.Add("ecosystem", ecosystem.String())
		params.Add("type", typ)
		if severity != "" {
			params.Add("severity", severity)
		}

		url := "https://api.github.com/advisories?" + params.Encode()
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
		if err != nil {
			return nil, autofix.NewLogicError("could not create request: " + err.Error())
		}
		req.Header.Set("Accept", "application/vnd.github+json")
		req.Header.Set("X-GitHub-Api-Version", "2022-11-28")

		// Make authenticated calls to the GitHub API if a token is provided
		if githubToken != "" {
			enhancedctx.Logger(ctx).Info("Using GitHub token for fetching advisories")
			req.Header.Set("Authorization", "Bearer "+githubToken)
		} else {
			// We will still try to fetch advisories without authentication,
			// but this may result in a rate limit error or incomplete data.
			// This is logged, but not treated as an error.
			enhancedctx.Logger(ctx).Warn("GitHub token not provided in context or environment, will fetch advisories without authentication")
			// Add an extra metric to track how often this happens
			enhancedctx.Statter(ctx).Counter("advisories_fetch_without_auth", stats.Tags{}, 1)
		}

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return nil, autofix.NewRetryableError(err.Error()) // TODO properly map this!
		}
		defer resp.Body.Close()

		body, _ := io.ReadAll(resp.Body)

		var advisories []fixdata.Advisory

		if err := json.Unmarshal(body, &advisories); err != nil {
			enhancedctx.Logger(
				ctx,
			).WithFields(
				kvp.String("advisories-json-unparsed", string(body)),
			).WithError(
				err,
			).Error("Failed to parse advisories response")
			return nil, autofix.NewLogicError(fmt.Sprintf("could not parse advisories response: %v, body: %s", err.Error(), string(body)))
		}

		return advisories, nil
	}, enhancedctx.Logger(ctx))

	return advisories, err
}

// checkTypesAndSeverities Sanity checks on the types and severities.
// We require at least one type to be specified. For severities, we
// allow an empty list, which means all severities are accepted.
func checkTypesAndSeverities(types []string, severities []string) autofix.AutofixError {
	if len(types) == 0 {
		return autofix.NewLogicError("no advisory type specified")
	}

	// see permitted types and severities here: https://docs.github.com/en/rest/security-advisories/global-advisories?apiVersion=2022-11-28#list-global-security-advisories
	for _, t := range types {
		if !utils.Contains(
			[]string{"malware", "reviewed", "unreviewed"},
			t,
		) {
			return autofix.NewLogicError("searching for invalid advisory type: " + t)
		}
	}

	for _, s := range severities {
		if !utils.Contains(
			[]string{"unknown", "low", "medium", "high", "critical"},
			s,
		) {
			return autofix.NewLogicError("searching for invalid advisory severity: " + s)
		}
	}

	return nil
}

// GetAdvisories retrieves high and critical reviewed advisories for a given dependency and version.
// It also checks if this dependency is malicious. The first return value indicates if this version of
// the dependency is malicious or has any advisories. The second return value is a list of malicious or high/critical advisories
// for this version of the dependency.
func GetAdvisories(ctx context.Context, depName string, version string, ecosystem IEcoSystem) ([]fixdata.Advisory, autofix.AutofixError) {
	nameAndVersion := fmt.Sprintf("%s@%s", depName, version)

	maliciousAdvisories, err := getAdvisoriesInternal(ctx, nameAndVersion, ecosystem, []string{"malware"}, []string{})
	if err != nil {
		return nil, err
	}

	reviewedAdvisories, err := getAdvisoriesInternal(ctx, nameAndVersion, ecosystem, []string{"reviewed"}, []string{"high", "critical"})
	if err != nil {
		return nil, err
	}

	var allAdvisories []fixdata.Advisory
	allAdvisories = append(allAdvisories, maliciousAdvisories...)
	allAdvisories = append(allAdvisories, reviewedAdvisories...)

	return allAdvisories, nil
}

// isPathPrefix checks if targetPath is a prefix of basePath.
func isPathPrefix(basePath, targetPath string) bool {
	rel, err := filepath.Rel(basePath, targetPath)
	return err == nil && !strings.HasPrefix(rel, "..")
}

// Sometimes the root of the codebase is absolute, sometimes it is relative.
// This function resolves a relative path against a base path, ensuring that
// the result is always absolute and cleaned up.
func resolveWithBase(base, rel string) string {
	if filepath.IsAbs(rel) {
		return filepath.Clean(rel)
	}
	return filepath.Clean(filepath.Join(base, rel))
}

func isInsideOfRoot(path string) bool {
	cleanPath := filepath.Clean(path)
	return !strings.HasPrefix(cleanPath, "..")
}
