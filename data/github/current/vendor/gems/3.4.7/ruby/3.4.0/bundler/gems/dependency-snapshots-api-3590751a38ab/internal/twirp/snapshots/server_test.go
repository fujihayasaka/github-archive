package snapshots

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	snapshotsMock "github.com/github/dependency-snapshots-api/internal/snapshots/mock"
	"github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

func getServiceLayerFakeSnapshot() *interfaces.Snapshot {
	return &interfaces.Snapshot{
		Version: 0,
		Job: interfaces.Job{
			Correlator: "test-correlator",
			ID:         "job-id",
			HTMLUrl:    "example.com/job",
		},
		SHA: "some_fake_sha",
		Ref: "refs/heads/main",
		Detector: &interfaces.DetectorMetadata{
			Name:    "test-detector",
			URL:     "example.com/detector",
			Version: "1.1.1",
		},
		Metadata: interfaces.Metadata{
			"scan_directory": "/some/path",
			"push_id":        "654321",
		},
		Manifests: interfaces.Manifests{
			"Path1": &interfaces.Manifest{
				Name:     "Path1",
				File:     interfaces.FileInfo{SourceLocation: "Path1"},
				Metadata: interfaces.Metadata{"oid": "oid1"},
				Resolved: interfaces.DependencyGraph{
					"somepack1": &interfaces.DependencyNode{
						PackageURL:   "pkg:example/somepack1@version1",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
						Metadata:     interfaces.Metadata{},
						Dependencies: []string{},
					},
				},
			},
			"Path2": &interfaces.Manifest{
				Name:     "Path2",
				File:     interfaces.FileInfo{SourceLocation: "Path2"},
				Metadata: interfaces.Metadata{"oid": "oid2"},
				Resolved: interfaces.DependencyGraph{
					"somepack2": &interfaces.DependencyNode{
						PackageURL:   "pkg:example/somepack2@version2",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
						Metadata:     interfaces.Metadata{},
						Dependencies: []string{},
					},
				},
			},
		},
		ID:           12345,
		RepositoryID: 1,
	}
}

func TestGetSnapshotByIDHappyPath(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	service := service{snapshotsSvc: &mockSnapshotService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependencySnapshotRequest{RepositoryId: 1, SnapshotId: 12345}
	serviceLayerFakeSnapshot := getServiceLayerFakeSnapshot()

	mockSnapshotService.On("SnapshotByID", mock.Anything, expectedRequest.SnapshotId).Return(serviceLayerFakeSnapshot, nil)

	response, err := service.GetDependencySnapshot(expectedCtx, &expectedRequest)
	assert.NoError(t, err)
	assert.NotNil(t, response)

	var got interfaces.Snapshot
	err = json.Unmarshal(response.GetPayload(), &got)
	assert.NoError(t, err)
	verifyServiceLayerFakeSnapshotMatchesActual(t, serviceLayerFakeSnapshot, &got)

	assert.Equal(t, expectedRequest.RepositoryId, response.GetRepositoryId())
	assert.Equal(t, expectedRequest.SnapshotId, response.GetSnapshotId())
}

func TestGetSnapshotByIDZeroID(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	service := service{snapshotsSvc: &mockSnapshotService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependencySnapshotRequest{RepositoryId: 1, SnapshotId: 0}

	response, err := service.GetDependencySnapshot(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "snapshot not found")
	assert.Nil(t, response)
}

func TestGetSnapshotByIDEmptyDependencies(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	service := service{snapshotsSvc: &mockSnapshotService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependencySnapshotRequest{RepositoryId: 1, SnapshotId: 12345}
	serviceLayerFakeSnapshot := getServiceLayerFakeSnapshot()
	for key := range serviceLayerFakeSnapshot.Manifests {
		// Go requires that we pull the value out of the map before setting a struct field on it
		if manifest, ok := serviceLayerFakeSnapshot.Manifests[key]; ok {
			manifest.Resolved = interfaces.DependencyGraph{}
		}
	}

	mockSnapshotService.On("SnapshotByID", expectedCtx, expectedRequest.SnapshotId).Return(serviceLayerFakeSnapshot, nil)

	response, err := service.GetDependencySnapshot(expectedCtx, &expectedRequest)
	assert.NoError(t, err)
	assert.NotNil(t, response)

	var got interfaces.Snapshot
	err = json.Unmarshal(response.GetPayload(), &got)
	assert.NoError(t, err)

	// Don't double test anything happy path already covers, but do test:
	for name, manifest := range got.Manifests {
		if len(manifest.Resolved) > 0 {
			t.Errorf("response.Manifests[%s] has non-empty dependencies: %v", name, manifest.Resolved)
		}
	}
}

func TestGetSnapshotByIDEmptyManifests(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	service := service{snapshotsSvc: &mockSnapshotService}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependencySnapshotRequest{RepositoryId: 1, SnapshotId: 12345}
	serviceLayerFakeSnapshot := getServiceLayerFakeSnapshot()
	serviceLayerFakeSnapshot.Manifests = nil
	mockSnapshotService.On("SnapshotByID", expectedCtx, expectedRequest.SnapshotId).Return(serviceLayerFakeSnapshot, nil)

	response, err := service.GetDependencySnapshot(expectedCtx, &expectedRequest)
	assert.NoError(t, err)
	assert.NotNil(t, response)

	var got interfaces.Snapshot
	err = json.Unmarshal(response.GetPayload(), &got)
	assert.NoError(t, err)

	// Don't double test anything happy path already covers, but do test:
	assert.Nil(t, got.Manifests)
}

func verifyServiceLayerFakeSnapshotMatchesActual(t *testing.T, serviceLayerFakeSnapshot *interfaces.Snapshot, snapshot *interfaces.Snapshot) {
	t.Helper()

	assert.Equal(t, serviceLayerFakeSnapshot.Job.ID, snapshot.Job.ID)
	assert.Equal(t, serviceLayerFakeSnapshot.Job.Correlator, snapshot.Job.Correlator)
	assert.Equal(t, serviceLayerFakeSnapshot.Ref, snapshot.Ref)
	assert.Equal(t, serviceLayerFakeSnapshot.SHA, snapshot.SHA)

	for manifestName, manifest := range snapshot.Manifests {
		serviceLayerManifest := serviceLayerFakeSnapshot.Manifests[manifestName]
		assert.NotNil(t, serviceLayerManifest)
		assert.Equal(t, serviceLayerManifest.Name, manifest.Name)
		assert.Equal(t, serviceLayerManifest.File.SourceLocation, manifest.File.SourceLocation)

		for depName, dependency := range manifest.Resolved {
			serviceLayerDependency := serviceLayerManifest.Resolved[depName]
			assert.NotNil(t, serviceLayerDependency)
			assert.Equal(t, serviceLayerDependency.PackageURL, dependency.PackageURL)
			assert.Equal(t, serviceLayerDependency.Scope.String(), dependency.Scope.String())
			assert.Equal(t, serviceLayerDependency.Relationship.String(), dependency.Relationship.String())
		}
	}
}
