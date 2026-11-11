package dependencies_test

import (
	"testing"

	dg "github.com/github/dependency-graph-api/gen/go/v1"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFilterSingleLockFile(t *testing.T) {
	dependencyGraphManifestList := []*dg.Manifest{{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "./yarn.lock",
		Type:             "yarn_lock",
		OriginalFilePath: "./yarn.lock",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}, {
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "./package.json",
		Type:             "package_json",
		OriginalFilePath: "./package.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}}

	expected := []*dg.Manifest{{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "./yarn.lock",
		Type:             "yarn_lock",
		OriginalFilePath: "./yarn.lock",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}}

	r := require.New(t)
	actual := dependencies.FilterManifests(log.NewNullLogger(), dependencyGraphManifestList, nil)
	r.ElementsMatch(expected, actual)
}

func TestFilterManifestsWithNestedPaths(t *testing.T) {
	dependencyGraphManifestList := []*dg.Manifest{
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./yarn.lock",
			Type:             "yarn_lock",
			OriginalFilePath: "./yarn.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./package.json",
			Type:             "package_json",
			OriginalFilePath: "./package.json",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./packages/app/yarn.lock",
			Type:             "yarn_lock",
			OriginalFilePath: "./packages/app/yarn.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./packages/app/package.json",
			Type:             "package_json",
			OriginalFilePath: "./packages/app/package.json",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
	}
	expected := []*dg.Manifest{
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./yarn.lock",
			Type:             "yarn_lock",
			OriginalFilePath: "./yarn.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./packages/app/yarn.lock",
			Type:             "yarn_lock",
			OriginalFilePath: "./packages/app/yarn.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
	}

	r := require.New(t)
	actual := dependencies.FilterManifests(log.NewNullLogger(), dependencyGraphManifestList, nil)
	r.ElementsMatch(expected, actual)
}

func TestFilterManifestsWithMixedManifests(t *testing.T) {
	dependencyGraphManifestList := []*dg.Manifest{
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./package-lock.json",
			Type:             "",
			OriginalFilePath: "./package-lock.json",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./package.json",
			Type:             "package_json",
			OriginalFilePath: "./package.json",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
			FilePath:         "./Gemfile",
			Type:             "gemfile",
			OriginalFilePath: "./Gemfile",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
			FilePath:         "./gemfile.lock",
			Type:             "gemfile_lock",
			OriginalFilePath: "./gemfile.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
	}
	expected := []*dg.Manifest{
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./package-lock.json",
			Type:             "",
			OriginalFilePath: "./package-lock.json",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
			FilePath:         "./gemfile.lock",
			Type:             "gemfile_lock",
			OriginalFilePath: "./gemfile.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
	}

	r := require.New(t)
	actual := dependencies.FilterManifests(log.NewNullLogger(), dependencyGraphManifestList, nil)
	r.ElementsMatch(expected, actual)
}

func TestFilterManifestsWithNoType(t *testing.T) {
	dependencyGraphManifestList := []*dg.Manifest{
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./yarn.lock",
			Type:             "",
			OriginalFilePath: "./yarn.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./package.json",
			Type:             "",
			OriginalFilePath: "./package.json",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./packages/app/yarn.lock",
			Type:             "",
			OriginalFilePath: "./packages/app/yarn.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./packages/app/package.json",
			Type:             "",
			OriginalFilePath: "./packages/app/package.json",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
			FilePath:         "./packages/app/Gemfile.lock",
			Type:             "",
			OriginalFilePath: "./packages/app/Gemfile.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
			FilePath:         "./packages/app/Gemfile",
			Type:             "",
			OriginalFilePath: "./packages/app/Gemfile",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
	}
	expected := []*dg.Manifest{
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./yarn.lock",
			Type:             "",
			OriginalFilePath: "./yarn.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
			FilePath:         "./packages/app/yarn.lock",
			Type:             "",
			OriginalFilePath: "./packages/app/yarn.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
			FilePath:         "./packages/app/Gemfile.lock",
			Type:             "",
			OriginalFilePath: "./packages/app/Gemfile.lock",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
	}

	r := require.New(t)
	actual := dependencies.FilterManifests(log.NewNullLogger(), dependencyGraphManifestList, nil)
	r.ElementsMatch(expected, actual)
}

func TestFilterManifestWithNoLockFiles(t *testing.T) {
	dependencyGraphManifestList := []*dg.Manifest{{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "packages/app/package.json",
		Type:             "package_json",
		OriginalFilePath: "packages/app/package.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}, {
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "package.json",
		Type:             "package_json",
		OriginalFilePath: "package.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}}
	expected := []*dg.Manifest{{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "packages/app/package.json",
		Type:             "package_json",
		OriginalFilePath: "packages/app/package.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}, {
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "package.json",
		Type:             "package_json",
		OriginalFilePath: "package.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}}

	r := require.New(t)
	actual := dependencies.FilterManifests(log.NewNullLogger(), dependencyGraphManifestList, nil)
	r.ElementsMatch(expected, actual)
}

func TestFilterWithManifestsToCheck(t *testing.T) {
	manifest1 := &dg.Manifest{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "packages/app/package.json",
		Type:             "package_json",
		OriginalFilePath: "packages/app/package.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}
	manifest2 := &dg.Manifest{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "./yarn.lock",
		Type:             "",
		OriginalFilePath: "./yarn.lock",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}
	manifestList := []*dg.Manifest{manifest1, manifest2}

	testCases := []struct {
		name                 string
		manifestPathsToCheck []string
		expected             []*dg.Manifest
	}{
		{
			name:                 "no ManifestpathsToCheck",
			manifestPathsToCheck: []string{},
			expected:             manifestList,
		},
		{
			name:                 "unmatched ManifestpathsToCheck",
			manifestPathsToCheck: []string{"package.json"},
			expected:             []*dg.Manifest{},
		},
		{
			name:                 "manifestPathsToCheck matches manifest1",
			manifestPathsToCheck: []string{"packages/app/package.json"},
			expected:             []*dg.Manifest{manifest1},
		},
		{
			name:                 "manifestPathsToCheck matches manifest2",
			manifestPathsToCheck: []string{"yarn.lock"},
			expected:             []*dg.Manifest{manifest2},
		},
		{
			name:                 "manifestPathsToCheck matches both manifests",
			manifestPathsToCheck: []string{"packages/app/package.json", "yarn.lock"},
			expected:             manifestList,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result := dependencies.FilterManifests(log.NewNullLogger(), manifestList, &dependencies.FilterOptions{ManifestPathsToCheck: tc.manifestPathsToCheck})
			assert.Equal(t, tc.expected, result)
		})
	}
}

func TestFilterWithNonLockFileEditedAndLockFileNotEdited(t *testing.T) {
	gemfile := &dg.Manifest{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
		FilePath:         "./Gemfile",
		Type:             "gemfile",
		OriginalFilePath: "./Gemfile.lock",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}
	gemfileLock := &dg.Manifest{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
		FilePath:         "./Gemfile.lock",
		Type:             "gemfile_lock",
		OriginalFilePath: "./Gemfile.lock",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}
	gemfileLockNested := &dg.Manifest{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
		FilePath:         "./packages/app/Gemfile.lock",
		Type:             "",
		OriginalFilePath: "./packages/app/Gemfile.lock",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}
	packageFile := &dg.Manifest{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "packages/app/package.json",
		Type:             "package_json",
		OriginalFilePath: "packages/app/package.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}
	packageFileLock := &dg.Manifest{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "packages/app/package-lock.json",
		Type:             "package_lock_json",
		OriginalFilePath: "packages/app/package-lock.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}
	yarnLock := &dg.Manifest{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "./yarn.lock",
		Type:             "",
		OriginalFilePath: "./yarn.lock",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}
	requirementsText := &dg.Manifest{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_PIP,
		FilePath:         "./requirements.txt",
		Type:             "",
		OriginalFilePath: "./requirements.txt",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}

	testCases := []struct {
		name                 string
		manifestList         []*dg.Manifest
		manifestPathsToCheck []string
		expected             []*dg.Manifest
	}{
		{
			name:                 "returns empty no matching Gemfile",
			manifestList:         []*dg.Manifest{gemfile, gemfileLock},
			manifestPathsToCheck: []string{"Gemfile"},
			expected:             []*dg.Manifest{},
		},
		{
			name:                 "returns empty when no matching package.json",
			manifestList:         []*dg.Manifest{packageFile, packageFileLock},
			manifestPathsToCheck: []string{"package.json", "package-lock.json"},
			expected:             []*dg.Manifest{},
		},
		{
			name:                 "matches nested gemfileLock",
			manifestList:         []*dg.Manifest{gemfile, gemfileLock, gemfileLockNested},
			manifestPathsToCheck: []string{"Gemfile", "packages/app/Gemfile.lock"},
			expected:             []*dg.Manifest{gemfileLockNested},
		},
		{
			name:                 "matches both lockfiles yarnlock and Gemfile.lock",
			manifestList:         []*dg.Manifest{gemfileLock, yarnLock},
			manifestPathsToCheck: []string{"Gemfile.lock", "yarn.lock"},
			expected:             []*dg.Manifest{gemfileLock, yarnLock},
		},
		{
			name:                 "only matches Gemfile.Lock",
			manifestList:         []*dg.Manifest{gemfileLock, gemfile},
			manifestPathsToCheck: []string{"Gemfile.lock", "gemfile"},
			expected:             []*dg.Manifest{gemfileLock},
		},
		{
			name:                 "matches Gemfile.Lock and requirements.txt",
			manifestList:         []*dg.Manifest{gemfileLock, requirementsText},
			manifestPathsToCheck: []string{"Gemfile.lock", "requirements.txt"},
			expected:             []*dg.Manifest{gemfileLock, requirementsText},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result := dependencies.FilterManifests(log.NewNullLogger(), tc.manifestList, &dependencies.FilterOptions{ManifestPathsToCheck: tc.manifestPathsToCheck})
			assert.ElementsMatch(t, tc.expected, result)
		})
	}
}

func TestFilterWithManifestOptions(t *testing.T) {
	testdata := []*dg.Manifest{{
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "/package-lock.json",
		Type:             "",
		OriginalFilePath: "/package-lock.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}, {
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "./package.json",
		Type:             "package_json",
		OriginalFilePath: "./package.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}, {
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
		FilePath:         "./Gemfile",
		Type:             "gemfile",
		OriginalFilePath: "./Gemfile",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}, {
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
		FilePath:         "./gemfile.lock",
		Type:             "gemfile_lock",
		OriginalFilePath: "./gemfile.lock",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}, {
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "./node_modules/foo/package-lock.json",
		Type:             "package_lock_json",
		OriginalFilePath: "./node_modules/foo/package-lock.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}, {
		PackageManager:   dg.PackageManager_PACKAGE_MANAGER_NPM,
		FilePath:         "./node_modules/bar/package.json",
		Type:             "package_json",
		OriginalFilePath: "./node_modules/bar/package.json",
		Source:           "dependency graph",
		Dependencies:     []*dg.Manifest_Dependency{},
	}}
	r := require.New(t)

	result := dependencies.FilterManifests(
		log.NewNullLogger(),
		testdata,
		&dependencies.FilterOptions{
			LockFilesOnly:       true,
			RootManifestsOnly:   true,
			AdditionalManifests: []string{"./node_modules/bar/package.json"},
		},
	)

	r.Len(result, 3)
	r.ElementsMatch([]*dg.Manifest{testdata[0], testdata[3], testdata[5]}, result)
}

func TestFilterPackageManagersWithoutCDLicenses(t *testing.T) {
	testdata := []*dg.Manifest{
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_ACTIONS,
			FilePath:         ".github/workflows/build.yaml",
			OriginalFilePath: ".github/workflows/build.yaml",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_PUB,
			FilePath:         ".pubspec.yaml",
			OriginalFilePath: ".pubspec.yaml",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
		{
			PackageManager:   dg.PackageManager_PACKAGE_MANAGER_UNKNOWN,
			FilePath:         ".foo.yaml",
			OriginalFilePath: ".foo.yaml",
			Source:           "dependency graph",
			Dependencies:     []*dg.Manifest_Dependency{},
		},
	}

	result := dependencies.FilterManifests(log.NewNullLogger(), testdata, nil)
	require.Len(t, result, 0)
}
