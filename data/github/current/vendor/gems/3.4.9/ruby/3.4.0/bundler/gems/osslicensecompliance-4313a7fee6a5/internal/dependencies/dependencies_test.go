package dependencies_test

import (
	"context"
	"strconv"
	"testing"

	dg "github.com/github/dependency-graph-api/gen/go/v1"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/github/osslicensecompliance/internal/models"
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
	GetPkgRequest       *dg.GetPackageVersionsRequest
	GetPkgResponse      *dg.GetPackageVersionsResponse
	ListPkgRequest      *dg.ListPackageVersionsRequest
	ListPkgResponse     *dg.ListPackageVersionsResponse
	ListPkgRequestCount int
}

func (mpg *MockPkgGetter) GetPackageVersions(_ context.Context, req *dg.GetPackageVersionsRequest) (*dg.GetPackageVersionsResponse, error) {
	mpg.GetPkgRequest = req
	return mpg.GetPkgResponse, nil
}

func (mpg *MockPkgGetter) ListPackageVersions(_ context.Context, req *dg.ListPackageVersionsRequest) (*dg.ListPackageVersionsResponse, error) {
	mpg.ListPkgRequestCount++
	mpg.ListPkgRequest = req
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

	dependentPackages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha")
	require.NoError(t, err)

	assert.Equal(t, uint64(1), mockShaDiffGetter.Request.GetRepositoryId())
	assert.Equal(t, "base-sha", mockShaDiffGetter.Request.GetBaseSha())
	assert.Equal(t, "target-sha", mockShaDiffGetter.Request.GetTargetSha())
	assert.True(t, mockShaDiffGetter.Request.GetDecomposeUpdates(), "DecomposeUpdates field should be true in request")
	assert.Nil(t, mockShaDiffGetter.Request.GetLimitToFiles(), "LimitToFiles field should not be present in request")

	assert.Equal(
		t,
		map[string]models.Package{
			strconv.Itoa(int(models.PMrubygems)) + ":foo/bar@1.0.1": {
				PackageManager: models.PMrubygems,
				Name:           "foo/bar",
				Version:        "1.0.1",
				License:        "BSD-3-Clause",
				LicenseVersion: "1.0.1",
				Manifests:      []string{"./Gemfile.lock"},
			},
		},
		dependentPackages,
	)
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

	dependentPackages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha")
	require.NoError(t, err)

	assert.Equal(t, models.Version("v1.0.1"), dependentPackages["7:foo/no_v@v1.0.1"].Version)
	assert.Equal(t, models.Version("v1.0.1"), dependentPackages["7:foo/no_v@v1.0.1"].LicenseVersion)

	assert.Equal(t, models.Version("v1.0.1"), dependentPackages["7:foo/has_v@v1.0.1"].Version)
	assert.Equal(t, models.Version("v1.0.1"), dependentPackages["7:foo/has_v@v1.0.1"].LicenseVersion)

	assert.Equal(
		t,
		map[string]models.Package{
			strconv.Itoa(int(models.PMgomod)) + ":foo/no_v@v1.0.1": {
				PackageManager: models.PMgomod,
				Name:           "foo/no_v",
				Version:        "v1.0.1",
				License:        "BSD-3-Clause",
				LicenseVersion: "v1.0.1",
				Manifests:      []string{"./go.mod"},
			},
			strconv.Itoa(int(models.PMgomod)) + ":foo/has_v@v1.0.1": {
				PackageManager: models.PMgomod,
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

	dependentPackages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha")
	require.NoError(t, err)

	assert.Equal(
		t,
		map[string]models.Package{
			strconv.Itoa(int(models.PMgomod)) + ":foo/bar@v1.0.1": {
				PackageManager: models.PMgomod,
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
			},
		},
	}

	dependencyGetter := dependencies.DependencyGetter{
		ShaDiffGetter: mockShaDiffGetter,
		Logger:        log.NewNullLogger(),
		Metrics:       stats.NullStatter,
	}

	dependentPackages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha")
	require.NoError(t, err)

	// Should only contain the rubygems package, filtered package managers should be excluded
	assert.Equal(
		t,
		map[string]models.Package{
			strconv.Itoa(int(models.PMrubygems)) + ":good-gem@1.0.1": {
				PackageManager: models.PMrubygems,
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

func TestGetDiffDependenciesForRepo_FiltersOutDependenciesWithoutLicenses(t *testing.T) {
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
							Name:          "with-license",
							TargetVersion: "1.0.1",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "MIT",
						},
						{
							Name:          "without-license",
							TargetVersion: "1.0.2",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "", // Empty license should be filtered out
						},
						{
							Name:          "with-license-two",
							TargetVersion: "2.0.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "Apache-2.0",
						},
					},
				},
				{
					Type:     dg.PackageManager_PACKAGE_MANAGER_NPM,
					FilePath: "./package-lock.json",
					Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
						{
							Name:          "js-no-license",
							TargetVersion: "3.0.0",
							ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
							License:       "", // Another empty license to filter out
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

	dependentPackages, err := dependencyGetter.GetDiffDependenciesForRepo(t.Context(), 1, "target-sha", "base-sha")
	require.NoError(t, err)

	// Should only contain packages with licenses, filtered packages should be excluded
	assert.Equal(
		t,
		map[string]models.Package{
			strconv.Itoa(int(models.PMrubygems)) + ":with-license@1.0.1": {
				PackageManager: models.PMrubygems,
				Name:           "with-license",
				Version:        "1.0.1",
				License:        "MIT",
				LicenseVersion: "1.0.1",
				Manifests:      []string{"./Gemfile.lock"},
			},
			strconv.Itoa(int(models.PMrubygems)) + ":with-license-two@2.0.0": {
				PackageManager: models.PMrubygems,
				Name:           "with-license-two",
				Version:        "2.0.0",
				License:        "Apache-2.0",
				LicenseVersion: "2.0.0",
				Manifests:      []string{"./Gemfile.lock"},
			},
		},
		dependentPackages,
	)

	// Verify that dependencies without licenses are not included
	for key := range dependentPackages {
		assert.NotContains(t, key, "without-license", "Dependencies without license should be filtered out")
		assert.NotContains(t, key, "js-no-license", "Dependencies without license should be filtered out")
	}
}
