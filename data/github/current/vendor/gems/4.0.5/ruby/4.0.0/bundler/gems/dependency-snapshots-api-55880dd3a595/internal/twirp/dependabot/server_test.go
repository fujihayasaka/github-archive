package dependabot

import (
	"context"
	"errors"
	"strconv"
	"testing"
	"time"

	hydroproto "github.com/github/dependency-snapshots-api/hydro/schemas/github/dependencygraph/v1"
	dependabotmock "github.com/github/dependency-snapshots-api/internal/dependabot/mock"
	"github.com/github/dependency-snapshots-api/internal/ecosystems"
	featuresmock "github.com/github/dependency-snapshots-api/internal/features/mock"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	hydromock "github.com/github/dependency-snapshots-api/internal/hydro/mock"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	snapshotsmock "github.com/github/dependency-snapshots-api/internal/snapshots/mock"
	"github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/github/dependency-snapshots-api/pkg/proto/entities"
	stats "github.com/github/go-stats"

	"buf.build/go/protovalidate"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// TODO: test new service logic

func TestProtoToSnapshot(t *testing.T) {
	request := twirpRequest()
	snapshot := protoToSnapshot(&request)
	assert.EqualExportedValues(t, expectedSnapshot(), snapshot)
}

func TestValidateRequest(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		field      string
		request    func() *proto.CreateDependabotSnapshotRequest
		violations []string
	}{
		{
			name: "valid request",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				return &req
			},
		},
		{
			name:  "missing repository id",
			field: "repositoryId",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.RepositoryId = 0
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "missing payload",
			field: "payload",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload = nil
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "missing version",
			field: "version",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Version = 0
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "missing job",
			field: "job",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Job = nil
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "missing job id",
			field: "id",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Job.Id = ""
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "missing job correlator",
			field: "correlator",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Job.Correlator = ""
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "missing sha",
			field: "sha",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Sha = ""
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "invalid short sha",
			field: "sha",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Sha = "abc123"
				return &req
			},
			violations: []string{"value length must be at least 40 characters"},
		},
		{
			name:  "invalid long sha",
			field: "sha",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Sha = "faa40ef14cb556bafe62a84392896cd2af59b3bf1234"
				return &req
			},
			violations: []string{"value length must be at most 40 characters"},
		},
		{
			name:  "missing ref",
			field: "ref",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Ref = ""
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "invalid ref",
			field: "ref",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Ref = "main"
				return &req
			},
			violations: []string{"value does not match regex pattern `^refs/`"},
		},
		{
			name:  "missing detector",
			field: "detector",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Detector = nil
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "missing detector name",
			field: "name",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Detector.Name = ""
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "missing detector url",
			field: "url",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Detector.Url = ""
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "missing detector version",
			field: "version",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Detector.Version = ""
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "missing scanned timestamp",
			field: "scanned",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Scanned = nil
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "too many metadata entries",
			field: "metadata",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				for i := 0; i < 10; i++ {
					key := "key" + strconv.Itoa(i)
					req.Payload.Metadata[key] = "value"
				}
				return &req
			},
			violations: []string{"map must be at most 8 entries"},
		},
		{
			name:  "manifest with missing name",
			field: "name",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Manifests["Path1"].Name = ""
				return &req
			},
			violations: []string{"value is required"},
		},
		{
			name:  "manifest with too many metadata entries",
			field: "metadata",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				for i := 0; i < 10; i++ {
					key := "key" + strconv.Itoa(i)
					req.Payload.Manifests["Path1"].Metadata[key] = "value"
				}
				return &req
			},
			violations: []string{"map must be at most 8 entries"},
		},
		{
			name:  "dependency with invalid purl",
			field: "packageUrl",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				req.Payload.Manifests["Path1"].Resolved["package1"].PackageUrl = "invalid-purl"
				return &req
			},
			violations: []string{"value does not match regex pattern `^pkg`"},
		},
		{
			name:  "dependency with too many metadata entries",
			field: "metadata",
			request: func() *proto.CreateDependabotSnapshotRequest {
				req := twirpRequest()
				for i := 0; i < 10; i++ {
					key := "key" + strconv.Itoa(i)
					req.Payload.Manifests["Path1"].Resolved["package1"].Metadata[key] = "value"
				}
				return &req
			},
			violations: []string{"map must be at most 8 entries"},
		},
	}
	for _, testCase := range tests {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()

			err := validateCreateDependabotSnapshotRequest(testCase.request())

			if len(testCase.violations) > 0 {
				require.Error(t, err)

				var validationError *protovalidate.ValidationError
				require.ErrorAs(t, err, &validationError)
				require.Len(t, validationError.Violations, len(testCase.violations))

				for i, violation := range testCase.violations {
					assert.Equal(t, testCase.field, validationError.Violations[i].FieldDescriptor.JSONName())
					assert.Equal(t, violation, validationError.Violations[i].Proto.GetMessage())
				}
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestCreateDependabotSnapshot_InvalidRequest(t *testing.T) {
	expectedCtx := context.Background()
	expectedRequest := twirpRequest()
	expectedRequest.Payload.Version = 0 // invalid version

	service := service{}
	response, err := service.CreateDependabotSnapshot(expectedCtx, &expectedRequest)

	assert.Errorf(t, err, "expected error to be returned")
	assert.NotNil(t, response)
	assert.Equal(t, uint64(0), response.SnapshotId)
	assert.Nil(t, response.CreatedAt)
	assert.Equal(t, proto.CreateDependabotSnapshotResponse_RESULT_INVALID, response.Result)
	assert.Contains(t, response.Message, "Invalid request:")
	assert.Contains(t, response.Message, "payload.version: value is required [required]")
}

func TestCreateDependabotSnapshot_ValidRequest(t *testing.T) {
	expectedCtx := context.Background()
	expectedRequest := twirpRequest()

	mockSnapshotService := snapshotsmock.MockedSnapshotsService{}
	mockHydroPublisher := hydromock.MockedHydroPublisher{}
	mockFeaturesClient := featuresmock.NewFeaturesClientAllOn()
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter, publisher: &mockHydroPublisher, features: mockFeaturesClient}

	// Mock the StoreSnapshot method to return success
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: interfaces.AcceptedCanonical}, nil)

	// Mock the Publish method and return nil error
	mockHydroPublisher.On("Publish", mock.Anything, mock.Anything).Return(nil)

	response, err := service.CreateDependabotSnapshot(expectedCtx, &expectedRequest)

	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, proto.CreateDependabotSnapshotResponse_RESULT_SUCCESS, response.Result)
	assert.Equal(t, uint64(12345), response.SnapshotId)
	assert.NotNil(t, response.CreatedAt)
	assert.Contains(t, response.Message, "Dependency results for the repo have been successfully updated.")
	assert.True(t, mockSnapshotService.AssertExpectations(t))
	assert.True(t, mockHydroPublisher.AssertExpectations(t))
}

func TestCreateDependabotSnapshot_PublishesSnapshotProcessed(t *testing.T) {
	expectedCtx := context.Background()
	deadline := time.Now().Add(30 * time.Minute)

	// Build a request with event_id in metadata so the deadline lookup is triggered
	expectedRequest := proto.CreateDependabotSnapshotRequest{
		RepositoryId: 1,
		Payload: &entities.Snapshot{
			Version: 10,
			Job: &entities.Snapshot_Job{
				Id:         "job-id",
				Correlator: "test-correlator",
				HtmlUrl:    "example.com/job",
			},
			Sha: "faa40ef14cb556bafe62a84392896cd2af59b3bf",
			Ref: "refs/heads/main",
			Detector: &entities.Snapshot_Detector{
				Name:    "test-detector",
				Url:     "example.com/detector",
				Version: "1.1.1",
			},
			Metadata: map[string]string{
				"event_id": "99",
			},
			Manifests: map[string]*entities.Manifest{
				"go.mod": {
					Name: "go.mod",
					File: &entities.Manifest_File{
						SourceLocation: "go.mod",
					},
					Metadata: map[string]string{
						"ecosystem": "gomod",
					},
					Resolved: map[string]*entities.Dependency{},
				},
			},
			Scanned: timestamppb.New(time.Now()),
		},
	}

	mockSnapshotService := snapshotsmock.MockedSnapshotsService{}
	mockHydroPublisher := hydromock.MockedHydroPublisher{}
	mockFeaturesClient := featuresmock.NewFeaturesClientAllOn()
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	svc := service{
		snapshotsSvc:       &mockSnapshotService,
		statter:            stats.NullStatter,
		publisher:          &mockHydroPublisher,
		features:           mockFeaturesClient,
		dependabotEventSvc: mockEventSvc,
	}

	createdAt := time.Now()
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: createdAt, Result: interfaces.AcceptedCanonical, DependenciesChanged: true}, nil)
	mockEventSvc.On("MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	mockEventSvc.On("GetEventDeadline", mock.Anything, uint64(99)).Return(deadline, true, nil)

	// Capture the published message to verify its type and fields
	mockHydroPublisher.On("Publish", mock.Anything, mock.MatchedBy(func(msg interface{}) bool {
		sp, ok := msg.(*hydroproto.SnapshotProcessed)
		if !ok {
			return false
		}
		return sp.RepositoryId == 1 &&
			sp.SnapshotId == 12345 &&
			sp.Sha == "faa40ef14cb556bafe62a84392896cd2af59b3bf" &&
			sp.DetectorName == "test-detector" &&
			sp.Correlator == "test-correlator" &&
			sp.SnapshotType == hydroproto.SnapshotProcessed_SNAPSHOT_TYPE_DEPENDABOT &&
			sp.Deadline != nil &&
			sp.DependencyChange != nil && sp.DependencyChange.GetValue() == true
	})).Return(nil)

	response, err := svc.CreateDependabotSnapshot(expectedCtx, &expectedRequest)

	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, proto.CreateDependabotSnapshotResponse_RESULT_SUCCESS, response.Result)
	assert.True(t, mockHydroPublisher.AssertExpectations(t))
}

func TestCreateDependabotSnapshot_PublishesWithoutDeadlineWhenNoEventID(t *testing.T) {
	expectedCtx := context.Background()
	expectedRequest := twirpRequest() // no event_id in metadata

	mockSnapshotService := snapshotsmock.MockedSnapshotsService{}
	mockHydroPublisher := hydromock.MockedHydroPublisher{}
	mockFeaturesClient := featuresmock.NewFeaturesClientAllOn()
	svc := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter, publisher: &mockHydroPublisher, features: mockFeaturesClient}

	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: interfaces.AcceptedCanonical, DependenciesChanged: false}, nil)

	// Verify the published message has DEPENDABOT type but no deadline, and DependencyChange is false
	mockHydroPublisher.On("Publish", mock.Anything, mock.MatchedBy(func(msg interface{}) bool {
		sp, ok := msg.(*hydroproto.SnapshotProcessed)
		if !ok {
			return false
		}
		return sp.SnapshotType == hydroproto.SnapshotProcessed_SNAPSHOT_TYPE_DEPENDABOT &&
			sp.Deadline == nil &&
			sp.DependencyChange != nil && sp.DependencyChange.GetValue() == false
	})).Return(nil)

	response, err := svc.CreateDependabotSnapshot(expectedCtx, &expectedRequest)

	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, proto.CreateDependabotSnapshotResponse_RESULT_SUCCESS, response.Result)
	assert.True(t, mockHydroPublisher.AssertExpectations(t))
}

// We don't expect any calls to this endpoint in GHES environments, but test anyway.
func TestCreateDependabotSnapshot_Enterprise(t *testing.T) {
	expectedCtx := context.Background()
	expectedRequest := twirpRequest()

	mockSnapshotService := snapshotsmock.MockedSnapshotsService{}
	mockFeaturesClient := featuresmock.NewFeaturesClientAllOn()
	noopHydroPublisher := hydro.NewNoopPublisher()
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter, publisher: noopHydroPublisher, features: mockFeaturesClient}

	// Mock the StoreSnapshot method to return success
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: interfaces.AcceptedCanonical}, nil)

	response, err := service.CreateDependabotSnapshot(expectedCtx, &expectedRequest)

	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, proto.CreateDependabotSnapshotResponse_RESULT_SUCCESS, response.Result)
	assert.Equal(t, uint64(12345), response.SnapshotId)
	assert.NotNil(t, response.CreatedAt)
	assert.Contains(t, response.Message, "Dependency results for the repo have been successfully updated.")
	assert.True(t, mockSnapshotService.AssertExpectations(t))
}

func TestCreateDependabotSnapshot_StorageError(t *testing.T) {
	expectedCtx := context.Background()
	expectedRequest := twirpRequest()

	mockSnapshotService := snapshotsmock.MockedSnapshotsService{}
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter}

	// Mock the StoreSnapshot method to return an error to test error handling
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{Result: interfaces.Error}, errors.New("some error"))

	response, err := service.CreateDependabotSnapshot(expectedCtx, &expectedRequest)

	assert.ErrorContains(t, err, "twirp error internal: validating or storing snapshot")
	assert.Nil(t, response)
	assert.True(t, mockSnapshotService.AssertExpectations(t))
}

func TestCreateDependabotSnapshot_PublisherError(t *testing.T) {
	expectedCtx := context.Background()
	expectedRequest := twirpRequest()

	mockSnapshotService := snapshotsmock.MockedSnapshotsService{}
	mockHydroPublisher := hydromock.MockedHydroPublisher{}
	mockFeaturesClient := featuresmock.NewFeaturesClientAllOn()
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter, publisher: &mockHydroPublisher, features: mockFeaturesClient}

	// Mock the StoreSnapshot method to return success
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: interfaces.AcceptedCanonical}, nil)

	// Mock the Publish method to return an error to test error handling
	mockHydroPublisher.On("Publish", mock.Anything, mock.Anything).Return(errors.New("publishing error"))

	response, err := service.CreateDependabotSnapshot(expectedCtx, &expectedRequest)

	assert.ErrorContains(t, err, "twirp error internal: publishing Hydro event")
	assert.Nil(t, response)
	assert.True(t, mockSnapshotService.AssertExpectations(t))
	assert.True(t, mockHydroPublisher.AssertExpectations(t))
}

func TestCreateDependabotSnapshot_FailedStatusNoManifests(t *testing.T) {
	expectedCtx := context.Background()
	expectedRequest := proto.CreateDependabotSnapshotRequest{
		RepositoryId: 1,
		Payload: &entities.Snapshot{
			Version: 10,
			Job: &entities.Snapshot_Job{
				Id:         "job-id",
				Correlator: "test-correlator",
				HtmlUrl:    "example.com/job",
			},
			Sha: "faa40ef14cb556bafe62a84392896cd2af59b3bf",
			Ref: "refs/heads/main",
			Detector: &entities.Snapshot_Detector{
				Name:    "test-detector",
				Url:     "example.com/detector",
				Version: "1.1.1",
			},
			Metadata: map[string]string{
				"status":   "failed",
				"event_id": "42",
			},
			Manifests: map[string]*entities.Manifest{},
			Scanned:   timestamppb.New(time.Now()),
		},
	}

	mockSnapshotService := snapshotsmock.MockedSnapshotsService{}
	mockHydroPublisher := hydromock.MockedHydroPublisher{}
	mockFeaturesClient := featuresmock.NewFeaturesClientAllOn()
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	svc := service{
		snapshotsSvc:       &mockSnapshotService,
		statter:            stats.NullStatter,
		publisher:          &mockHydroPublisher,
		features:           mockFeaturesClient,
		dependabotEventSvc: mockEventSvc,
	}

	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(interfaces.StoreSnapshotOutput{SnapshotID: uint64(12345), CreatedAt: time.Now(), Result: interfaces.AcceptedCanonical}, nil)
	mockHydroPublisher.On("Publish", mock.Anything, mock.Anything).Return(nil)
	mockEventSvc.On("GetEventDeadline", mock.Anything, uint64(42)).Return(time.Time{}, false, nil)

	response, err := svc.CreateDependabotSnapshot(expectedCtx, &expectedRequest)

	assert.NoError(t, err)
	assert.NotNil(t, response)
	assert.Equal(t, proto.CreateDependabotSnapshotResponse_RESULT_SUCCESS, response.Result)
	assert.Equal(t, uint64(12345), response.SnapshotId)
	mockSnapshotService.AssertCalled(t, "StoreSnapshot", mock.Anything, mock.Anything)
	mockEventSvc.AssertNotCalled(t, "MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func twirpRequest() proto.CreateDependabotSnapshotRequest {
	return proto.CreateDependabotSnapshotRequest{
		RepositoryId: 1,
		Payload: &entities.Snapshot{
			Version: 10,
			Job: &entities.Snapshot_Job{
				Id:         "job-id",
				Correlator: "test-correlator",
				HtmlUrl:    "example.com/job",
			},
			Sha: "faa40ef14cb556bafe62a84392896cd2af59b3bf",
			Ref: "refs/heads/main",
			Detector: &entities.Snapshot_Detector{
				Name:    "test-detector",
				Url:     "example.com/detector",
				Version: "1.1.1",
			},
			Metadata: map[string]string{
				"scan_directory": "/repo/dependabot",
				"push_id":        "654321",
			},
			Manifests: map[string]*entities.Manifest{
				"Path1": {
					Name: "Path1",
					File: &entities.Manifest_File{
						SourceLocation: "Path1",
					},
					Metadata: map[string]string{
						"oid": "oid1",
					},
					Resolved: map[string]*entities.Dependency{
						"package1": {
							PackageUrl:   "pkg:golang/github.com/gin-gonic/gin@v1.9.1",
							Relationship: entities.Dependency_RELATIONSHIP_INDIRECT,
							Scope:        entities.Dependency_SCOPE_DEVELOPMENT,
							Metadata:     map[string]string{},
							Dependencies: []string{},
						},
					},
				},
				"Path2": {
					Name: "Path2",
					File: &entities.Manifest_File{
						SourceLocation: "Path2",
					},
					Metadata: map[string]string{
						"oid": "oid2",
					},
					Resolved: map[string]*entities.Dependency{
						"package2": {
							PackageUrl:   "pkg:golang/github.com/spf13/cobra@v1.8.0",
							Relationship: entities.Dependency_RELATIONSHIP_DIRECT,
							Scope:        entities.Dependency_SCOPE_RUNTIME,
							Metadata:     map[string]string{},
							Dependencies: []string{},
						},
					},
				},
			},
			Scanned: timestamppb.New(time.Now()),
		},
	}
}

func expectedSnapshot() *interfaces.Snapshot {
	return &interfaces.Snapshot{
		ID:           0,
		RepositoryID: 1,
		Version:      10,
		Type:         interfaces.SnapshotTypeIncremental,
		Job: interfaces.Job{
			Correlator: "test-correlator",
			ID:         "job-id",
			HTMLUrl:    "example.com/job",
		},
		SHA: "faa40ef14cb556bafe62a84392896cd2af59b3bf",
		Ref: "refs/heads/main",
		Detector: &interfaces.DetectorMetadata{
			Name:    "test-detector",
			URL:     "example.com/detector",
			Version: "1.1.1",
		},
		Metadata: interfaces.Metadata{
			"scan_directory": "/repo/dependabot",
			"push_id":        "654321",
		},
		Manifests: interfaces.Manifests{
			"Path1": &interfaces.Manifest{
				Name:     "Path1",
				File:     interfaces.FileInfo{SourceLocation: "Path1"},
				Metadata: interfaces.Metadata{"oid": "oid1"},
				Resolved: interfaces.DependencyGraph{
					"package1": &interfaces.DependencyNode{
						PackageURL:   "pkg:golang/github.com/gin-gonic/gin@v1.9.1",
						Relationship: interfaces.Indirect,
						Scope:        interfaces.Development,
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
					"package2": &interfaces.DependencyNode{
						PackageURL:   "pkg:golang/github.com/spf13/cobra@v1.8.0",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
						Metadata:     interfaces.Metadata{},
						Dependencies: []string{},
					},
				},
			},
		},
		Scanned:  time.Now(),
		Internal: false,
	}
}

func newServiceWithDependabotEventMock(dependabotEventMock *dependabotmock.MockedDependabotEventService) service {
	return service{
		snapshotsSvc:       &snapshotsmock.MockedSnapshotsService{},
		dependabotEventSvc: dependabotEventMock,
		statter:            stats.NullStatter,
		publisher:          hydro.NewNoopPublisher(),
		features:           featuresmock.NewFeaturesClientAllOn(),
	}
}

// CheckRepositoryReadiness tests
func TestCheckRepositoryReadiness_ValidationErrors(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		request *proto.CheckRepositoryReadinessRequest
		errMsg  string
	}{
		{
			name: "missing repository id",
			request: &proto.CheckRepositoryReadinessRequest{
				RepositoryId: 0,
			},
			errMsg: "invalid request",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dependabotEventMock := &dependabotmock.MockedDependabotEventService{}
			svc := newServiceWithDependabotEventMock(dependabotEventMock)

			resp, err := svc.CheckRepositoryReadiness(context.Background(), tc.request)
			assert.Error(t, err)
			assert.Nil(t, resp)
			assert.Contains(t, err.Error(), tc.errMsg)
		})
	}
}

func TestCheckRepositoryReadiness_ReadinessReasons(t *testing.T) {
	t.Parallel()

	fixedTime := time.Date(2026, 3, 15, 12, 0, 0, 0, time.UTC)

	tests := []struct {
		name           string
		result         *interfaces.ReadinessResult
		event          *interfaces.DependabotEvent
		expectedReady  bool
		expectedReason entities.DependabotReadinessReason
		expectEvent    bool
	}{
		{
			name:           "no event",
			result:         &interfaces.ReadinessResult{Ready: true, Reason: interfaces.ReadinessReasonNoEvent},
			event:          nil,
			expectedReady:  true,
			expectedReason: entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_NO_EVENT,
			expectEvent:    false,
		},
		{
			name:   "snapshot complete",
			result: &interfaces.ReadinessResult{Ready: true, Reason: interfaces.ReadinessReasonSnapshotComplete},
			event: &interfaces.DependabotEvent{
				ID: 1, EventType: interfaces.EventTypePush,
				Ref: "refs/heads/main", SHA: "abc123", CreatedAt: fixedTime,
			},
			expectedReady:  true,
			expectedReason: entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE,
			expectEvent:    true,
		},
		{
			name:   "deadline past partial snapshot",
			result: &interfaces.ReadinessResult{Ready: true, Reason: interfaces.ReadinessReasonDeadlinePastPartialSnapshot},
			event: &interfaces.DependabotEvent{
				ID: 2, EventType: interfaces.EventTypeInit,
				Ref: "refs/heads/main", SHA: "def456", CreatedAt: fixedTime,
			},
			expectedReady:  true,
			expectedReason: entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_DEADLINE_PAST_PARTIAL_SNAPSHOT,
			expectEvent:    true,
		},
		{
			name:   "deadline past no snapshot",
			result: &interfaces.ReadinessResult{Ready: true, Reason: interfaces.ReadinessReasonDeadlinePastNoSnapshot},
			event: &interfaces.DependabotEvent{
				ID: 3, EventType: interfaces.EventTypePush,
				Ref: "refs/heads/main", SHA: "ghi789", CreatedAt: fixedTime,
			},
			expectedReady:  true,
			expectedReason: entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_DEADLINE_PAST_NO_SNAPSHOT,
			expectEvent:    true,
		},
		{
			name:   "pending",
			result: &interfaces.ReadinessResult{Ready: false, Reason: interfaces.ReadinessReasonPending},
			event: &interfaces.DependabotEvent{
				ID: 4, EventType: interfaces.EventTypePush,
				Ref: "refs/heads/main", SHA: "jkl012", CreatedAt: fixedTime,
			},
			expectedReady:  false,
			expectedReason: entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_PENDING,
			expectEvent:    true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dependabotEventMock := &dependabotmock.MockedDependabotEventService{}
			svc := newServiceWithDependabotEventMock(dependabotEventMock)

			dependabotEventMock.On("CheckRepositoryReadiness", mock.Anything, mock.Anything, mock.Anything).
				Return(tc.result, tc.event, nil)

			resp, err := svc.CheckRepositoryReadiness(context.Background(), &proto.CheckRepositoryReadinessRequest{
				RepositoryId: 1,
			})
			assert.NoError(t, err)
			assert.Equal(t, tc.expectedReady, resp.Ready)
			assert.Equal(t, tc.expectedReason, resp.Reason)

			if tc.expectEvent {
				assert.NotNil(t, resp.MostRecentEvent, "MostRecentEvent should be populated")
				assert.Equal(t, tc.event.Ref, resp.MostRecentEvent.Ref)
				assert.Equal(t, tc.event.SHA, resp.MostRecentEvent.Sha)
				assert.Equal(t, timestamppb.New(tc.event.CreatedAt), resp.MostRecentEvent.CreatedAt)
			} else {
				assert.Nil(t, resp.MostRecentEvent, "MostRecentEvent should be nil when no event found")
			}
			dependabotEventMock.AssertExpectations(t)
		})
	}
}

func TestCheckRepositoryReadiness_WithEventTypeFilter(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name              string
		eventType         entities.DependabotEventType
		expectedEventType *interfaces.EventType
	}{
		{
			name:              "unspecified passes nil",
			eventType:         entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_UNSPECIFIED,
			expectedEventType: nil,
		},
		{
			name:              "push filter",
			eventType:         entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH,
			expectedEventType: eventTypePtr(interfaces.EventTypePush),
		},
		{
			name:              "init filter",
			eventType:         entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_INIT,
			expectedEventType: eventTypePtr(interfaces.EventTypeInit),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dependabotEventMock := &dependabotmock.MockedDependabotEventService{}
			svc := newServiceWithDependabotEventMock(dependabotEventMock)

			dependabotEventMock.On("CheckRepositoryReadiness", mock.Anything, uint64(1), tc.expectedEventType).
				Return(&interfaces.ReadinessResult{Ready: true, Reason: interfaces.ReadinessReasonSnapshotComplete}, (*interfaces.DependabotEvent)(nil), nil)

			resp, err := svc.CheckRepositoryReadiness(context.Background(), &proto.CheckRepositoryReadinessRequest{
				RepositoryId: 1,
				EventType:    tc.eventType,
			})
			assert.NoError(t, err)
			assert.True(t, resp.Ready)
			dependabotEventMock.AssertExpectations(t)
		})
	}
}

func TestCheckRepositoryReadiness_DependabotEventError(t *testing.T) {
	dependabotEventMock := &dependabotmock.MockedDependabotEventService{}
	svc := newServiceWithDependabotEventMock(dependabotEventMock)

	dependabotEventMock.On("CheckRepositoryReadiness", mock.Anything, mock.Anything, mock.Anything).
		Return((*interfaces.ReadinessResult)(nil), (*interfaces.DependabotEvent)(nil), errors.New("database error"))

	resp, err := svc.CheckRepositoryReadiness(context.Background(), &proto.CheckRepositoryReadinessRequest{
		RepositoryId: 1,
	})
	assert.Error(t, err)
	assert.Nil(t, resp)
	assert.Contains(t, err.Error(), "checking repository readiness")
	dependabotEventMock.AssertExpectations(t)
}

func eventTypePtr(et interfaces.EventType) *interfaces.EventType {
	return &et
}

// CheckEventReadiness tests
func TestCheckEventReadiness_ValidationErrors(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		request *proto.CheckEventReadinessRequest
		errMsg  string
	}{
		{
			name: "missing event id",
			request: &proto.CheckEventReadinessRequest{
				DependabotEventId: 0,
			},
			errMsg: "invalid request",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dependabotEventMock := &dependabotmock.MockedDependabotEventService{}
			svc := newServiceWithDependabotEventMock(dependabotEventMock)

			resp, err := svc.CheckEventReadiness(context.Background(), tc.request)
			assert.Error(t, err)
			assert.Nil(t, resp)
			assert.Contains(t, err.Error(), tc.errMsg)
		})
	}
}

func TestCheckEventReadiness_ReadinessReasons(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name           string
		result         *interfaces.ReadinessResult
		expectedReady  bool
		expectedReason entities.DependabotReadinessReason
	}{
		{
			name:           "no event",
			result:         &interfaces.ReadinessResult{Ready: true, Reason: interfaces.ReadinessReasonNoEvent},
			expectedReady:  true,
			expectedReason: entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_NO_EVENT,
		},
		{
			name:           "snapshot complete",
			result:         &interfaces.ReadinessResult{Ready: true, Reason: interfaces.ReadinessReasonSnapshotComplete},
			expectedReady:  true,
			expectedReason: entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE,
		},
		{
			name:           "deadline past partial snapshot",
			result:         &interfaces.ReadinessResult{Ready: true, Reason: interfaces.ReadinessReasonDeadlinePastPartialSnapshot},
			expectedReady:  true,
			expectedReason: entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_DEADLINE_PAST_PARTIAL_SNAPSHOT,
		},
		{
			name:           "deadline past no snapshot",
			result:         &interfaces.ReadinessResult{Ready: true, Reason: interfaces.ReadinessReasonDeadlinePastNoSnapshot},
			expectedReady:  true,
			expectedReason: entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_DEADLINE_PAST_NO_SNAPSHOT,
		},
		{
			name:           "pending",
			result:         &interfaces.ReadinessResult{Ready: false, Reason: interfaces.ReadinessReasonPending},
			expectedReady:  false,
			expectedReason: entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_PENDING,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dependabotEventMock := &dependabotmock.MockedDependabotEventService{}
			svc := newServiceWithDependabotEventMock(dependabotEventMock)

			dependabotEventMock.On("CheckEventReadiness", mock.Anything, uint64(42)).
				Return(tc.result, nil)

			resp, err := svc.CheckEventReadiness(context.Background(), &proto.CheckEventReadinessRequest{
				DependabotEventId: 42,
			})
			assert.NoError(t, err)
			assert.Equal(t, tc.expectedReady, resp.Ready)
			assert.Equal(t, tc.expectedReason, resp.Reason)
			dependabotEventMock.AssertExpectations(t)
		})
	}
}

func TestCheckEventReadiness_DependabotEventError(t *testing.T) {
	dependabotEventMock := &dependabotmock.MockedDependabotEventService{}
	svc := newServiceWithDependabotEventMock(dependabotEventMock)

	dependabotEventMock.On("CheckEventReadiness", mock.Anything, uint64(42)).
		Return((*interfaces.ReadinessResult)(nil), errors.New("database error"))

	resp, err := svc.CheckEventReadiness(context.Background(), &proto.CheckEventReadinessRequest{
		DependabotEventId: 42,
	})
	assert.Error(t, err)
	assert.Nil(t, resp)
	assert.Contains(t, err.Error(), "checking event readiness")
	dependabotEventMock.AssertExpectations(t)
}

func TestMarkAsReceived_SkipsInvalidMetadata(t *testing.T) {
	tests := []struct {
		name     string
		metadata interfaces.Metadata
	}{
		{"no event_id", interfaces.Metadata{}},
		{"blank event_id", interfaces.Metadata{"event_id": ""}},
		{"invalid event_id", interfaces.Metadata{"event_id": "not-a-number"}},
		{"zero event_id", interfaces.Metadata{"event_id": "0"}},
		{"no scanned_manifest_path", interfaces.Metadata{"event_id": "42"}},
		{"blank scanned_manifest_path", interfaces.Metadata{"event_id": "42", "scanned_manifest_path": ""}},
		{"invalid format (no delimiter)", interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "no-delimiter-here"}},
		{"unknown ecosystem", interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "not_a_real_ecosystem::."}},
		{"empty manifest path", interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "golang::"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockEventSvc := &dependabotmock.MockedDependabotEventService{}
			svc := service{dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

			snapshot := &interfaces.Snapshot{
				RepositoryID: 1,
				Metadata:     tt.metadata,
			}

			svc.markAsReceived(context.Background(), snapshot, 100)

			mockEventSvc.AssertNotCalled(t, "MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
		})
	}
}

func TestMarkAsReceived_CallsMarkSnapshotReceived(t *testing.T) {
	tests := []struct {
		name              string
		metadata          interfaces.Metadata
		manifests         interfaces.Manifests
		expectedEcosystem ecosystems.Ecosystem
		expectedPath      string
		mockMatched       bool
		mockErr           error
	}{
		{
			name:              "root path with dot",
			metadata:          interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "golang::."},
			expectedEcosystem: ecosystems.Golang,
			expectedPath:      ".",
			mockMatched:       true,
		},
		{
			name:              "nested path",
			metadata:          interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "npm::frontend/app"},
			expectedEcosystem: ecosystems.NPM,
			expectedPath:      "frontend/app",
			mockMatched:       true,
		},
		{
			name:              "leading slash normalized",
			metadata:          interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "npm::/frontend/app"},
			expectedEcosystem: ecosystems.NPM,
			expectedPath:      "frontend/app",
			mockMatched:       true,
		},
		{
			name:              "trailing slash normalized",
			metadata:          interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "npm::frontend/app/"},
			expectedEcosystem: ecosystems.NPM,
			expectedPath:      "frontend/app",
			mockMatched:       true,
		},
		{
			name:              "leading and trailing slash normalized",
			metadata:          interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "npm::/frontend/app/"},
			expectedEcosystem: ecosystems.NPM,
			expectedPath:      "frontend/app",
			mockMatched:       true,
		},
		{
			name:              "slash root normalizes to dot",
			metadata:          interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "npm::/"},
			expectedEcosystem: ecosystems.NPM,
			expectedPath:      ".",
			mockMatched:       true,
		},
		{
			name:              "path containing delimiter",
			metadata:          interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "golang::path::with::colons"},
			expectedEcosystem: ecosystems.Golang,
			expectedPath:      "path::with::colons",
			mockMatched:       true,
		},
		{
			name:              "deletion snapshot with empty manifests",
			metadata:          interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "golang::."},
			manifests:         interfaces.Manifests{},
			expectedEcosystem: ecosystems.Golang,
			expectedPath:      ".",
			mockMatched:       true,
		},
		{
			name:              "no match in requested snapshots",
			metadata:          interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "golang::."},
			expectedEcosystem: ecosystems.Golang,
			expectedPath:      ".",
			mockMatched:       false,
		},
		{
			name:              "error does not panic",
			metadata:          interfaces.Metadata{"event_id": "42", "scanned_manifest_path": "golang::."},
			expectedEcosystem: ecosystems.Golang,
			expectedPath:      ".",
			mockErr:           assert.AnError,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockEventSvc := &dependabotmock.MockedDependabotEventService{}
			mockEventSvc.On("MarkSnapshotReceived", mock.Anything, uint64(42), uint64(100), tt.expectedEcosystem, tt.expectedPath).Return(tt.mockMatched, tt.mockErr)
			svc := service{dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

			snapshot := &interfaces.Snapshot{
				RepositoryID: 1,
				Metadata:     tt.metadata,
				Manifests:    tt.manifests,
			}

			assert.NotPanics(t, func() {
				svc.markAsReceived(context.Background(), snapshot, 100)
			})

			mockEventSvc.AssertCalled(t, "MarkSnapshotReceived", mock.Anything, uint64(42), uint64(100), tt.expectedEcosystem, tt.expectedPath)
		})
	}
}
