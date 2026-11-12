package snapshots

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	hydroproto "github.com/github/dependency-snapshots-api/hydro/schemas/github/dependencygraph/v1"
	featuresMock "github.com/github/dependency-snapshots-api/internal/features/mock"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	hydromock "github.com/github/dependency-snapshots-api/internal/hydro/mock"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	snapshotsMock "github.com/github/dependency-snapshots-api/internal/snapshots/mock"
	"github.com/github/dependency-snapshots-api/pkg/proto"

	"github.com/github/go-stats"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
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
	mockFeaturesClient := featuresMock.NewMockFeaturesClient()
	service := service{snapshotsSvc: &mockSnapshotService, features: mockFeaturesClient}

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
	mockFeaturesClient := featuresMock.NewMockFeaturesClient()
	service := service{snapshotsSvc: &mockSnapshotService, features: mockFeaturesClient}

	expectedCtx := context.Background()
	expectedRequest := proto.GetDependencySnapshotRequest{RepositoryId: 1, SnapshotId: 0}

	response, err := service.GetDependencySnapshot(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "snapshot not found")
	assert.Nil(t, response)
}

func TestGetSnapshotByIDEmptyDependencies(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	mockFeaturesClient := featuresMock.NewMockFeaturesClient()
	service := service{snapshotsSvc: &mockSnapshotService, features: mockFeaturesClient}

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
	mockFeaturesClient := featuresMock.NewMockFeaturesClient()
	service := service{snapshotsSvc: &mockSnapshotService, features: mockFeaturesClient}

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

func TestGetSnapshotDiff_Enterprise(t *testing.T) {
	err := os.Setenv("ENTERPRISE", "true")
	if err != nil {
		t.Fatalf("failed to set env: %v", err)
	}
	t.Cleanup(func() {
		if err := os.Unsetenv("ENTERPRISE"); err != nil {
			t.Fatalf("failed to unset env: %v", err)
		}
	})

	service := service{}

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffRequest{RepositoryId: 1, Basehead: "base...head"}

	response, err := service.GetSnapshotDiff(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Equal(t, twirp.Unimplemented, err.(twirp.Error).Code())
	assert.Contains(t, err.Error(), "not implemented in GitHub Enterprise Server")
	assert.Nil(t, response)
}

func TestGetSnapshotDiff_InvalidRepo(t *testing.T) {
	service := service{}

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffRequest{RepositoryId: 0, Basehead: "base...head"}

	response, err := service.GetSnapshotDiff(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Equal(t, twirp.InvalidArgument, err.(twirp.Error).Code())
	assert.Contains(t, err.Error(), "repository_id is required")
	assert.Nil(t, response)
}

func TestGetSnapshotDiff_MissingBaseHead(t *testing.T) {
	service := service{}

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffRequest{RepositoryId: 1}

	response, err := service.GetSnapshotDiff(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Equal(t, twirp.InvalidArgument, err.(twirp.Error).Code())
	assert.Contains(t, err.Error(), "basehead is required")
	assert.Nil(t, response)
}

func TestGetSnapshotDiff_InvalidBaseHead(t *testing.T) {
	service := service{}

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffRequest{RepositoryId: 1, Basehead: "base...head"}

	response, err := service.GetSnapshotDiff(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Equal(t, twirp.InvalidArgument, err.(twirp.Error).Code())
	assert.Contains(t, err.Error(), "basehead must be of the form [a-f0-9]{40}...[a-f0-9]{40}")
	assert.Nil(t, response)
}

func TestGetSnapshotDiff_HandlesQueryCompleteSnapshotsErrors(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter}

	baseSha := "d6a046bd25306981451c09c28e04be1125b84791"
	headSha := "74065c8c5d5fcc87b50fa1cce3b379cf1587e131"

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffRequest{RepositoryId: 1, Basehead: baseSha + "..." + headSha}

	mockSnapshotService.On("QueryCompleteSnapshots", mock.Anything, mock.Anything, mock.Anything).Return([]*interfaces.Snapshot{}, errors.New("test error"))

	response, err := service.GetSnapshotDiff(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Equal(t, twirp.Internal, err.(twirp.Error).Code())
	assert.Contains(t, err.Error(), "getting diffable snapshots")
	assert.Nil(t, response)
}

func TestGetSnapshotDiff_ValidatesDiffableSnapshots(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter}

	baseSha := "d6a046bd25306981451c09c28e04be1125b84791"
	headSha := "74065c8c5d5fcc87b50fa1cce3b379cf1587e131"

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffRequest{RepositoryId: 1, Basehead: baseSha + "..." + headSha}

	mockSnapshotService.On("QueryCompleteSnapshots", mock.Anything, uint64(1), baseSha).Return([]*interfaces.Snapshot{}, nil)
	mockSnapshotService.On("QueryCompleteSnapshots", mock.Anything, uint64(1), headSha).Return([]*interfaces.Snapshot{}, nil)

	response, err := service.GetSnapshotDiff(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Equal(t, twirp.NotFound, err.(twirp.Error).Code())
	assert.Contains(t, err.Error(), "no snapshots found for head commit")
	assert.Nil(t, response)
}

func TestGetSnapshotDiff(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter}

	baseSha := "d6a046bd25306981451c09c28e04be1125b84791"
	headSha := "74065c8c5d5fcc87b50fa1cce3b379cf1587e131"

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffRequest{RepositoryId: 1, Basehead: baseSha + "..." + headSha}

	baseSnapshot := getServiceLayerFakeSnapshot()
	baseSnapshot.SHA = baseSha

	headSnapshot := getServiceLayerFakeSnapshot()
	headSnapshot.SHA = headSha
	// Modify the head snapshot to ensure there are some diffs
	headSnapshot.Manifests["Path1"].Resolved["somepack1"] = &interfaces.DependencyNode{
		PackageURL:   "pkg:example/somepack1@version2",
		Relationship: interfaces.Direct,
		Scope:        interfaces.Runtime,
		Metadata:     interfaces.Metadata{},
		Dependencies: []string{},
	}

	// Expected diff
	expectedDependencyChanges := []*proto.GetSnapshotDiffResponse_DependencyChange{
		{
			ChangeType: proto.GetSnapshotDiffResponse_REMOVED,
			SnapshotMetadata: &proto.GetSnapshotDiffResponse_SnapshotMetadata{
				SnapshotId: headSnapshot.ID,
				Detector:   headSnapshot.Detector.Name,
				Correlator: headSnapshot.Job.Correlator,
			},
			Manifest:   "Path1",
			Ecosystem:  "example",
			Name:       "somepack1",
			Version:    "version1",
			PackageUrl: "pkg:example/somepack1@version1",
			Scope:      proto.GetSnapshotDiffResponse_RUNTIME,
		},
		{
			ChangeType: proto.GetSnapshotDiffResponse_ADDED,
			SnapshotMetadata: &proto.GetSnapshotDiffResponse_SnapshotMetadata{
				SnapshotId: headSnapshot.ID,
				Detector:   headSnapshot.Detector.Name,
				Correlator: headSnapshot.Job.Correlator,
			},
			Manifest:   "Path1",
			Ecosystem:  "example",
			Name:       "somepack1",
			Version:    "version2",
			PackageUrl: "pkg:example/somepack1@version2",
			Scope:      proto.GetSnapshotDiffResponse_RUNTIME,
		},
	}

	mockSnapshotService.On("QueryCompleteSnapshots", mock.Anything, uint64(1), baseSha).Return([]*interfaces.Snapshot{baseSnapshot}, nil)
	mockSnapshotService.On("QueryCompleteSnapshots", mock.Anything, uint64(1), headSha).Return([]*interfaces.Snapshot{headSnapshot}, nil)

	response, err := service.GetSnapshotDiff(expectedCtx, &expectedRequest)
	assert.NoError(t, err)
	assert.NotNil(t, response)

	assert.Equal(t, uint32(1), response.BaseSnapshotsCompared)
	assert.Equal(t, uint32(1), response.HeadSnapshotsCompared)
	assert.EqualExportedValues(t, expectedDependencyChanges, response.DependencyChanges)
}

func TestGetSnapshotDiffStatus_Enterprise(t *testing.T) {
	err := os.Setenv("ENTERPRISE", "true")
	if err != nil {
		t.Fatalf("failed to set env: %v", err)
	}
	t.Cleanup(func() {
		if err := os.Unsetenv("ENTERPRISE"); err != nil {
			t.Fatalf("failed to unset env: %v", err)
		}
	})

	service := service{}

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffStatusRequest{RepositoryId: 1, Basehead: "base...head"}

	response, err := service.GetSnapshotDiffStatus(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Equal(t, twirp.Unimplemented, err.(twirp.Error).Code())
	assert.Contains(t, err.Error(), "not implemented in GitHub Enterprise Server")
	assert.Nil(t, response)
}

func TestGetSnapshotDiffStatus_InvalidRepo(t *testing.T) {
	service := service{}

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffStatusRequest{RepositoryId: 0, Basehead: "base...head"}

	response, err := service.GetSnapshotDiffStatus(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Equal(t, twirp.InvalidArgument, err.(twirp.Error).Code())
	assert.Contains(t, err.Error(), "repository_id is required")
	assert.Nil(t, response)
}

func TestGetSnapshotDiffStatus_MissingBaseHead(t *testing.T) {
	service := service{}

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffStatusRequest{RepositoryId: 1}

	response, err := service.GetSnapshotDiffStatus(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Equal(t, twirp.InvalidArgument, err.(twirp.Error).Code())
	assert.Contains(t, err.Error(), "basehead is required")
	assert.Nil(t, response)
}

func TestGetSnapshotDiffStatus_InvalidBaseHead(t *testing.T) {
	service := service{}

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffStatusRequest{RepositoryId: 1, Basehead: "base...head"}

	response, err := service.GetSnapshotDiffStatus(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Equal(t, twirp.InvalidArgument, err.(twirp.Error).Code())
	assert.Contains(t, err.Error(), "basehead must be of the form [a-f0-9]{40}...[a-f0-9]{40}")
	assert.Nil(t, response)
}

func TestGetSnapshotDiffStatus_HandlesQueryCompleteSnapshotsErrors(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter}

	baseSha := "d6a046bd25306981451c09c28e04be1125b84791"
	headSha := "74065c8c5d5fcc87b50fa1cce3b379cf1587e131"

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffStatusRequest{RepositoryId: 1, Basehead: baseSha + "..." + headSha}

	mockSnapshotService.On("CountCompleteSnapshotsForSHA", mock.Anything, mock.Anything, mock.Anything).Return(0, errors.New("test error"))

	response, err := service.GetSnapshotDiffStatus(expectedCtx, &expectedRequest)
	assert.Error(t, err)
	assert.Equal(t, twirp.Internal, err.(twirp.Error).Code())
	assert.Contains(t, err.Error(), "getting status of diffable snapshots")
	assert.Nil(t, response)
}

func TestGetSnapshotDiffStatus(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter}

	baseSha := "d6a046bd25306981451c09c28e04be1125b84791"
	headSha := "74065c8c5d5fcc87b50fa1cce3b379cf1587e131"

	expectedCtx := context.Background()
	expectedRequest := proto.GetSnapshotDiffStatusRequest{RepositoryId: 1, Basehead: baseSha + "..." + headSha}

	expectedHeadSnapshots := 10
	expectedBaseSnapshots := 5

	mockSnapshotService.On("CountCompleteSnapshotsForSHA", mock.Anything, uint64(1), baseSha).Return(expectedBaseSnapshots, nil)
	mockSnapshotService.On("CountCompleteSnapshotsForSHA", mock.Anything, uint64(1), headSha).Return(expectedHeadSnapshots, nil)

	response, err := service.GetSnapshotDiffStatus(expectedCtx, &expectedRequest)
	assert.NoError(t, err)
	assert.NotNil(t, response)

	assert.Equal(t, uint32(expectedHeadSnapshots), response.HeadSnapshotCount)
	assert.Equal(t, uint32(expectedBaseSnapshots), response.BaseSnapshotCount)
	assert.Empty(t, response.MissingDetectors)
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

func TestCreateDependencySnapshotDependabotDetectorName(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	mockFeaturesClient := featuresMock.NewMockFeaturesClient()
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter, features: mockFeaturesClient}

	// Create a snapshot with detector name "dependabot" and valid PURLs
	snapshot := &interfaces.Snapshot{
		Version: 0,
		Job: interfaces.Job{
			Correlator: "test-correlator",
			ID:         "job-id",
			HTMLUrl:    "example.com/job",
		},
		SHA: "some_fake_sha",
		Ref: "refs/heads/main",
		Detector: &interfaces.DetectorMetadata{
			Name:    "dependabot", // This should trigger validation error
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
						PackageURL:   "pkg:npm/somepack1@1.0.0", // Valid npm PURL
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
						Metadata:     interfaces.Metadata{},
						Dependencies: []string{},
					},
				},
			},
		},
	}

	payload, err := json.Marshal(snapshot)
	assert.NoError(t, err)

	expectedCtx := context.Background()
	expectedRequest := proto.CreateDependencySnapshotRequest{
		RepositoryId: 1,
		Payload:      payload,
	}

	response, err := service.CreateDependencySnapshot(expectedCtx, &expectedRequest)

	// Should return an error response
	assert.Error(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, uint64(0), response.SnapshotId)
	assert.Nil(t, response.CreatedAt)
	assert.Equal(t, proto.CreateDependencySnapshotResponse_INVALID, response.Result)
	assert.Equal(t, "detector name 'dependabot' is reserved for internal services", response.Message)

	// Verify the error is a twirp error with the correct type
	twirpErr, ok := err.(twirp.Error)
	assert.True(t, ok, "Expected twirp.Error")
	assert.Equal(t, twirp.Malformed, twirpErr.Code())
	assert.Contains(t, twirpErr.Msg(), "invalid detector name")
}

func TestCreateDependencySnapshotValidDetectorName(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	mockFeaturesClient := featuresMock.NewFeaturesClientAllOff()
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter, features: mockFeaturesClient}

	// Create a snapshot with valid detector name and valid PURLs
	snapshot := &interfaces.Snapshot{
		Version: 0,
		Job: interfaces.Job{
			Correlator: "test-correlator",
			ID:         "job-id",
			HTMLUrl:    "example.com/job",
		},
		SHA: "some_fake_sha",
		Ref: "refs/heads/main",
		Detector: &interfaces.DetectorMetadata{
			Name:    "test-detector", // Valid detector name (not "dependabot")
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
						PackageURL:   "pkg:npm/somepack1@1.0.0", // Valid npm PURL
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
						Metadata:     interfaces.Metadata{},
						Dependencies: []string{},
					},
				},
			},
		},
	}

	payload, err := json.Marshal(snapshot)
	assert.NoError(t, err)

	expectedCtx := context.Background()
	expectedRequest := proto.CreateDependencySnapshotRequest{
		RepositoryId: 1,
		Payload:      payload,
	}

	// Mock the StoreSnapshot method to return success
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: interfaces.AcceptedCanonical}, nil)

	response, err := service.CreateDependencySnapshot(expectedCtx, &expectedRequest)

	// Should succeed without validation errors
	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, uint64(12345), response.SnapshotId)
	assert.Equal(t, proto.CreateDependencySnapshotResponse_SUCCESS, response.Result)
	assert.Contains(t, response.Message, "successfully updated")
}

func TestCreateDependencySnapshotNonExpiringFlagEnabled(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	mockFeaturesClient := featuresMock.NewMockFeaturesClient()
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter, features: mockFeaturesClient, publisher: hydro.NewNoopPublisher()}

	// Create a valid snapshot
	snapshot := &interfaces.Snapshot{
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
		Manifests: interfaces.Manifests{
			"Path1": &interfaces.Manifest{
				Name: "Path1",
				File: interfaces.FileInfo{SourceLocation: "Path1"},
				Resolved: interfaces.DependencyGraph{
					"somepack1": &interfaces.DependencyNode{
						PackageURL:   "pkg:npm/somepack1@1.0.0",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
					},
				},
			},
		},
	}

	payload, err := json.Marshal(snapshot)
	require.NoError(t, err)

	expectedCtx := context.Background()
	expectedRequest := proto.CreateDependencySnapshotRequest{
		RepositoryId: 1,
		Payload:      payload,
	}

	// Mock the feature flag to be enabled for this repository
	mockFeaturesClient.On("IsFeatureFlagEnabledForRepository",
		mock.Anything,
		NonExpiringSnapshotsFeatureFlag,
		uint64(1),
	).Return(true, nil)

	// Mock the StoreSnapshot method and capture the snapshot type
	var capturedSnapshot *interfaces.Snapshot
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Run(func(args mock.Arguments) {
		capturedSnapshot = args.Get(1).(*interfaces.Snapshot)
	}).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: interfaces.AcceptedCanonical}, nil)

	response, err := service.CreateDependencySnapshot(expectedCtx, &expectedRequest)

	// Should succeed
	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, proto.CreateDependencySnapshotResponse_SUCCESS, response.Result)

	// Verify the snapshot type was set to incremental
	assert.Equal(t, interfaces.SnapshotTypeIncremental, capturedSnapshot.Type)
	mockFeaturesClient.AssertCalled(t, "IsFeatureFlagEnabledForRepository", mock.Anything, NonExpiringSnapshotsFeatureFlag, uint64(1))
}

func TestCreateDependencySnapshotNonExpiringFlagDisabled(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	mockFeaturesClient := featuresMock.NewMockFeaturesClient()
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter, features: mockFeaturesClient, publisher: hydro.NewNoopPublisher()}

	// Create a valid snapshot
	snapshot := &interfaces.Snapshot{
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
		Manifests: interfaces.Manifests{
			"Path1": &interfaces.Manifest{
				Name: "Path1",
				File: interfaces.FileInfo{SourceLocation: "Path1"},
				Resolved: interfaces.DependencyGraph{
					"somepack1": &interfaces.DependencyNode{
						PackageURL:   "pkg:npm/somepack1@1.0.0",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
					},
				},
			},
		},
	}

	payload, err := json.Marshal(snapshot)
	require.NoError(t, err)

	expectedCtx := context.Background()
	expectedRequest := proto.CreateDependencySnapshotRequest{
		RepositoryId: 1,
		Payload:      payload,
	}

	// Mock the feature flag to be disabled for this repository
	mockFeaturesClient.On("IsFeatureFlagEnabledForRepository",
		mock.Anything,
		NonExpiringSnapshotsFeatureFlag,
		uint64(1),
	).Return(false, nil)

	// Mock the StoreSnapshot method and capture the snapshot type
	var capturedSnapshot *interfaces.Snapshot
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Run(func(args mock.Arguments) {
		capturedSnapshot = args.Get(1).(*interfaces.Snapshot)
	}).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: interfaces.AcceptedCanonical}, nil)

	response, err := service.CreateDependencySnapshot(expectedCtx, &expectedRequest)

	// Should succeed
	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, proto.CreateDependencySnapshotResponse_SUCCESS, response.Result)

	// Verify the snapshot type was set to complete (default behavior)
	assert.Equal(t, interfaces.SnapshotTypeComplete, capturedSnapshot.Type)
}

func TestCreateDependencySnapshotNonExpiringFlagError(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	mockFeaturesClient := featuresMock.NewMockFeaturesClient()
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter, features: mockFeaturesClient, publisher: hydro.NewNoopPublisher()}

	// Create a valid snapshot
	snapshot := &interfaces.Snapshot{
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
		Manifests: interfaces.Manifests{
			"Path1": &interfaces.Manifest{
				Name: "Path1",
				File: interfaces.FileInfo{SourceLocation: "Path1"},
				Resolved: interfaces.DependencyGraph{
					"somepack1": &interfaces.DependencyNode{
						PackageURL:   "pkg:npm/somepack1@1.0.0",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
					},
				},
			},
		},
	}

	payload, err := json.Marshal(snapshot)
	require.NoError(t, err)

	expectedCtx := context.Background()
	expectedRequest := proto.CreateDependencySnapshotRequest{
		RepositoryId: 1,
		Payload:      payload,
	}

	// Mock the feature flag check to return an error
	mockFeaturesClient.On("IsFeatureFlagEnabledForRepository",
		mock.Anything,
		NonExpiringSnapshotsFeatureFlag,
		uint64(1),
	).Return(false, errors.New("feature flag check failed"))

	// Mock the StoreSnapshot method and capture the snapshot type
	var capturedSnapshot *interfaces.Snapshot
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Run(func(args mock.Arguments) {
		capturedSnapshot = args.Get(1).(*interfaces.Snapshot)
	}).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: interfaces.AcceptedCanonical}, nil)

	response, err := service.CreateDependencySnapshot(expectedCtx, &expectedRequest)

	// Should succeed even with feature flag error (defaults to complete)
	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, proto.CreateDependencySnapshotResponse_SUCCESS, response.Result)

	// Verify the snapshot type was set to complete (safe default on error)
	assert.Equal(t, interfaces.SnapshotTypeComplete, capturedSnapshot.Type)
}

func createSnapshotPayload(t *testing.T) []byte {
	t.Helper()
	snapshot := &interfaces.Snapshot{
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
		Manifests: interfaces.Manifests{
			"Path1": &interfaces.Manifest{
				Name: "Path1",
				File: interfaces.FileInfo{SourceLocation: "Path1"},
				Resolved: interfaces.DependencyGraph{
					"somepack1": &interfaces.DependencyNode{
						PackageURL:   "pkg:npm/somepack1@1.0.0",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
					},
				},
			},
		},
	}
	payload, err := json.Marshal(snapshot)
	require.NoError(t, err)
	return payload
}

func TestCreateDependencySnapshot_PublishesSnapshotProcessed(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	mockFeaturesClient := featuresMock.NewMockFeaturesClient()
	mockPublisher := hydromock.MockedHydroPublisher{}
	svc := service{
		snapshotsSvc: &mockSnapshotService,
		statter:      stats.NullStatter,
		features:     mockFeaturesClient,
		publisher:    &mockPublisher,
	}

	payload := createSnapshotPayload(t)
	req := proto.CreateDependencySnapshotRequest{RepositoryId: 1, Payload: payload}

	mockFeaturesClient.On("IsFeatureFlagEnabledForRepository", mock.Anything, NonExpiringSnapshotsFeatureFlag, uint64(1)).Return(false, nil)
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: interfaces.AcceptedCanonical, DependenciesChanged: true}, nil)

	mockPublisher.On("Publish", mock.Anything, mock.MatchedBy(func(msg interface{}) bool {
		sp, ok := msg.(*hydroproto.SnapshotProcessed)
		if !ok {
			return false
		}
		return sp.RepositoryId == 1 &&
			sp.SnapshotId == 12345 &&
			sp.Sha == "some_fake_sha" &&
			sp.DetectorName == "test-detector" &&
			sp.Correlator == "test-correlator" &&
			sp.SnapshotType == hydroproto.SnapshotProcessed_SNAPSHOT_TYPE_EXTERNAL &&
			sp.Deadline == nil &&
			sp.DependencyChange != nil && sp.DependencyChange.GetValue() == true
	})).Return(nil)

	response, err := svc.CreateDependencySnapshot(context.Background(), &req)

	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, proto.CreateDependencySnapshotResponse_SUCCESS, response.Result)
	mockPublisher.AssertExpectations(t)
}

func TestCreateDependencySnapshot_PublishesDependencyChangeFalse(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	mockFeaturesClient := featuresMock.NewMockFeaturesClient()
	mockPublisher := hydromock.MockedHydroPublisher{}
	svc := service{
		snapshotsSvc: &mockSnapshotService,
		statter:      stats.NullStatter,
		features:     mockFeaturesClient,
		publisher:    &mockPublisher,
	}

	payload := createSnapshotPayload(t)
	req := proto.CreateDependencySnapshotRequest{RepositoryId: 1, Payload: payload}

	mockFeaturesClient.On("IsFeatureFlagEnabledForRepository", mock.Anything, NonExpiringSnapshotsFeatureFlag, uint64(1)).Return(false, nil)
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: interfaces.AcceptedCanonical, DependenciesChanged: false}, nil)

	mockPublisher.On("Publish", mock.Anything, mock.MatchedBy(func(msg interface{}) bool {
		sp, ok := msg.(*hydroproto.SnapshotProcessed)
		if !ok {
			return false
		}
		return sp.DependencyChange != nil && sp.DependencyChange.GetValue() == false
	})).Return(nil)

	response, err := svc.CreateDependencySnapshot(context.Background(), &req)

	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, proto.CreateDependencySnapshotResponse_SUCCESS, response.Result)
	mockPublisher.AssertExpectations(t)
}

func TestCreateDependencySnapshot_PublishesForAllResultTypes(t *testing.T) {
	resultTypes := []struct {
		name           string
		result         interfaces.SnapshotResult
		expectedResult proto.CreateDependencySnapshotResponse_Result
	}{
		{"AcceptedCanonical", interfaces.AcceptedCanonical, proto.CreateDependencySnapshotResponse_SUCCESS},
		{"AcceptedNonDefaultBranch", interfaces.AcceptedNonDefaultBranch, proto.CreateDependencySnapshotResponse_ACCEPTED},
		{"AcceptedHistorical", interfaces.AcceptedHistorical, proto.CreateDependencySnapshotResponse_ACCEPTED},
	}

	for _, tc := range resultTypes {
		t.Run(tc.name, func(t *testing.T) {
			mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
			mockFeaturesClient := featuresMock.NewMockFeaturesClient()
			mockPublisher := hydromock.MockedHydroPublisher{}
			svc := service{
				snapshotsSvc: &mockSnapshotService,
				statter:      stats.NullStatter,
				features:     mockFeaturesClient,
				publisher:    &mockPublisher,
			}

			payload := createSnapshotPayload(t)
			req := proto.CreateDependencySnapshotRequest{RepositoryId: 1, Payload: payload}

			mockFeaturesClient.On("IsFeatureFlagEnabledForRepository", mock.Anything, NonExpiringSnapshotsFeatureFlag, uint64(1)).Return(false, nil)
			mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: tc.result}, nil)
			mockPublisher.On("Publish", mock.Anything, mock.AnythingOfType("*dependencygraphv1.SnapshotProcessed")).Return(nil)

			response, err := svc.CreateDependencySnapshot(context.Background(), &req)

			assert.NoError(t, err)
			assert.NotNil(t, response)
			assert.Equal(t, tc.expectedResult, response.Result)
			mockPublisher.AssertCalled(t, "Publish", mock.Anything, mock.AnythingOfType("*dependencygraphv1.SnapshotProcessed"))
		})
	}
}

func TestCreateDependencySnapshot_DoesNotPublishForSnapshotRemoved(t *testing.T) {
	mockSnapshotService := snapshotsMock.MockedSnapshotsService{}
	mockFeaturesClient := featuresMock.NewMockFeaturesClient()
	mockPublisher := hydromock.MockedHydroPublisher{}
	svc := service{
		snapshotsSvc: &mockSnapshotService,
		statter:      stats.NullStatter,
		features:     mockFeaturesClient,
		publisher:    &mockPublisher,
	}

	payload := createSnapshotPayload(t)
	req := proto.CreateDependencySnapshotRequest{RepositoryId: 1, Payload: payload}

	mockFeaturesClient.On("IsFeatureFlagEnabledForRepository", mock.Anything, NonExpiringSnapshotsFeatureFlag, uint64(1)).Return(false, nil)
	// SnapshotRemoved should not trigger publishing
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{Result: interfaces.SnapshotRemoved}, nil)

	response, err := svc.CreateDependencySnapshot(context.Background(), &req)

	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, proto.CreateDependencySnapshotResponse_REMOVED, response.Result)
	mockPublisher.AssertNotCalled(t, "Publish", mock.Anything, mock.Anything)
}
