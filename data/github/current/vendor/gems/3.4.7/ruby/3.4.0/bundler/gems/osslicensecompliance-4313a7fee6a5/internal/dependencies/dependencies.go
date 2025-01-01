// Package dependencies fetches dependant packages and their licenses from DG API
package dependencies

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"

	dg "github.com/github/dependency-graph-api/gen/go/v1"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	twirpAuth "github.com/github/go-twirp/client/auth"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/twitchtv/twirp"
)

// DependencyGetter is a struct that contains the dependencies API clients
type DependencyGetter struct {
	ShaDiffGetter ShaDiffGetter
	Logger        log.Logger
	Metrics       stats.Client
}

// ShaDiffGetter gets the dependencies between diffs
type ShaDiffGetter interface {
	// FYI: The word Snapshot here does not mean DS-API snapshots. This endpoint was
	// originally created for Dependency Review Action snapshots between two diffs
	GetSnapshotsDiff(context.Context, *dg.GetSnapshotsDiffRequest) (*dg.GetSnapshotsDiffResponse, error)
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

// New creates a dependency getter for DG API
func New(cfg *config.Config, logger log.Logger, metrics stats.Client) (*DependencyGetter, error) {
	logger = logger.Named("depgetter")
	client := dg.HTTPClient(http.DefaultClient)
	var err error
	if cfg.DependencyGraphHMACSecret != "" {
		client, err = twirpAuth.NewRequestHMACSigner(cfg.DependencyGraphHMACSecret, http.DefaultClient)
		if err != nil {
			return nil, fmt.Errorf("failed to create HMAC auth client: %w", err)
		}
	}
	if cfg.DependencyGraphHMACKey != "" {
		client, err = NewRequestHMACClient(cfg.DependencyGraphHMACKey, http.DefaultClient)
		if err != nil {
			return nil, fmt.Errorf("failed to create local HMAC client: %w", err)
		}
	}
	if client == nil {
		return nil, errors.New("no DG HMAC provided, cannot create HTTP Client")
	}

	return &DependencyGetter{
		ShaDiffGetter: dg.NewSnapshotAPIProtobufClient(
			cfg.DependencyGraphEndpoint,
			client,
			twirp.WithClientPathPrefix(snapshotPathPrefix),
		),
		Logger:  logger,
		Metrics: metrics,
	}, nil
}

// GetDiffDependenciesForRepo returns packages with licenses that were added between baseSha and sha
func (d *DependencyGetter) GetDiffDependenciesForRepo(ctx context.Context, repoID uint64, sha, baseSha string) (map[string]models.Package, error) {
	request := &dg.GetSnapshotsDiffRequest{
		RepositoryId:     repoID,
		BaseSha:          baseSha,
		TargetSha:        sha,
		DecomposeUpdates: true,
		LimitToFiles:     nil,
	}

	snapshotsDiff, err := d.ShaDiffGetter.GetSnapshotsDiff(ctx, request)
	if err != nil {
		log.Error(fmt.Sprintf("DG request to get snapshots diff errored: %v", err))
		return nil, fmt.Errorf("failed to get snapshots diff: %w", err)
	}

	modelPackages := make(map[string]models.Package)

	// Process manifest diffs for ADDED dependencies only
	for _, manifestDiff := range snapshotsDiff.GetChangedManifests() {
		if _, ok := isFilteredPackageManagers[manifestDiff.GetType()]; ok {
			continue
		}

		for _, depDiff := range manifestDiff.GetDependencies() {
			if depDiff.GetChangeType() != dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED {
				continue
			}

			// Skip dependencies with no license information
			if depDiff.GetLicense() == "" {
				d.Logger.Debug(fmt.Sprintf("Package %s@%s is missing license information, skipping", depDiff.GetName(), depDiff.GetTargetVersion()))

				tags := map[string]string{
					"package_manager": manifestDiff.GetType().String(),
				}
				d.Metrics.Counter("dependencies.missing_license", tags, 1)
				continue
			}

			version := standardizeVersion(depDiff.GetTargetVersion(), manifestDiff.GetType())
			key := packageMapKey(manifestDiff.GetType(), depDiff.GetName(), version)

			modelPackage, ok := modelPackages[key]
			if !ok {
				pkg := models.Package{
					PackageManager: DGPackageManagerToModel(manifestDiff.GetType()),
					Name:           depDiff.GetName(),
					Version:        models.Version(version),
					License:        depDiff.GetLicense(),
					LicenseVersion: models.Version(version),
					Manifests:      []string{manifestDiff.GetFilePath()},
				}
				modelPackages[key] = pkg
			} else {
				modelPackage.Manifests = append(modelPackage.Manifests, manifestDiff.GetFilePath())
				modelPackages[key] = modelPackage
			}
		}
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
