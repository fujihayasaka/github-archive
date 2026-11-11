package dependencies_test

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"testing"

	dg "github.com/github/dependency-graph-api/gen/go/v1"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type MockDependenciesGetter struct {
	Request  *dg.GetDependenciesForRepositoryRequest
	Response *dg.GetDependenciesForRepositoryResponse
}

func (mdg *MockDependenciesGetter) GetDependenciesForRepository(_ context.Context, req *dg.GetDependenciesForRepositoryRequest) (*dg.GetDependenciesForRepositoryResponse, error) {
	mdg.Request = req
	return mdg.Response, nil
}

type MockPkgGetter struct {
	ListPkgRequest      *dg.ListPackageVersionsRequest
	ListPkgResponse     *dg.ListPackageVersionsResponse
	ListPkgError        error
	ListPkgRequestCount int
}

func (mpg *MockPkgGetter) ListPackageVersions(_ context.Context, req *dg.ListPackageVersionsRequest) (*dg.ListPackageVersionsResponse, error) {
	mpg.ListPkgRequestCount++
	mpg.ListPkgRequest = req
	if mpg.ListPkgError != nil {
		return nil, mpg.ListPkgError
	}
	return mpg.ListPkgResponse, nil
}

type MockShaDiffGetter struct {
	Request  *dg.GetSnapshotsDiffRequest
	Response *dg.GetSnapshotsDiffResponse
}

func (msdg *MockShaDiffGetter) GetSnapshotsDiff(_ context.Context, req *dg.GetSnapshotsDiffRequest) (*dg.GetSnapshotsDiffResponse, error) {
	msdg.Request = req
	return msdg.Response, nil
}

func TestGetDiffDependenciesForRepo_ReturnsAddedDependencyPackages(t *testing.T) {
	mockShaDiffGetter := &MockShaDiffGetter{
		Response: &dg.GetSnapshotsDiffResponse{
			RepositoryId: 1,
			BaseSha:      "base-sha",
			TargetSha:    "target-sha",
			ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
					FilePath: "./Gemfile.lock",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "foo/bar",
							TargetVersion: "1.0.1",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "BSD-3-Clause",
							RepoNwo:       "foo/bar-gem",
						},
						{
							Name:        "removed/package",
							BaseVersion: "1.0.0",
							ChangeType:  dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_REMOVED,
							License:     "MIT",
						},
					},
				},
			},
		},
	}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	dependentPackages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 0, 0, 0)
	require.NoError(t, err)

	assert.Equal(t, uint64(1), mockShaDiffGetter.Request.GetRepositoryId())
	assert.Equal(t, "base-sha", mockShaDiffGetter.Request.GetBaseSha())
	assert.Equal(t, "target-sha", mockShaDiffGetter.Request.GetTargetSha())
	assert.True(t, mockShaDiffGetter.Request.GetDecomposeUpdates(), "DecomposeUpdates field should be true in request")
	assert.Nil(t, mockShaDiffGetter.Request.GetLimitToFiles(), "LimitToFiles field should not be present in request")
	assert.Equal(t, uint64(0), mockShaDiffGetter.Request.GetTargetRepositoryId(), "TargetRepositoryId should be zero for same-repo PRs")

	assert.Equal(
		t,
		map[string]models.Package{
			strconv.Itoa(int(proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS)) + ":foo/bar@1.0.1": {
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
				Name:           "foo/bar",
				Version:        "1.0.1",
				License:        "BSD-3-Clause",
				LicenseVersion: "1.0.1",
				Manifests:      []string{"./Gemfile.lock"},
				PackageRepoNWO: "foo/bar-gem",
			},
		},
		dependentPackages,
	)
}

func TestGetDiffDependenciesForRepo_PassesForkRepositoryID(t *testing.T) {
	mockShaDiffGetter := &MockShaDiffGetter{
		Response: &dg.GetSnapshotsDiffResponse{},
	}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	_, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 42, 0, 0)
	require.NoError(t, err)

	assert.Equal(t, uint64(1), mockShaDiffGetter.Request.GetRepositoryId())
	assert.Equal(t, uint64(42), mockShaDiffGetter.Request.GetTargetRepositoryId())
}

func TestGetDiffDependenciesForRepo_AppendsVToGoPackagesExactVersion(t *testing.T) {
	mockShaDiffGetter := &MockShaDiffGetter{
		Response: &dg.GetSnapshotsDiffResponse{
			RepositoryId: 1,
			BaseSha:      "base-sha",
			TargetSha:    "target-sha",
			ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_GOMOD,
					FilePath: "./go.mod",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "foo/no_v",
							TargetVersion: "1.0.1",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "BSD-3-Clause",
						},
						{
							Name:          "foo/has_v",
							TargetVersion: "v1.0.1",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "MIT",
						},
					},
				},
			},
		},
	}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	dependentPackages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 0, 0, 0)
	require.NoError(t, err)

	assert.Equal(t, models.Version("v1.0.1"), dependentPackages["7:foo/no_v@v1.0.1"].Version)
	assert.Equal(t, models.Version("v1.0.1"), dependentPackages["7:foo/no_v@v1.0.1"].LicenseVersion)

	assert.Equal(t, models.Version("v1.0.1"), dependentPackages["7:foo/has_v@v1.0.1"].Version)
	assert.Equal(t, models.Version("v1.0.1"), dependentPackages["7:foo/has_v@v1.0.1"].LicenseVersion)

	assert.Equal(
		t,
		map[string]models.Package{
			strconv.Itoa(int(proto.PackageManager_PACKAGE_MANAGER_GOMOD)) + ":foo/no_v@v1.0.1": {
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD,
				Name:           "foo/no_v",
				Version:        "v1.0.1",
				License:        "BSD-3-Clause",
				LicenseVersion: "v1.0.1",
				Manifests:      []string{"./go.mod"},
			},
			strconv.Itoa(int(proto.PackageManager_PACKAGE_MANAGER_GOMOD)) + ":foo/has_v@v1.0.1": {
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD,
				Name:           "foo/has_v",
				Version:        "v1.0.1",
				License:        "MIT",
				LicenseVersion: "v1.0.1",
				Manifests:      []string{"./go.mod"},
			},
		},
		dependentPackages,
	)
}

func TestGetDiffDependenciesForRepo_MultipleManifests(t *testing.T) {
	mockShaDiffGetter := &MockShaDiffGetter{
		Response: &dg.GetSnapshotsDiffResponse{
			RepositoryId: 1,
			BaseSha:      "base-sha",
			TargetSha:    "target-sha",
			ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_GOMOD,
					FilePath: "./go.mod",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "foo/bar",
							TargetVersion: "1.0.1",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "BSD-3-Clause",
						},
					},
				},
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_GOMOD,
					FilePath: "./tools/go.mod",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "foo/bar",
							TargetVersion: "1.0.1",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "BSD-3-Clause",
						},
					},
				},
			},
		},
	}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	dependentPackages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 0, 0, 0)
	require.NoError(t, err)

	assert.Equal(
		t,
		map[string]models.Package{
			strconv.Itoa(int(proto.PackageManager_PACKAGE_MANAGER_GOMOD)) + ":foo/bar@v1.0.1": {
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD,
				Name:           "foo/bar",
				Version:        "v1.0.1",
				License:        "BSD-3-Clause",
				LicenseVersion: "v1.0.1",
				Manifests:      []string{"./go.mod", "./tools/go.mod"},
			},
		},
		dependentPackages,
	)
}

func TestGetDiffDependenciesForRepo_FilterOutUnwantedPackageManagers(t *testing.T) {
	mockShaDiffGetter := &MockShaDiffGetter{
		Response: &dg.GetSnapshotsDiffResponse{
			RepositoryId: 1,
			BaseSha:      "base-sha",
			TargetSha:    "target-sha",
			ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
					FilePath: "./Gemfile.lock",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "good-gem",
							TargetVersion: "1.0.1",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "MIT",
						},
					},
				},
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_ACTIONS,
					FilePath: "./.github/workflows/action.yml",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "github-action",
							TargetVersion: "v1.0.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "Apache-2.0",
						},
					},
				},
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_PUB,
					FilePath: "./pubspec.yaml",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "flutter-package",
							TargetVersion: "2.0.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "BSD-3-Clause",
						},
					},
				},
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_UNKNOWN,
					FilePath: "./unknown.txt",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "unknown-package",
							TargetVersion: "1.0.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "GPL-3.0",
						},
					},
				},
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_SWIFT,
					FilePath: "./Package.swift",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "swift-package",
							TargetVersion: "1.0.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "MIT",
						},
					},
				},
			},
		},
	}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	dependentPackages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 0, 0, 0)
	require.NoError(t, err)

	// Should only contain the rubygems package, filtered package managers should be excluded
	assert.Equal(
		t,
		map[string]models.Package{
			strconv.Itoa(int(proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS)) + ":good-gem@1.0.1": {
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
				Name:           "good-gem",
				Version:        "1.0.1",
				License:        "MIT",
				LicenseVersion: "1.0.1",
				Manifests:      []string{"./Gemfile.lock"},
			},
		},
		dependentPackages,
	)

	// Verify that dependencies from filtered package managers are not included
	for key := range dependentPackages {
		assert.NotContains(t, key, "github-action", "GitHub Actions packages should be filtered out")
		assert.NotContains(t, key, "flutter-package", "Pub packages should be filtered out")
		assert.NotContains(t, key, "unknown-package", "Unknown package manager packages should be filtered out")
	}
}

func TestGetDiffDependenciesForRepo_UnknownManifestWithPURLs(t *testing.T) {
	// This test simulates dependency snapshot submissions that use unrecognized manifest names
	// (like "purls") but include valid PURLs that allow us to determine the ecosystem
	mockShaDiffGetter := &MockShaDiffGetter{
		Response: &dg.GetSnapshotsDiffResponse{
			RepositoryId: 1,
			BaseSha:      "base-sha",
			TargetSha:    "target-sha",
			ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_UNKNOWN,
					FilePath: "purls",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "lodash",
							TargetVersion: "4.17.21",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "MIT",
							TargetPurl:    "pkg:npm/lodash@4.17.21",
						},
						{
							Name:          "com.google.guava:guava",
							TargetVersion: "31.0-jre",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "Apache-2.0",
							TargetPurl:    "pkg:maven/com.google.guava/guava@31.0-jre",
						},
						{
							Name:          "actions/checkout",
							TargetVersion: "v3",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "MIT",
							TargetPurl:    "pkg:githubactions/actions/checkout@v3",
						},
						{
							Name:          "some-unsupported-type",
							TargetVersion: "1.0.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "BSD-3-Clause",
							TargetPurl:    "pkg:unknowntype/some-unsupported-type@1.0.0",
						},
						{
							Name:          "no-purl-package",
							TargetVersion: "2.0.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "GPL-2.0",
							// No TargetPurl - should be filtered out
						},
					},
				},
			},
		},
	}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	dependentPackages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 0, 0, 0)
	require.NoError(t, err)

	assert.Len(t, dependentPackages, 2)

	// Should contain npm and maven packages (supported ecosystems extracted from PURLs)
	// Should NOT contain actions, unknown type, or packages without PURLs
	npmKey := strconv.Itoa(int(proto.PackageManager_PACKAGE_MANAGER_NPM)) + ":lodash@4.17.21"
	assert.Contains(t, dependentPackages, npmKey)
	assert.Equal(t, models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "lodash",
		Version:        "4.17.21",
		License:        "MIT",
		LicenseVersion: "4.17.21",
		Manifests:      []string{"purls"},
	}, dependentPackages[npmKey])

	mavenKey := strconv.Itoa(int(proto.PackageManager_PACKAGE_MANAGER_MAVEN)) + ":com.google.guava:guava@31.0-jre"
	assert.Contains(t, dependentPackages, mavenKey)
	assert.Equal(t, models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_MAVEN,
		Name:           "com.google.guava:guava",
		Version:        "31.0-jre",
		License:        "Apache-2.0",
		LicenseVersion: "31.0-jre",
		Manifests:      []string{"purls"},
	}, dependentPackages[mavenKey])

	for key := range dependentPackages {
		assert.NotContains(t, key, "actions/checkout", "GitHub Actions should be filtered out even from UNKNOWN manifests")
		assert.NotContains(t, key, "some-unsupported-type", "Unsupported PURL types should be filtered out")
		assert.NotContains(t, key, "no-purl-package", "Packages without PURLs in UNKNOWN manifests should be filtered out")
	}
}

func TestGetDiffDependenciesForRepo_GetsMissingLicenseFromLatestVersion(t *testing.T) {
	tests := []struct {
		name    string
		version string
	}{
		{
			name:    "exact version",
			version: "4.17.0",
		},
		{
			name:    "inexact version constraint",
			version: "~> 1.48",
		},
		{
			name:    "wildcard version",
			version: "*",
		},
		{
			name:    "empty version",
			version: "",
		},
	}

	packageManager := dg.PackageManager_PACKAGE_MANAGER_NPM
	packageName := "test-package"
	latestVersion := "2.0.0"
	expectedLicense := "MIT"

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockShaDiffGetter := &MockShaDiffGetter{
				Response: &dg.GetSnapshotsDiffResponse{
					RepositoryId: 1,
					BaseSha:      "base-sha",
					TargetSha:    "target-sha",
					ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
						{
							Type:     packageManager,
							FilePath: "./manifest.lock",
							Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
								{
									Name:          packageName,
									TargetVersion: tt.version,
									ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
									License:       "",
								},
							},
						},
					},
				},
			}

			mockPkgGetter := &MockPkgGetter{
				ListPkgResponse: &dg.ListPackageVersionsResponse{
					PackageVersions: []*dg.ListPackageVersionsResponse_PackageVersion{
						{PackageVersion: "1.0.0", PackageLicense: "GPL-2"},
						{PackageVersion: "1.1.0", PackageLicense: "Apache-2.0"},
						{PackageVersion: "2.0.0", PackageLicense: expectedLicense},
					},
				},
			}

			dependencyGetter := dependencies.DependencyGetter{
				ShaDiffGetter: mockShaDiffGetter,
				PackageGetter: mockPkgGetter,
				Logger:        log.NewNullLogger(),
				Metrics:       stats.NullStatter,
			}

			packages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 0, 0, 0)
			require.NoError(t, err)

			key := fmt.Sprintf("%d:%s@%s", packageManager, strings.ToLower(packageName), tt.version)
			pkg, ok := packages[key]
			require.True(t, ok, "Package should be in result")

			assert.Equal(t, expectedLicense, pkg.License, "Should have license from latest version")
			assert.Equal(t, models.Version(latestVersion), pkg.LicenseVersion, "LicenseVersion should be latest version")
			assert.True(t, pkg.CalculatedLicense, "CalculatedLicense should be true for inexact version")
		})
	}
}

func TestGetDiffDependenciesForRepo_MissingLicense_NoLicenseOnLatest_RemainsEmpty(t *testing.T) {
	mockShaDiffGetter := &MockShaDiffGetter{
		Response: &dg.GetSnapshotsDiffResponse{
			RepositoryId: 1,
			BaseSha:      "base-sha",
			TargetSha:    "target-sha",
			ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_NPM,
					FilePath: "./package.json",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "test-package",
							TargetVersion: "1.0.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "",
						},
					},
				},
			},
		},
	}

	mockPkgGetter := &MockPkgGetter{
		ListPkgResponse: &dg.ListPackageVersionsResponse{
			PackageVersions: []*dg.ListPackageVersionsResponse_PackageVersion{
				{PackageVersion: "1.0.0", PackageLicense: ""},
				{PackageVersion: "2.0.0", PackageLicense: ""},
			},
		},
	}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		PackageGetter: mockPkgGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	packages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 0, 0, 0)
	require.NoError(t, err)

	key := fmt.Sprintf("%d:%s@%s", dg.PackageManager_PACKAGE_MANAGER_NPM, "test-package", "1.0.0")
	pkg, ok := packages[key]
	require.True(t, ok)

	assert.Equal(t, "", pkg.License, "License should remain empty when not available")
	assert.Equal(t, models.Version("1.0.0"), pkg.LicenseVersion, "LicenseVersion must be original version")
	assert.False(t, pkg.CalculatedLicense, "CalculatedLicense should be false when no license found")
}

func TestGetDiffDependenciesForRepo_DoesntMakeDuplicateLatestPackageVersionRequests(t *testing.T) {
	mockShaDiffGetter := &MockShaDiffGetter{
		Response: &dg.GetSnapshotsDiffResponse{
			RepositoryId: 1,
			BaseSha:      "base-sha",
			TargetSha:    "target-sha",
			ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_NPM,
					FilePath: "./package.json",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "lodash",
							TargetVersion: "^4.17.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "",
						},
					},
				},
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_NPM,
					FilePath: "./src/utils/package.json",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "lodash",
							TargetVersion: "^4.17.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "",
						},
						{
							Name:          "lodash",
							TargetVersion: "~4.17.10",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "",
						},
					},
				},
			},
		},
	}

	mockPkgGetter := &MockPkgGetter{
		ListPkgResponse: &dg.ListPackageVersionsResponse{
			PackageVersions: []*dg.ListPackageVersionsResponse_PackageVersion{
				{PackageVersion: "4.17.21", PackageLicense: "MIT"},
			},
		},
	}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		PackageGetter: mockPkgGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	packages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 0, 0, 0)
	require.NoError(t, err)
	require.Len(t, packages, 2, "Should have 2 unique version constraints")
	assert.Equal(t, "MIT", packages[fmt.Sprintf("%d:%s@%s", dg.PackageManager_PACKAGE_MANAGER_NPM, "lodash", "^4.17.0")].License)
	assert.Equal(t, models.Version("4.17.21"), packages[fmt.Sprintf("%d:%s@%s", dg.PackageManager_PACKAGE_MANAGER_NPM, "lodash", "^4.17.0")].LicenseVersion)
	assert.Equal(t, "MIT", packages[fmt.Sprintf("%d:%s@%s", dg.PackageManager_PACKAGE_MANAGER_NPM, "lodash", "~4.17.10")].License)
	assert.Equal(t, models.Version("4.17.21"), packages[fmt.Sprintf("%d:%s@%s", dg.PackageManager_PACKAGE_MANAGER_NPM, "lodash", "~4.17.10")].LicenseVersion)

	assert.Equal(t, 1, mockPkgGetter.ListPkgRequestCount, "Should only call ListPackageVersions once (3 packages but all same name)")
}

func TestGetDiffDependenciesForRepo_MissingLicenseUsesHighestSemverWithLicense(t *testing.T) {
	mockShaDiffGetter := &MockShaDiffGetter{
		Response: &dg.GetSnapshotsDiffResponse{
			RepositoryId: 1,
			BaseSha:      "base-sha",
			TargetSha:    "target-sha",
			ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_NPM,
					FilePath: "./package.json",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "test-package",
							TargetVersion: "^2.0.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "",
						},
					},
				},
			},
		},
	}

	mockPkgGetter := &MockPkgGetter{
		ListPkgResponse: &dg.ListPackageVersionsResponse{
			PackageVersions: []*dg.ListPackageVersionsResponse_PackageVersion{
				{PackageVersion: "2.0.0", PackageLicense: "MIT"},
				{PackageVersion: "4.0.0", PackageLicense: "GPL"},
				{PackageVersion: "5.0.0", PackageLicense: ""},
				{PackageVersion: "undefined", PackageLicense: "Apache"},
			},
		},
	}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		PackageGetter: mockPkgGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	packages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 0, 0, 0)
	require.NoError(t, err)

	key := fmt.Sprintf("%d:%s@%s", dg.PackageManager_PACKAGE_MANAGER_NPM, "test-package", "^2.0.0")
	pkg, ok := packages[key]
	require.True(t, ok, "Package should be in result")

	assert.Equal(t, "GPL", pkg.License, "Should use license from 4.0.0 (highest semver WITH license)")
	assert.Equal(t, models.Version("4.0.0"), pkg.LicenseVersion, "LicenseVersion should be 4.0.0")
	assert.True(t, pkg.CalculatedLicense, "CalculatedLicense should be true")
}

func TestGetDiffDependenciesForRepo_MissingLicenseUsesNonSemverIfNoSemver(t *testing.T) {
	mockShaDiffGetter := &MockShaDiffGetter{
		Response: &dg.GetSnapshotsDiffResponse{
			RepositoryId: 1,
			BaseSha:      "base-sha",
			TargetSha:    "target-sha",
			ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_NPM,
					FilePath: "./package.json",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "non-semver-package",
							TargetVersion: "latest",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "",
						},
					},
				},
			},
		},
	}

	mockPkgGetter := &MockPkgGetter{
		ListPkgResponse: &dg.ListPackageVersionsResponse{
			PackageVersions: []*dg.ListPackageVersionsResponse_PackageVersion{
				{PackageVersion: "earliest", PackageLicense: "GPL"},
				{PackageVersion: "latest", PackageLicense: "MIT"},
			},
		},
	}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		PackageGetter: mockPkgGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	packages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 0, 0, 0)
	require.NoError(t, err)

	key := fmt.Sprintf("%d:%s@%s", dg.PackageManager_PACKAGE_MANAGER_NPM, "non-semver-package", "latest")
	pkg, ok := packages[key]
	require.True(t, ok, "Package should be in result")

	assert.Equal(t, "MIT", pkg.License, "Should use last version from list when no semver versions exist")
	assert.Equal(t, models.Version("latest"), pkg.LicenseVersion, "LicenseVersion should be the last non-semver version in original order")
	assert.True(t, pkg.CalculatedLicense, "CalculatedLicense should be true")
}

// For case where we actually get the license from DG-API.
func TestGetDiffDependenciesForRepo_InexactVersionInDiffResponseLicenseResolvesVersion(t *testing.T) {
	mockShaDiffGetter := &MockShaDiffGetter{
		Response: &dg.GetSnapshotsDiffResponse{
			RepositoryId: 1,
			BaseSha:      "base-sha",
			TargetSha:    "target-sha",
			ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_NPM,
					FilePath: "./package.json",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "future-package",
							TargetVersion: "^1.0.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "MIT",
						},
					},
				},
			},
		},
	}

	mockPkgGetter := &MockPkgGetter{}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		PackageGetter: mockPkgGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	packages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha", 0, 0, 0)
	require.NoError(t, err)

	key := fmt.Sprintf("%d:%s@%s", dg.PackageManager_PACKAGE_MANAGER_NPM, "future-package", "^1.0.0")
	pkg, ok := packages[key]
	require.True(t, ok, "Package should be in result")

	assert.Equal(t, "MIT", pkg.License, "Should keep license from SnapshotsDiff")
	assert.Equal(t, models.Version("^1.0.0"), pkg.LicenseVersion, "LicenseVersion should remain the inexact version")
	assert.False(t, pkg.CalculatedLicense, "CalculatedLicense should be false - license came from API")

	assert.Equal(t, 0, mockPkgGetter.ListPkgRequestCount, "Should NOT call ListPackageVersions - license already exists")
}
