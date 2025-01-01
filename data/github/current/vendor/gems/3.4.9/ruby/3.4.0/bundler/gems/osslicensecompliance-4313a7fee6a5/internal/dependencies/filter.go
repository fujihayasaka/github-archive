package dependencies

import (
	"fmt"
	"path/filepath"
	"slices"
	"strings"
	"sync"

	dg "github.com/github/dependency-graph-api/gen/go/v1"
	"github.com/github/github-telemetry-go/log"
)

var packageManagerLockFileMap = map[string]dg.PackageManager{
	"gemfile.lock":                   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
	"gemspec":                        dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
	"package-lock.json":              dg.PackageManager_PACKAGE_MANAGER_NPM,
	"yarn.lock":                      dg.PackageManager_PACKAGE_MANAGER_NPM,
	"vendored_javascript_dependency": dg.PackageManager_PACKAGE_MANAGER_NPM,
	"requirements_txt":               dg.PackageManager_PACKAGE_MANAGER_PIP,
	"pipfile.lock":                   dg.PackageManager_PACKAGE_MANAGER_PIP,
	"setup.py":                       dg.PackageManager_PACKAGE_MANAGER_PIP,
	"pyproject.toml":                 dg.PackageManager_PACKAGE_MANAGER_PIP,
	"poetry.lock":                    dg.PackageManager_PACKAGE_MANAGER_PIP,
	"pom.xml":                        dg.PackageManager_PACKAGE_MANAGER_MAVEN,
	"nuspec":                         dg.PackageManager_PACKAGE_MANAGER_NUGET,
	"msbuild":                        dg.PackageManager_PACKAGE_MANAGER_NUGET,
	"package.config":                 dg.PackageManager_PACKAGE_MANAGER_NUGET,
	"composer.lock":                  dg.PackageManager_PACKAGE_MANAGER_COMPOSER,
	"go.mod":                         dg.PackageManager_PACKAGE_MANAGER_GOMOD,
	"cargo.lock":                     dg.PackageManager_PACKAGE_MANAGER_RUST,
	"pubspec.lock":                   dg.PackageManager_PACKAGE_MANAGER_PUB,
}

var createManifestLockFilesOnce = sync.OnceValue(func() map[string]struct{} {
	manifestLockFiles := make(map[string]struct{})
	replacer := strings.NewReplacer(".", "_", "-", "_")
	for key := range packageManagerLockFileMap {
		manifestLockFiles[replacer.Replace(key)] = struct{}{}
	}
	return manifestLockFiles
})

// isLockFile returns true if the given manifest type is a _known_ lock file.
func isLockFile(manifestType string) bool {
	_, ok := createManifestLockFilesOnce()[manifestType]
	return ok
}

// FilterOptions is a struct that holds the options for filtering manifests.
type FilterOptions struct {
	ManifestPathsToCheck []string
	LockFilesOnly        bool
	RootManifestsOnly    bool
	AdditionalManifests  []string
}

// ManifestSort is a struct that holds a list of lock file and package manifests.
type ManifestSort struct {
	LockFileManifests []*dg.Manifest
	PackageManifest   []*dg.Manifest
}

// FilterManifests filters a list of manifests to only include manifests that
// provide exact dependencies and match manifestPathsToCheck.
// This is how filtering is decided:
//   - If options is non-nil, those options will additionally filter the manifests used
//   - If manifestPathsToCheck is not empty
//     -- the file path must match one of the manifestsToCheck
//     -- if package file is changed and lock file exists in same directory, but is not changed, package file is ignored
//   - If there is both a package file and a lock file -> only include the lock file
//   - If there is only a package file -> include the package file
//   - If there is only a lock file -> include the lock file
//   - If there is more than one lock file -> include ALL lock files
func FilterManifests(logger log.Logger, manifests []*dg.Manifest, filteropts *FilterOptions) []*dg.Manifest {
	ops := &FilterOptions{}
	if filteropts != nil {
		ops = filteropts
	}
	// First build a map of all the manifests by their file path
	manifestMap := make(map[string]map[string]*ManifestSort)
	directories := make([]string, 0)
	hasManifestsToCheck := len(ops.ManifestPathsToCheck) > 0
	for _, manifest := range manifests {
		// Split the path into the directory and manifest
		dir, file := filepath.Split(manifest.FilePath)

		// Sometimes type is empty, but we can work around that with a replace
		manifestType := manifest.Type
		if manifest.Type == "" {
			manifestType = manifestTypeFromFileName(file)
		}

		// Handle the manifest filtering options
		if ops.LockFilesOnly && !isLockFile(manifestType) || (ops.RootManifestsOnly && dir != "./" && dir != "" && dir != "/") {
			if !slices.Contains(ops.AdditionalManifests, manifest.FilePath) {
				continue
			}
		}

		if hasManifestsToCheck {
			filePath := strings.TrimPrefix(manifest.FilePath, "./")
			if !isLockFile(manifest.Type) && hasUneditedLockfile(manifest, manifests, ops.ManifestPathsToCheck) {
				ops.ManifestPathsToCheck = slices.DeleteFunc(ops.ManifestPathsToCheck, func(manifestToCheck string) bool {
					return filePath == manifestToCheck
				})
			}
			if !slices.Contains(ops.ManifestPathsToCheck, filePath) {
				continue
			}
		}

		if _, ok := manifestMap[dir]; !ok {
			manifestMap[dir] = make(map[string]*ManifestSort)
			for env := range dg.PackageManager_value {
				manifestMap[dir][env] = &ManifestSort{
					LockFileManifests: []*dg.Manifest{},
					PackageManifest:   []*dg.Manifest{},
				}
			}

			directories = append(directories, dir)
		}

		if _, ok := isFilteredPackageManagers[manifest.GetPackageManager()]; ok {
			continue
		}

		manifestEnvironment := manifest.GetPackageManager().String()

		// Based on if the file is a lock file or not, add it to the appropriate map
		if isLockFile(manifestType) {
			logger.Debug(fmt.Sprintf("Adding manifest %s to lock file map", manifest.FilePath))
			manifestMap[dir][manifestEnvironment].LockFileManifests = append(manifestMap[dir][manifestEnvironment].LockFileManifests, manifest)
		} else {
			logger.Debug(fmt.Sprintf("Adding manifest %s to package file map", manifest.FilePath))
			manifestMap[dir][manifestEnvironment].PackageManifest = append(manifestMap[dir][manifestEnvironment].PackageManifest, manifest)
		}
	}

	filteredManifests := make([]*dg.Manifest, 0)

	// Go through all the directories and collect the manifests
	for _, dir := range directories {
		// Go through all the environments and collect the manifests
		for env := range dg.PackageManager_value {
			// If there are no lock files, use the package file
			if len(manifestMap[dir][env].LockFileManifests) == 0 {
				filteredManifests = append(filteredManifests, manifestMap[dir][env].PackageManifest...)
			} else {
				filteredManifests = append(filteredManifests, manifestMap[dir][env].LockFileManifests...)
			}
		}
	}

	return filteredManifests
}

// manifestTypeFromFileName returns the manifest type based on the file name.
func manifestTypeFromFileName(fileName string) string {
	manifestType := strings.ToLower(strings.ReplaceAll(strings.ReplaceAll(fileName, ".", "_"), "-", "_"))
	return manifestType
}

// packageManagerFromFile returns the package manager type based on the filename
func packageManagerFromFile(fullFilePath string) dg.PackageManager {
	file := strings.ToLower(filepath.Base(fullFilePath))
	result, ok := packageManagerLockFileMap[file]
	if !ok {
		return dg.PackageManager_PACKAGE_MANAGER_UNKNOWN
	}
	return result
}

// hasUneditedLockfile returns true if the manifest file provided has a lock file for the same package manager
// in the same directory which is not present in `manifestPathsToCheck`
func hasUneditedLockfile(manifest *dg.Manifest, manifests []*dg.Manifest, manifestPathsToCheck []string) bool {
	filePath := strings.TrimPrefix(manifest.FilePath, "./")
	manifestDir, _ := filepath.Split(filePath)

	lockFileExistsInSameDirectory := false
	for _, m := range manifests {
		if isLockFile(m.Type) &&
			m.PackageManager == manifest.PackageManager &&
			strings.HasPrefix(m.FilePath, manifestDir) {
			lockFileExistsInSameDirectory = true
		}
	}
	if !lockFileExistsInSameDirectory {
		return false
	}

	for _, manifestToCheck := range manifestPathsToCheck {
		manifestToCheckDir, file := filepath.Split(manifestToCheck)
		manifestType := manifestTypeFromFileName(file)
		if isLockFile(manifestType) {
			continue
		}
		packageManager := packageManagerFromFile(file)
		lockFileIsIncludedInCheck := (manifestDir == manifestToCheckDir) && (packageManager == manifest.PackageManager)
		if lockFileIsIncludedInCheck {
			return false
		}
	}

	return true
}
