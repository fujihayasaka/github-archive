package dependabot

import (
	"context"
	"errors"
	"strconv"
	"testing"
	"time"

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
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(uint64(12345), time.Now(), interfaces.AcceptedCanonical, nil)

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

// We don't expect any calls to this endpoint in GHES environments, but test anyway.
func TestCreateDependabotSnapshot_Enterprise(t *testing.T) {
	expectedCtx := context.Background()
	expectedRequest := twirpRequest()

	mockSnapshotService := snapshotsmock.MockedSnapshotsService{}
	mockFeaturesClient := featuresmock.NewFeaturesClientAllOn()
	noopHydroPublisher := hydro.NewNoopPublisher()
	service := service{snapshotsSvc: &mockSnapshotService, statter: stats.NullStatter, publisher: noopHydroPublisher, features: mockFeaturesClient}

	// Mock the StoreSnapshot method to return success
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(uint64(12345), time.Now(), interfaces.AcceptedCanonical, nil)

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
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(uint64(0), time.Time{}, interfaces.Error, errors.New("some error"))

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
	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(uint64(12345), time.Now(), interfaces.AcceptedCanonical, nil)

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

	mockSnapshotService.On("StoreSnapshot", mock.Anything, mock.Anything).Return(uint64(12345), time.Now(), interfaces.AcceptedCanonical, nil)
	mockHydroPublisher.On("Publish", mock.Anything, mock.Anything).Return(nil)

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

// CheckRepositoryEventReadiness tests

func readinessRequest() *proto.CheckRepositoryEventReadinessRequest {
	pushID := uint64(654321)
	return &proto.CheckRepositoryEventReadinessRequest{
		RepositoryId: 1,
		EventType:    entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH,
		Ref:          "refs/heads/main",
		Sha:          "faa40ef14cb556bafe62a84392896cd2af59b3bf",
		PushId:       &pushID,
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

func TestCheckRepositoryEventReadiness_ValidationErrors(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		request *proto.CheckRepositoryEventReadinessRequest
		errMsg  string
	}{
		{
			name: "missing repository id",
			request: &proto.CheckRepositoryEventReadinessRequest{
				RepositoryId: 0,
				EventType:    entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH,
				Ref:          "refs/heads/main",
				Sha:          "faa40ef14cb556bafe62a84392896cd2af59b3bf",
			},
			errMsg: "invalid request",
		},
		{
			name: "unspecified event type",
			request: &proto.CheckRepositoryEventReadinessRequest{
				RepositoryId: 1,
				EventType:    entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_UNSPECIFIED,
				Ref:          "refs/heads/main",
				Sha:          "faa40ef14cb556bafe62a84392896cd2af59b3bf",
			},
			errMsg: "invalid request",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dependabotEventMock := &dependabotmock.MockedDependabotEventService{}
			svc := newServiceWithDependabotEventMock(dependabotEventMock)

			resp, err := svc.CheckRepositoryEventReadiness(context.Background(), tc.request)
			assert.Error(t, err)
			assert.Nil(t, resp)
			assert.Contains(t, err.Error(), tc.errMsg)
		})
	}
}

func TestCheckRepositoryEventReadiness_ReadinessReasons(t *testing.T) {
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

			dependabotEventMock.On("CheckDependabotEventReadiness", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
				Return(tc.result, nil)

			resp, err := svc.CheckRepositoryEventReadiness(context.Background(), readinessRequest())
			assert.NoError(t, err)
			assert.Equal(t, tc.expectedReady, resp.Ready)
			assert.Equal(t, tc.expectedReason, resp.Reason)
			dependabotEventMock.AssertExpectations(t)
		})
	}
}

func TestCheckRepositoryEventReadiness_DependabotEventError(t *testing.T) {
	dependabotEventMock := &dependabotmock.MockedDependabotEventService{}
	svc := newServiceWithDependabotEventMock(dependabotEventMock)

	dependabotEventMock.On("CheckDependabotEventReadiness", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return((*interfaces.ReadinessResult)(nil), errors.New("database error"))

	resp, err := svc.CheckRepositoryEventReadiness(context.Background(), readinessRequest())
	assert.Error(t, err)
	assert.Nil(t, resp)
	assert.Contains(t, err.Error(), "checking event readiness")
	dependabotEventMock.AssertExpectations(t)
}

func TestCheckRepositoryEventReadiness_WithoutPushID(t *testing.T) {
	dependabotEventMock := &dependabotmock.MockedDependabotEventService{}
	svc := newServiceWithDependabotEventMock(dependabotEventMock)

	dependabotEventMock.On("CheckDependabotEventReadiness", mock.Anything, uint64(1), interfaces.EventTypeInit, "refs/heads/main", "faa40ef14cb556bafe62a84392896cd2af59b3bf", mock.Anything).
		Return(&interfaces.ReadinessResult{Ready: true, Reason: interfaces.ReadinessReasonNoEvent}, nil)

	req := &proto.CheckRepositoryEventReadinessRequest{
		RepositoryId: 1,
		EventType:    entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_INIT,
		Ref:          "refs/heads/main",
		Sha:          "faa40ef14cb556bafe62a84392896cd2af59b3bf",
	}

	resp, err := svc.CheckRepositoryEventReadiness(context.Background(), req)
	assert.NoError(t, err)
	assert.True(t, resp.Ready)
	assert.Equal(t, entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_NO_EVENT, resp.Reason)
	dependabotEventMock.AssertExpectations(t)
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

			dependabotEventMock.On("CheckRepositoryReadiness", mock.Anything, mock.Anything, mock.Anything).
				Return(tc.result, nil)

			resp, err := svc.CheckRepositoryReadiness(context.Background(), &proto.CheckRepositoryReadinessRequest{
				RepositoryId: 1,
			})
			assert.NoError(t, err)
			assert.Equal(t, tc.expectedReady, resp.Ready)
			assert.Equal(t, tc.expectedReason, resp.Reason)
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
				Return(&interfaces.ReadinessResult{Ready: true, Reason: interfaces.ReadinessReasonSnapshotComplete}, nil)

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
		Return((*interfaces.ReadinessResult)(nil), errors.New("database error"))

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

func TestMarkAsReceived_FlagDisabled(t *testing.T) {
	mockFeatures := featuresmock.NewFeaturesClientAllOff()
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	svc := service{features: mockFeatures, dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

	snapshot := &interfaces.Snapshot{
		RepositoryID: 1,
		Metadata:     interfaces.Metadata{"event_id": "42"},
	}

	svc.markAsReceived(context.Background(), snapshot, 100)

	mockEventSvc.AssertNotCalled(t, "MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestMarkAsReceived_NoEventID(t *testing.T) {
	mockFeatures := featuresmock.NewMockFeaturesClient()
	mockFeatures.On("IsFeatureFlagEnabledForRepository", mock.Anything, RepositoryAlertingFeatureFlag, uint64(1)).Return(true, nil)
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	svc := service{features: mockFeatures, dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

	snapshot := &interfaces.Snapshot{
		RepositoryID: 1,
		Metadata:     interfaces.Metadata{},
	}

	svc.markAsReceived(context.Background(), snapshot, 100)

	mockEventSvc.AssertNotCalled(t, "MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestMarkAsReceived_BlankEventID(t *testing.T) {
	mockFeatures := featuresmock.NewMockFeaturesClient()
	mockFeatures.On("IsFeatureFlagEnabledForRepository", mock.Anything, RepositoryAlertingFeatureFlag, uint64(1)).Return(true, nil)
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	svc := service{features: mockFeatures, dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

	snapshot := &interfaces.Snapshot{
		RepositoryID: 1,
		Metadata:     interfaces.Metadata{"event_id": ""},
	}

	svc.markAsReceived(context.Background(), snapshot, 100)

	mockEventSvc.AssertNotCalled(t, "MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestMarkAsReceived_InvalidEventID(t *testing.T) {
	mockFeatures := featuresmock.NewMockFeaturesClient()
	mockFeatures.On("IsFeatureFlagEnabledForRepository", mock.Anything, RepositoryAlertingFeatureFlag, uint64(1)).Return(true, nil)
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	svc := service{features: mockFeatures, dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

	snapshot := &interfaces.Snapshot{
		RepositoryID: 1,
		Metadata:     interfaces.Metadata{"event_id": "not-a-number"},
	}

	svc.markAsReceived(context.Background(), snapshot, 100)

	mockEventSvc.AssertNotCalled(t, "MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestMarkAsReceived_ZeroEventID(t *testing.T) {
	mockFeatures := featuresmock.NewMockFeaturesClient()
	mockFeatures.On("IsFeatureFlagEnabledForRepository", mock.Anything, RepositoryAlertingFeatureFlag, uint64(1)).Return(true, nil)
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	svc := service{features: mockFeatures, dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

	snapshot := &interfaces.Snapshot{
		RepositoryID: 1,
		Metadata:     interfaces.Metadata{"event_id": "0"},
	}

	svc.markAsReceived(context.Background(), snapshot, 100)

	mockEventSvc.AssertNotCalled(t, "MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestMarkAsReceived_EmptyManifests(t *testing.T) {
	mockFeatures := featuresmock.NewMockFeaturesClient()
	mockFeatures.On("IsFeatureFlagEnabledForRepository", mock.Anything, RepositoryAlertingFeatureFlag, uint64(1)).Return(true, nil)
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	svc := service{features: mockFeatures, dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

	snapshot := &interfaces.Snapshot{
		RepositoryID: 1,
		Metadata:     interfaces.Metadata{"event_id": "42", "status": "failed"},
		Manifests:    interfaces.Manifests{},
	}

	svc.markAsReceived(context.Background(), snapshot, 100)

	mockEventSvc.AssertNotCalled(t, "MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestMarkAsReceived_IncompleteManifestData(t *testing.T) {
	mockFeatures := featuresmock.NewMockFeaturesClient()
	mockFeatures.On("IsFeatureFlagEnabledForRepository", mock.Anything, RepositoryAlertingFeatureFlag, uint64(1)).Return(true, nil)
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	svc := service{features: mockFeatures, dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

	snapshot := &interfaces.Snapshot{
		RepositoryID: 1,
		Metadata:     interfaces.Metadata{"event_id": "42"},
		Manifests: interfaces.Manifests{
			"go.mod": &interfaces.Manifest{
				Name:     "go.mod",
				File:     interfaces.FileInfo{SourceLocation: "go.mod"},
				Metadata: interfaces.Metadata{},
			},
		},
	}

	svc.markAsReceived(context.Background(), snapshot, 100)

	mockEventSvc.AssertNotCalled(t, "MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestMarkAsReceived_BlankSourceLocation(t *testing.T) {
	mockFeatures := featuresmock.NewMockFeaturesClient()
	mockFeatures.On("IsFeatureFlagEnabledForRepository", mock.Anything, RepositoryAlertingFeatureFlag, uint64(1)).Return(true, nil)
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	svc := service{features: mockFeatures, dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

	snapshot := &interfaces.Snapshot{
		RepositoryID: 1,
		Metadata:     interfaces.Metadata{"event_id": "42"},
		Manifests: interfaces.Manifests{
			"go.mod": &interfaces.Manifest{
				Name:     "go.mod",
				File:     interfaces.FileInfo{SourceLocation: ""},
				Metadata: interfaces.Metadata{"ecosystem": "golang"},
			},
		},
	}

	svc.markAsReceived(context.Background(), snapshot, 100)

	mockEventSvc.AssertNotCalled(t, "MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestMarkAsReceived_Success(t *testing.T) {
	mockFeatures := featuresmock.NewMockFeaturesClient()
	mockFeatures.On("IsFeatureFlagEnabledForRepository", mock.Anything, RepositoryAlertingFeatureFlag, uint64(1)).Return(true, nil)
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	mockEventSvc.On("MarkSnapshotReceived", mock.Anything, uint64(42), uint64(100), ecosystems.Golang, ".").Return(true, nil)
	svc := service{features: mockFeatures, dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

	snapshot := &interfaces.Snapshot{
		RepositoryID: 1,
		Metadata:     interfaces.Metadata{"event_id": "42"},
		Manifests: interfaces.Manifests{
			"go.mod": &interfaces.Manifest{
				Name:     "go.mod",
				File:     interfaces.FileInfo{SourceLocation: "go.mod"},
				Metadata: interfaces.Metadata{"ecosystem": "golang"},
			},
		},
	}

	svc.markAsReceived(context.Background(), snapshot, 100)

	mockEventSvc.AssertCalled(t, "MarkSnapshotReceived", mock.Anything, uint64(42), uint64(100), ecosystems.Golang, ".")
}

func TestMarkAsReceived_MultipleManifests(t *testing.T) {
	mockFeatures := featuresmock.NewMockFeaturesClient()
	mockFeatures.On("IsFeatureFlagEnabledForRepository", mock.Anything, RepositoryAlertingFeatureFlag, uint64(1)).Return(true, nil)
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	mockEventSvc.On("MarkSnapshotReceived", mock.Anything, uint64(42), uint64(100), ecosystems.Golang, ".").Return(true, nil)
	mockEventSvc.On("MarkSnapshotReceived", mock.Anything, uint64(42), uint64(100), ecosystems.NPM, "frontend").Return(true, nil)
	svc := service{features: mockFeatures, dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

	snapshot := &interfaces.Snapshot{
		RepositoryID: 1,
		Metadata:     interfaces.Metadata{"event_id": "42"},
		Manifests: interfaces.Manifests{
			"go.mod": &interfaces.Manifest{
				Name:     "go.mod",
				File:     interfaces.FileInfo{SourceLocation: "go.mod"},
				Metadata: interfaces.Metadata{"ecosystem": "golang"},
			},
			"frontend/package.json": &interfaces.Manifest{
				Name:     "package.json",
				File:     interfaces.FileInfo{SourceLocation: "frontend/package.json"},
				Metadata: interfaces.Metadata{"ecosystem": "npm"},
			},
		},
	}

	svc.markAsReceived(context.Background(), snapshot, 100)

	mockEventSvc.AssertCalled(t, "MarkSnapshotReceived", mock.Anything, uint64(42), uint64(100), ecosystems.Golang, ".")
	mockEventSvc.AssertCalled(t, "MarkSnapshotReceived", mock.Anything, uint64(42), uint64(100), ecosystems.NPM, "frontend")
}

func TestMarkAsReceived_ErrorDoesNotPanic(t *testing.T) {
	mockFeatures := featuresmock.NewMockFeaturesClient()
	mockFeatures.On("IsFeatureFlagEnabledForRepository", mock.Anything, RepositoryAlertingFeatureFlag, uint64(1)).Return(true, nil)
	mockEventSvc := &dependabotmock.MockedDependabotEventService{}
	mockEventSvc.On("MarkSnapshotReceived", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(false, assert.AnError)
	svc := service{features: mockFeatures, dependabotEventSvc: mockEventSvc, statter: stats.NullStatter}

	snapshot := &interfaces.Snapshot{
		RepositoryID: 1,
		Metadata:     interfaces.Metadata{"event_id": "42"},
		Manifests: interfaces.Manifests{
			"go.mod": &interfaces.Manifest{
				Name:     "go.mod",
				File:     interfaces.FileInfo{SourceLocation: "go.mod"},
				Metadata: interfaces.Metadata{"ecosystem": "go"},
			},
		},
	}

	assert.NotPanics(t, func() {
		svc.markAsReceived(context.Background(), snapshot, 100)
	})
}
