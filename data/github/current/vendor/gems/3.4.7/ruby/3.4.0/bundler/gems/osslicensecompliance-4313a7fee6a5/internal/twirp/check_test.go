package twirp

import (
	"errors"
	"fmt"
	"math"
	"math/rand/v2"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"

	dg "github.com/github/dependency-graph-api/gen/go/v1"
	ossproto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

func TestCheckRepository(t *testing.T) {
	repoID := randomIDForDatabase()
	dpConfig := dependencies.NullConfig{
		GetSnapshotsDiffResponses: map[string]*dg.GetSnapshotsDiffResponse{
			fmt.Sprintf("%d:%s:%s", repoID, "base-sha", "target-sha"): {
				RepositoryId: repoID,
				BaseSha:      "base-sha",
				TargetSha:    "target-sha",
				ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
					{
						Type:     dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
						FilePath: "./Gemfile.lock",
						Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
							{
								ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
								Name:          "foo/bar",
								TargetVersion: "1.0.1",
								License:       "BSD-3-Clause",
							},
						},
					},
				},
			},
		},
	}

	server := newTestServer(t, withDependencies(dpConfig))

	policy := &models.Policy{
		PolicyLicenses: models.LicenseList{Allowed: []models.LicenseEntry{{SpdxID: "BSD-3-Clause", Contexts: []string{"distributed", "network", "internal"}}}},
	}
	orgID := randomIDForDatabase()
	_, err := server.app.Subsystems.Storage.CreateOrganizationPolicy(t.Context(), orgID, policy, "")
	require.NoError(t, err)

	req := &ossproto.CheckRepositoryRequest{
		EnterpriseId:   0,
		OrganizationId: orgID,
		RepositoryId:   repoID,
		BaseSha:        "base-sha",
		CommitSha:      "target-sha",
		Context:        "distributed",
	}

	resp, err := server.CheckRepository(t.Context(), req)

	require.NoError(t, err)
	assert.NotNil(t, resp)

	expectedResponse := &ossproto.CheckRepositoryResponse{
		Status: ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PASS,
	}
	assert.True(t, proto.Equal(expectedResponse, resp), "expected: %v, got: %v", expectedResponse, resp)
}

func TestCheckRepository_NoCompletePolicy(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}
	resp, err := server.CheckRepository(t.Context(), &ossproto.CheckRepositoryRequest{
		EnterpriseId:   0,
		OrganizationId: 0,
		RepositoryId:   0,
	})
	assert.Nil(t, resp)

	var twerr twirp.Error
	assert.True(t, errors.As(err, &twerr), "error should be of type twirp.Error")
	assert.Equal(t, twirp.InvalidArgument, twerr.Code(), "expected error to be a twirp.InvalidArgument")
}

func TestCheckRepository_InternalErrorWhenStorageErrors(t *testing.T) {
	app, err := application.NewNullApplication(&application.NullConfig{}, log.NewNullLogger())
	require.NoError(t, err)
	server := &Server{app: app}

	// Close DB to force an unexpected error
	err = server.app.Subsystems.Storage.Close()
	require.NoError(t, err)
	resp, err := server.CheckRepository(t.Context(), &ossproto.CheckRepositoryRequest{
		EnterpriseId:   0,
		OrganizationId: 0,
		RepositoryId:   0,
		BaseSha:        "base-sha",
		CommitSha:      "target-sha",
	})
	assert.Nil(t, resp)

	var twerr twirp.Error
	assert.True(t, errors.As(err, &twerr), "error should be of type twirp.Error")
	assert.Equal(t, twirp.Internal, twerr.Code(), "expected error to be a twirp.Internal")
}

func TestCheckRepository_ContextViolation(t *testing.T) {
	repoID := randomIDForDatabase()
	dpConfig := dependencies.NullConfig{
		GetSnapshotsDiffResponses: map[string]*dg.GetSnapshotsDiffResponse{
			fmt.Sprintf("%d:%s:%s", repoID, "base-sha", "target-sha"): {
				RepositoryId: repoID,
				BaseSha:      "base-sha",
				TargetSha:    "target-sha",
				ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
					{
						Type:     dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
						FilePath: "./Gemfile.lock",
						Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
							{
								ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
								Name:          "foo/bar",
								TargetVersion: "1.0.1",
								License:       "BSD-3-Clause",
							},
						},
					},
				},
			},
		},
	}

	server := newTestServer(t, withDependencies(dpConfig))

	policy := &models.Policy{
		PolicyLicenses: models.LicenseList{Allowed: []models.LicenseEntry{{SpdxID: "BSD-3-Clause", Contexts: []string{"internal"}}}},
	}
	orgID := randomIDForDatabase()
	_, err := server.app.Subsystems.Storage.CreateOrganizationPolicy(t.Context(), orgID, policy, "")
	require.NoError(t, err)

	req := &ossproto.CheckRepositoryRequest{
		EnterpriseId:   0,
		OrganizationId: orgID,
		RepositoryId:   repoID,
		BaseSha:        "base-sha",
		CommitSha:      "target-sha",
		Context:        "distributed",
	}

	resp, err := server.CheckRepository(t.Context(), req)

	require.NoError(t, err)
	assert.NotNil(t, resp)

	expectedResponse := &ossproto.CheckRepositoryResponse{
		Status: ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_FAIL,
	}
	assert.True(t, proto.Equal(expectedResponse, resp), "expected: %v, got: %v", expectedResponse, resp)
}

func TestCheckRepository_ContextAllowedSubset(t *testing.T) {
	repoID := randomIDForDatabase()
	dpConfig := dependencies.NullConfig{
		GetSnapshotsDiffResponses: map[string]*dg.GetSnapshotsDiffResponse{
			fmt.Sprintf("%d:%s:%s", repoID, "base-sha", "target-sha"): {
				RepositoryId: repoID,
				BaseSha:      "base-sha",
				TargetSha:    "target-sha",
				ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
					{
						Type:     dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
						FilePath: "./Gemfile.lock",
						Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
							{
								ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
								Name:          "foo/bar",
								TargetVersion: "1.0.1",
								License:       "BSD-3-Clause",
							},
						},
					},
				},
			},
		},
	}

	server := newTestServer(t, withDependencies(dpConfig))

	policy := &models.Policy{
		PolicyLicenses: models.LicenseList{Allowed: []models.LicenseEntry{{SpdxID: "BSD-3-Clause", Contexts: []string{"internal", "network"}}}},
	}
	orgID := randomIDForDatabase()
	_, err := server.app.Subsystems.Storage.CreateOrganizationPolicy(t.Context(), orgID, policy, "")
	require.NoError(t, err)

	req := &ossproto.CheckRepositoryRequest{
		EnterpriseId:   0,
		OrganizationId: orgID,
		RepositoryId:   repoID,
		BaseSha:        "base-sha",
		CommitSha:      "target-sha",
		Context:        "internal",
	}

	resp, err := server.CheckRepository(t.Context(), req)

	require.NoError(t, err)
	assert.NotNil(t, resp)

	expectedResponse := &ossproto.CheckRepositoryResponse{
		Status: ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PASS,
	}
	assert.True(t, proto.Equal(expectedResponse, resp), "expected: %v, got: %v", expectedResponse, resp)
}

func TestCheckRepository_GPL_DisallowedForDistributed(t *testing.T) {
	repoID := randomIDForDatabase()
	dpConfig := dependencies.NullConfig{
		GetSnapshotsDiffResponses: map[string]*dg.GetSnapshotsDiffResponse{
			fmt.Sprintf("%d:%s:%s", repoID, "base-sha", "target-sha"): {
				RepositoryId: repoID,
				BaseSha:      "base-sha",
				TargetSha:    "target-sha",
				ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
					{
						Type:     dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
						FilePath: "./Gemfile.lock",
						Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
							{
								ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
								Name:          "gpl-lib",
								TargetVersion: "2.0.0",
								License:       "GPL-2.0",
							},
						},
					},
				},
			},
		},
	}

	server := newTestServer(t, withDependencies(dpConfig))

	policy := &models.Policy{
		PolicyLicenses: models.LicenseList{Allowed: []models.LicenseEntry{{SpdxID: "GPL-2.0", Contexts: []string{"internal", "network"}}}},
	}
	orgID := randomIDForDatabase()
	_, err := server.app.Subsystems.Storage.CreateOrganizationPolicy(t.Context(), orgID, policy, "")
	require.NoError(t, err)

	req := &ossproto.CheckRepositoryRequest{
		EnterpriseId:   0,
		OrganizationId: orgID,
		RepositoryId:   repoID,
		BaseSha:        "base-sha",
		CommitSha:      "target-sha",
		Context:        "distributed",
	}

	resp, err := server.CheckRepository(t.Context(), req)

	require.NoError(t, err)
	assert.NotNil(t, resp)

	expectedResponse := &ossproto.CheckRepositoryResponse{
		Status: ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_FAIL,
	}
	assert.True(t, proto.Equal(expectedResponse, resp), "expected: %v, got: %v", expectedResponse, resp)
}

func TestCheckRepository_GPL_AllowedForInternal(t *testing.T) {
	repoID := randomIDForDatabase()
	dpConfig := dependencies.NullConfig{
		GetSnapshotsDiffResponses: map[string]*dg.GetSnapshotsDiffResponse{
			fmt.Sprintf("%d:%s:%s", repoID, "base-sha", "target-sha"): {
				RepositoryId: repoID,
				BaseSha:      "base-sha",
				TargetSha:    "target-sha",
				ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
					{
						Type:     dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
						FilePath: "./Gemfile.lock",
						Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
							{
								ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
								Name:          "gpl-lib",
								TargetVersion: "2.0.0",
								License:       "GPL-2.0",
							},
						},
					},
				},
			},
		},
	}

	server := newTestServer(t, withDependencies(dpConfig))

	policy := &models.Policy{
		PolicyLicenses: models.LicenseList{Allowed: []models.LicenseEntry{{SpdxID: "GPL-2.0", Contexts: []string{"internal", "network"}}}},
	}
	orgID := randomIDForDatabase()
	_, err := server.app.Subsystems.Storage.CreateOrganizationPolicy(t.Context(), orgID, policy, "")
	require.NoError(t, err)

	req := &ossproto.CheckRepositoryRequest{
		EnterpriseId:   0,
		OrganizationId: orgID,
		RepositoryId:   repoID,
		BaseSha:        "base-sha",
		CommitSha:      "target-sha",
		Context:        "internal",
	}

	resp, err := server.CheckRepository(t.Context(), req)

	require.NoError(t, err)
	assert.NotNil(t, resp)

	expectedResponse := &ossproto.CheckRepositoryResponse{
		Status: ossproto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PASS,
	}
	assert.True(t, proto.Equal(expectedResponse, resp), "expected: %v, got: %v", expectedResponse, resp)
}

func randomIDForDatabase() uint64 {
	// The database drivers don't like it if they get a uint64 with the high
	// bit set. So, this returns random IDs that we're sure are in the clear.
	return rand.Uint64N(math.MaxInt32)
}
