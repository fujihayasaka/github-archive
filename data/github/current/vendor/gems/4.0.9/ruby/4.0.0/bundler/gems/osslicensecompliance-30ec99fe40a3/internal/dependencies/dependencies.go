// Package dependencies fetches dependant packages and their licenses from DG API
package dependencies

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/github/go-server/client"

	semver "github.com/Masterminds/semver/v3"
	dg "github.com/github/dependency-graph-api/gen/go/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	twirpAuth "github.com/github/go-twirp/client/auth"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/semconv"
	"github.com/package-url/packageurl-go"
	"github.com/twitchtv/twirp"
)

// DependencyGetter is a struct that contains the dependencies API clients
type DependencyGetter struct {
	ShaDiffGetter ShaDiffGetter
	PackageGetter PackageGetter
	Logger        log.Logger
	Metrics       stats.Client
}

// ShaDiffGetter gets the dependencies between diffs
type ShaDiffGetter interface {
	// FYI: The word Snapshot here does not mean DS-API snapshots. This endpoint was
	// originally created for Dependency Review Action snapshots between two diffs
	GetSnapshotsDiff(context.Context, *dg.GetSnapshotsDiffRequest) (*dg.GetSnapshotsDiffResponse, error)
}

// PackageGetter gets package version information
type PackageGetter interface {
	ListPackageVersions(context.Context, *dg.ListPackageVersionsRequest) (*dg.ListPackageVersionsResponse, error)
}

const (
	repoPathPrefix              = "twirp/repository-dependencies"
	pkgPathPrefix               = "twirp/packages"
	snapshotPathPrefix          = "twirp/snapshots"
	getPackageVersionsChunkSize = 500
)

// Filter out actions as they do not have licenses
// Filter out pub as ClearlyDefined does not support yet
// Filter out unknown as wont have licenses
var isFilteredPackageManagers = map[dg.PackageManager]struct{}{
	dg.PackageManager_PACKAGE_MANAGER_ACTIONS: {},
	dg.PackageManager_PACKAGE_MANAGER_PUB:     {},
	dg.PackageManager_PACKAGE_MANAGER_UNKNOWN: {},
}

// Allowlist of package managers we support (where we can get license data)
// This is used for filtering dependencies in UNKNOWN manifest types (e.g., snapshot submissions)
var supportedPackageManagers = map[dg.PackageManager]struct{}{
	dg.PackageManager_PACKAGE_MANAGER_NPM:      {},
	dg.PackageManager_PACKAGE_MANAGER_PIP:      {},
	dg.PackageManager_PACKAGE_MANAGER_MAVEN:    {},
	dg.PackageManager_PACKAGE_MANAGER_NUGET:    {},
	dg.PackageManager_PACKAGE_MANAGER_COMPOSER: {},
	dg.PackageManager_PACKAGE_MANAGER_GOMOD:    {},
	dg.PackageManager_PACKAGE_MANAGER_RUST:     {},
	dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS: {},
	dg.PackageManager_PACKAGE_MANAGER_SWIFT:    {},
}

// purlTypeToPackageManager maps PURL type strings to PackageManager enums
// Based on https://github.com/package-url/purl-spec/blob/master/PURL-TYPES.rst
var purlTypeToPackageManager = map[string]dg.PackageManager{
	"npm":           dg.PackageManager_PACKAGE_MANAGER_NPM,
	"pypi":          dg.PackageManager_PACKAGE_MANAGER_PIP,
	"maven":         dg.PackageManager_PACKAGE_MANAGER_MAVEN,
	"nuget":         dg.PackageManager_PACKAGE_MANAGER_NUGET,
	"composer":      dg.PackageManager_PACKAGE_MANAGER_COMPOSER,
	"golang":        dg.PackageManager_PACKAGE_MANAGER_GOMOD,
	"cargo":         dg.PackageManager_PACKAGE_MANAGER_RUST,
	"gem":           dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
	"swift":         dg.PackageManager_PACKAGE_MANAGER_SWIFT,
	"githubactions": dg.PackageManager_PACKAGE_MANAGER_ACTIONS,
	"pub":           dg.PackageManager_PACKAGE_MANAGER_PUB,
}

// packageManagerFromPURL extracts the package manager from a PURL string.
// Returns PACKAGE_MANAGER_UNKNOWN if the PURL is invalid or the type is not recognized.
func packageManagerFromPURL(purl string) dg.PackageManager {
	if purl == "" {
		return dg.PackageManager_PACKAGE_MANAGER_UNKNOWN
	}

	// Parse the PURL using the official library
	parsedPURL, err := packageurl.FromString(purl)
	if err != nil {
		return dg.PackageManager_PACKAGE_MANAGER_UNKNOWN
	}

	// Look up the package manager based on the PURL type
	if pm, ok := purlTypeToPackageManager[parsedPURL.Type]; ok {
		return pm
	}

	return dg.PackageManager_PACKAGE_MANAGER_UNKNOWN
}

// determinePackageManager determines the package manager for a dependency.
// For recognized manifest types, it returns the manifest type directly.
// For UNKNOWN manifest types (e.g., snapshot submissions), it extracts the ecosystem from the PURL.
// Returns (packageManager, shouldInclude) where shouldInclude is false if the dependency should be filtered.
func determinePackageManager(manifestType dg.PackageManager, purl string) (dg.PackageManager, bool) {
	// For recognized manifest types, trust the manifest type
	if manifestType != dg.PackageManager_PACKAGE_MANAGER_UNKNOWN {
		// Filter out unsupported manifest types
		if _, filtered := isFilteredPackageManagers[manifestType]; filtered {
			return manifestType, false
		}
		return manifestType, true
	}

	// For UNKNOWN manifest types (e.g., snapshot submissions with "purls" manifest),
	// extract the ecosystem from the PURL
	pkgManager := packageManagerFromPURL(purl)

	// Filter dependencies by allowlist of supported package managers
	// This prevents false positives for ecosystems where we can't get license data
	if _, supported := supportedPackageManagers[pkgManager]; !supported {
		return pkgManager, false
	}

	return pkgManager, true
}

// New creates a dependency getter for DG API
func New(cfg *config.Config, logger log.Logger, metrics stats.Client) (*DependencyGetter, error) {
	logger = logger.Named("depgetter")

	httpClient := client.New(
		metrics,
		client.WithRetries(true, 3, 10*time.Millisecond, 10*time.Second),
		client.WithLogger(logger),
	)
	dgClient := dg.HTTPClient(httpClient)
	var err error
	if cfg.DependencyGraphHMACSecret != "" {
		dgClient, err = twirpAuth.NewRequestHMACSigner(cfg.DependencyGraphHMACSecret, dgClient)
		if err != nil {
			return nil, fmt.Errorf("failed to create HMAC auth client: %w", err)
		}
	}
	if cfg.DependencyGraphHMACKey != "" {
		dgClient, err = NewRequestHMACClient(cfg.DependencyGraphHMACKey, dgClient)
		if err != nil {
			return nil, fmt.Errorf("failed to create local HMAC client: %w", err)
		}
	}
	if dgClient == nil {
		return nil, errors.New("no DG HMAC provided, cannot create HTTP Client")
	}

	return &DependencyGetter{
		ShaDiffGetter: dg.NewSnapshotAPIProtobufClient(
			cfg.DependencyGraphEndpoint,
			dgClient,
			twirp.WithClientPathPrefix(snapshotPathPrefix),
		),
		PackageGetter: dg.NewPackagesAPIProtobufClient(
			cfg.DependencyGraphEndpoint,
			dgClient,
			twirp.WithClientPathPrefix(pkgPathPrefix),
		),
		Logger:  logger,
		Metrics: metrics,
	}, nil
}

// GetDiffDependenciesForRepo returns packages with licenses that were added between baseSha and sha
func (d *DependencyGetter) GetDiffDependenciesForRepo(ctx context.Context, repoID uint64, sha, baseSha string) (map[string]models.Package, error) {
	start := time.Now()
	defer func() { d.Metrics.DistributionMs("dependencies.get.duration", nil, time.Since(start)) }()

	logger := d.Logger.Named("Dependencies").WithFields(
		semconv.Method("GetDiffDependenciesForRepo"),
		semconv.RepositoryID(repoID),
		semconv.CommitSHA(sha),
		semconv.BaseSHA(baseSha),
	)

	request := &dg.GetSnapshotsDiffRequest{
		RepositoryId:     repoID,
		BaseSha:          baseSha,
		TargetSha:        sha,
		DecomposeUpdates: true,
		LimitToFiles:     nil,
	}

	snapshotsDiffStart := time.Now()
	snapshotsDiff, err := d.ShaDiffGetter.GetSnapshotsDiff(ctx, request)
	d.Metrics.DistributionMs("dependencies.dgapi.get_snapshots_diff.duration", nil, time.Since(snapshotsDiffStart))
	if err != nil {
		logger.Error(fmt.Sprintf("DG request to get snapshots diff errored: %v", err))
		return nil, fmt.Errorf("failed to get snapshots diff: %w", err)
	}
	logger.Info("Fetched snapshots diff from DG", kvp.Int("num_changed_manifests", len(snapshotsDiff.GetChangedManifests())))

	modelPackages := make(map[string]models.Package)

	latestVersionCache := make(map[string]string)
	licenseCache := make(map[string]string)

	// Process manifest diffs for ADDED dependencies only
	for _, manifestDiff := range snapshotsDiff.GetChangedManifests() {
		for _, depDiff := range manifestDiff.GetDependencies() {
			if depDiff.GetChangeType() != dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED {
				continue
			}

			// Determine the package manager and whether to include this dependency
			pkgManager, shouldInclude := determinePackageManager(manifestDiff.GetType(), depDiff.GetTargetPurl())
			if !shouldInclude {
				continue
			}

			version := standardizeVersion(depDiff.GetTargetVersion(), pkgManager)
			key := packageMapKey(pkgManager, depDiff.GetName(), version)

			modelPackage, ok := modelPackages[key]
			if !ok {
				pkg := models.Package{
					PackageManager: DGPackageManagerToModel(pkgManager),
					Name:           depDiff.GetName(),
					Version:        models.Version(version),
					License:        depDiff.GetLicense(),
					LicenseVersion: models.Version(version),
					Manifests:      []string{manifestDiff.GetFilePath()},
					PackageRepoNWO: depDiff.GetRepoNwo(),
				}
				if pkg.License != "" {
					d.Metrics.Counter("package.license", stats.Tags{"source": "provided"}, 1)
				}
				modelPackages[key] = pkg
			} else {
				modelPackage.Manifests = append(modelPackage.Manifests, manifestDiff.GetFilePath())
				modelPackages[key] = modelPackage
			}
		}
	}

	// Lookup and apply licenses for packages with missing licenses
	for key, pkg := range modelPackages {
		if pkg.License != "" {
			continue
		}

		dgPkgManager := ModelPackageManagerToDG(pkg.PackageManager)
		cacheKey := latestVersionCacheKey(dgPkgManager, pkg.Name)

		// Check if we already looked up latest version for this package
		latestVersion, alreadyFetched := latestVersionCache[cacheKey]
		if !alreadyFetched {
			logger.Debug("Missing License, attempting to get latest version DG license for package",
				kvp.String("package_manager", pkg.PackageManager.String()),
				kvp.String("package_name", pkg.Name),
				kvp.String("manifest_package_version", string(pkg.Version)),
			)

			latestVerResult, err := d.getLatestPackageVersion(ctx, dgPkgManager, pkg.Name)
			if err != nil {
				logger.Error("dg-api get latest version request error for package",
					kvp.String("package_name", pkg.Name),
					kvp.Err(err),
				)
				latestVersionCache[cacheKey] = ""
				d.Metrics.Counter("package.license", stats.Tags{"source": "missing"}, 1)
				continue
			}
			if latestVerResult == nil {
				latestVersionCache[cacheKey] = ""
				d.Metrics.Counter("package.license", stats.Tags{"source": "missing"}, 1)
				logger.Debug("Unable to obtain latest license for package",
					kvp.String("package_manager", pkg.PackageManager.String()),
					kvp.String("package_name", pkg.Name),
					kvp.String("manifest_package_version", string(pkg.Version)),
				)
				continue
			}

			latestVersion = latestVerResult.version
			latestVersionCache[cacheKey] = latestVersion

			if latestVerResult.license != "" {
				logger.Debug(
					"Latest package with license retrieved",
					kvp.String("package_name", pkg.Name),
					kvp.String("license", latestVerResult.license),
					kvp.String("licensed_version", latestVerResult.versionString()),
				)

				licenseCacheKey := packageMapKey(dgPkgManager, pkg.Name, latestVersion)
				licenseCache[licenseCacheKey] = latestVerResult.license
			}
		}

		if latestVersion != "" {
			licenseCacheKey := packageMapKey(dgPkgManager, pkg.Name, latestVersion)
			if license, ok := licenseCache[licenseCacheKey]; ok && license != "" {
				d.Metrics.Counter("package.license", stats.Tags{"source": "calculated"}, 1)
				pkg.License = license
				pkg.LicenseVersion = models.Version(latestVersion)
				pkg.CalculatedLicense = true
				modelPackages[key] = pkg
				continue
			}
		}

		d.Metrics.Counter("package.license", stats.Tags{"source": "missing"}, 1)
		logger.Debug("Unable to obtain latest license for package",
			kvp.String("package_manager", pkg.PackageManager.String()),
			kvp.String("package_name", pkg.Name),
			kvp.String("manifest_package_version", string(pkg.Version)),
		)
	}

	return modelPackages, nil
}

func packageMapKey(pkgManager dg.PackageManager, pkgName, version string) string {
	return fmt.Sprintf(
		"%d:%s@%s",
		pkgManager,
		strings.ToLower(pkgName),
		version,
	)
}

func standardizeVersion(version string, pkgManager dg.PackageManager) string {
	if version != "" &&
		version != "*" && // wildcard versions
		(pkgManager == dg.PackageManager_PACKAGE_MANAGER_GOMOD) &&
		!strings.HasPrefix(version, "v") {
		return "v" + version
	}
	return version
}

type versionLicense struct {
	license       string
	version       string
	semVerVersion *semver.Version
}

func (v *versionLicense) versionString() string {
	if v.semVerVersion != nil {
		return v.semVerVersion.String()
	}
	return v.version
}

func (d *DependencyGetter) getLatestPackageVersion(ctx context.Context, pkgManager dg.PackageManager, name string) (vLicense *versionLicense, err error) {
	request := &dg.ListPackageVersionsRequest{
		PackageManager:  pkgManager,
		PackageName:     name,
		IncludeLicenses: true,
	}

	listVersionsStart := time.Now()
	resp, err := d.PackageGetter.ListPackageVersions(ctx, request)
	d.Metrics.DistributionMs("dependencies.dgapi.list_package_versions.duration", nil, time.Since(listVersionsStart))
	if err != nil {
		d.Logger.Error(fmt.Sprintf("DG request to list package versions errored: %v", err))

		return nil, fmt.Errorf("failed to list package versions: %w", err)
	}

	pkgVersionsWithLicense := make([]versionLicense, 0, len(resp.GetPackageVersions()))

	for _, v := range resp.GetPackageVersions() {
		if v.GetPackageLicense() == "" {
			continue
		}

		semverVersion, err := semver.NewVersion(v.GetPackageVersion())
		if err != nil {
			semverVersion = nil
		}

		vl := versionLicense{
			license:       v.GetPackageLicense(),
			version:       v.GetPackageVersion(),
			semVerVersion: semverVersion,
		}
		pkgVersionsWithLicense = append(pkgVersionsWithLicense, vl)
	}

	if len(pkgVersionsWithLicense) == 0 {
		return nil, nil
	}

	sort.SliceStable(pkgVersionsWithLicense, func(i, j int) bool {
		if pkgVersionsWithLicense[i].semVerVersion == nil || pkgVersionsWithLicense[j].semVerVersion == nil {
			return false
		}
		return pkgVersionsWithLicense[i].semVerVersion.GreaterThan(pkgVersionsWithLicense[j].semVerVersion)
	})

	if pkgVersionsWithLicense[0].semVerVersion == nil {
		return &pkgVersionsWithLicense[len(pkgVersionsWithLicense)-1], nil
	}
	return &pkgVersionsWithLicense[0], nil
}

func latestVersionCacheKey(pkgManager dg.PackageManager, name string) string {
	return fmt.Sprintf("%d:%s", pkgManager, strings.ToLower(name))
}
