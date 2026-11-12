package repocheck_test

import (
	"fmt"
	"math"
	"math/rand/v2"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/repocheck"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	dg "github.com/github/dependency-graph-api/gen/go/v1"
)

var allDistributionContexts = []string{"distributed", "network", "internal"}

func TestCheckRepository_NoCompletePolicy(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)

	checkRequest := repocheck.RepositoryCheckRequest{
		Subsystems:     app.Subsystems,
		EnterpriseID:   1,
		OrganizationID: 1,
		RepositoryID:   1,
		CommitSHA:      "sha",
		BaseSHA:        "",
		Logger:         log.NewNullLogger(),
	}
	report, err := repocheck.CheckRepository(t.Context(), checkRequest)
	require.ErrorIs(t, err, storage.ErrNotFound, "not found error expected")
	assert.Zero(t, report, "report should be empty if error occurred")
}

func randomIDForDatabase() uint64 {
	// The database drivers don't like it if they get a uint64 with the high
	// bit set. So, this returns random IDs that we're sure are in the clear.
	return rand.Uint64N(math.MaxInt32)
}

func TestCheckRepository_WithBaseSHA(t *testing.T) {
	repoID := randomIDForDatabase()
	dpConfig := dependencies.NullConfig{
		GetSnapshotsDiffResponses: map[string]*dg.GetSnapshotsDiffResponse{
			fmt.Sprintf("%d:basesha:sha", repoID): {
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
						},
					},
				},
			},
		},
	}
	app, err := application.NewNullApplication(&application.NullConfig{DependenciesConfig: dpConfig}, log.NewNullLogger())
	require.NoError(t, err)

	policy := &models.Policy{
		PolicyLicenses: models.LicenseList{
			Allowed: []models.LicenseEntry{
				{SpdxID: "BSD-3-Clause", Contexts: allDistributionContexts},
			},
		},
	}
	orgID := randomIDForDatabase()
	_, err = app.Subsystems.Storage.CreateOrganizationPolicy(t.Context(), orgID, policy, "")
	require.NoError(t, err)

	checkRequest := repocheck.RepositoryCheckRequest{
		Subsystems:     app.Subsystems,
		EnterpriseID:   1,
		OrganizationID: orgID,
		RepositoryID:   repoID,
		CommitSHA:      "sha",
		BaseSHA:        "basesha",
		Context:        "distributed",
		Logger:         log.NewNullLogger(),
	}
	report, err := repocheck.CheckRepository(t.Context(), checkRequest)
	require.NoError(t, err)

	assert.Equal(
		t,
		evaluator.RepositoryResults{
			SuccessCount: 1,
			Failures:     []evaluator.PackageFailure{},
		},
		report,
	)
}

func TestCheckRepository_RepopolicyWithRefinement_WithBaseSHA(t *testing.T) {
	repoID := randomIDForDatabase()
	dpConfig := dependencies.NullConfig{
		GetSnapshotsDiffResponses: map[string]*dg.GetSnapshotsDiffResponse{
			fmt.Sprintf("%d:basesha:sha", repoID): {
				ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
					{
						Type:     dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
						FilePath: "./gemfile.lock",
						Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
							{
								Name:          "gem-lockfile",
								TargetVersion: "1.0.1",
								ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
								License:       "BSD-3-Clause",
							},
						},
					},
				},
			},
		},
	}
	app, err := application.NewNullApplication(&application.NullConfig{DependenciesConfig: dpConfig}, log.NewNullLogger())
	require.NoError(t, err)

	repoRefinement := &models.RepositoryRefinement{
		Licenses: models.LicenseList{
			Allowed: []models.LicenseEntry{
				{SpdxID: "BSD-3-Clause", Contexts: allDistributionContexts},
			},
		},
	}
	orgID := randomIDForDatabase()
	_, err = app.Subsystems.Storage.CreateRepositoryPolicy(t.Context(), repoID, orgID, repoRefinement)
	require.NoError(t, err)

	checkRequest := repocheck.RepositoryCheckRequest{
		Subsystems:     app.Subsystems,
		EnterpriseID:   1,
		OrganizationID: orgID,
		RepositoryID:   repoID,
		CommitSHA:      "sha",
		BaseSHA:        "basesha",
		Context:        "distributed",
		Logger:         log.NewNullLogger(),
	}
	report, err := repocheck.CheckRepository(t.Context(), checkRequest)
	require.NoError(t, err)

	assert.Equal(
		t,
		evaluator.RepositoryResults{
			SuccessCount: 1,
			Failures:     []evaluator.PackageFailure{},
		},
		report,
	)
}
