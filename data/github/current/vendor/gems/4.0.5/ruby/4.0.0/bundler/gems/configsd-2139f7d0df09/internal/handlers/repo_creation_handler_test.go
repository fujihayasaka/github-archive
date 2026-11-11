package handlers

import (
	"errors"
	"strings"
	"testing"

	repositoriesv1 "github.com/github/configsd/internal/hydro/schemas/github/repositories/v1"
	"github.com/github/configsd/internal/hydro/schemas/github/v2/entities"
	"github.com/github/configsd/internal/mocks"
	"github.com/github/configsd/internal/model"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"go.uber.org/mock/gomock"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// testMocks holds all the mock objects needed for testing
type testMocks struct {
	store   *model.MockStore
	logger  *mocks.MockLogger
	flagger *mocks.MockFlagger
}

// setupMocks creates and returns all necessary mock objects
func setupMocks(ctrl *gomock.Controller) *testMocks {
	return &testMocks{
		store:   model.NewMockStore(ctrl),
		logger:  mocks.NewMockLogger(ctrl),
		flagger: mocks.NewMockFlagger(ctrl),
	}
}

// createRepositoryMessage creates and marshals a repository creation message
func createRepositoryMessage(t *testing.T, repositoryID int64, ownerID *int32) []byte {
	repoEvent := &repositoriesv1.Created{
		RepositoryId: repositoryID,
		Repository: &entities.Repository{
			Name: "test-repo",
		},
	}

	if ownerID != nil {
		repoEvent.Repository.OwnerId = wrapperspb.Int32(*ownerID)
	}

	messageBytes, err := proto.Marshal(repoEvent)
	if err != nil {
		t.Fatalf("Failed to marshal protobuf message: %v", err)
	}

	return messageBytes
}

// createHydroMessage creates a hydro message with the given parameters
func createHydroMessage(partition int32, offset int64, value []byte) hydro.Message {
	return hydro.Message{
		Topic:     RepoCreationHandlerTopic,
		Partition: partition,
		Offset:    offset,
		Value:     value,
	}
}

func TestRepoCreationHandler_NegativeIDValidation(t *testing.T) {
	tests := []struct {
		name             string
		repositoryID     int64
		ownerID          int32
		expectWarningLog bool
		logMessage       string
		partition        int32
		offset           int64
	}{
		{
			name:             "Valid positive IDs",
			repositoryID:     12345,
			ownerID:          67890,
			expectWarningLog: false,
			partition:        0,
			offset:           1,
		},
		{
			name:             "Negative repository ID",
			repositoryID:     -12345,
			ownerID:          67890,
			expectWarningLog: true,
			logMessage:       "ID is negative",
			partition:        0,
			offset:           1,
		},
		{
			name:             "Negative owner ID",
			repositoryID:     12345,
			ownerID:          -67890,
			expectWarningLog: true,
			logMessage:       "ID is negative",
			partition:        0,
			offset:           1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup mocks
			ctrl := gomock.NewController(t)
			defer ctrl.Finish()

			testMocks := setupMocks(ctrl)

			testMocks.flagger.EXPECT().
				IsEnabledWithDefaultValue(gomock.Any(), "configsd_persist_repo_owners", false).
				Return(true).
				AnyTimes()

			// Only expect SetRepositoryOwner call if no warning log is expected (valid case)
			if !tt.expectWarningLog {
				testMocks.store.EXPECT().
					SetRepositoryOwner(t.Context(), uint64(tt.repositoryID), uint64(tt.ownerID)).
					Return(nil)

				// Expect debug log for successful processing
				testMocks.logger.EXPECT().
					Debug("Message processed.", gomock.Any()).
					Times(1)
			} else {
				// Expect warning log for negative IDs
				testMocks.logger.EXPECT().
					Log(log.WarnLevel, tt.logMessage,
						kvp.String("topic", RepoCreationHandlerTopic),
						kvp.Int32("partition", tt.partition),
						kvp.Int64("offset", tt.offset)).
					Times(1)
			}

			stop := func() { t.Fail() } // Fail the test if stop is called unexpectedly

			// Create the handler
			handler := NewRepoCreationHandler(testMocks.store, testMocks.logger, testMocks.flagger, stop)

			// Create and marshal the protobuf message
			messageBytes := createRepositoryMessage(t, tt.repositoryID, &tt.ownerID)

			// Create hydro message
			hydroMessage := createHydroMessage(tt.partition, tt.offset, messageBytes)

			// Execute the handler
			err := handler(t.Context(), hydroMessage)

			// Verify results - negative IDs should not return errors, they should log and skip processing
			if err != nil {
				t.Errorf("Handler returned unexpected error: %v", err)
			}
		})
	}
}

func TestRepoCreationHandler_ProtobufUnmarshalError(t *testing.T) {
	// Setup mocks
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	testMocks := setupMocks(ctrl)

	// No store expectations set since we should fail before calling the store

	// Expect error log for unmarshal failure
	testMocks.logger.EXPECT().
		Log(log.ErrorLevel, "failed to unmarshal message",
			kvp.String("topic", RepoCreationHandlerTopic),
			kvp.Int32("partition", int32(0)),
			kvp.Int64("offset", int64(1))).
		Times(1)

	ctxCancelled := false
	stop := func() { ctxCancelled = true }

	// Create the handler
	handler := NewRepoCreationHandler(testMocks.store, testMocks.logger, testMocks.flagger, stop)

	// Create hydro message with invalid protobuf data
	hydroMessage := createHydroMessage(0, 1, []byte("invalid protobuf data"))

	// Execute the handler
	err := handler(t.Context(), hydroMessage)

	if !ctxCancelled {
		t.Errorf("Expected context to be cancelled on unmarshal error")
	}

	// Verify error
	if err == nil {
		t.Errorf("Expected error for invalid protobuf data but got none")
	}
	if !strings.Contains(err.Error(), "failed to unmarshal message") {
		t.Errorf("Expected error message to contain 'failed to unmarshal message', got: %s", err.Error())
	}
}

func TestRepoCreationHandler_MissingOwnerID(t *testing.T) {
	// Setup mocks
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	testMocks := setupMocks(ctrl)

	// No store expectations set since we should skip processing

	// Expect error log for missing owner ID
	testMocks.logger.EXPECT().
		Log(log.ErrorLevel, "owner ID is nil",
			kvp.String("topic", RepoCreationHandlerTopic),
			kvp.Int32("partition", int32(0)),
			kvp.Int64("offset", int64(1))).
		Times(1)

	// Create the handler
	handler := NewRepoCreationHandler(testMocks.store, testMocks.logger, testMocks.flagger, func() { t.Fail() })

	// Create the protobuf message with nil OwnerId
	messageBytes := createRepositoryMessage(t, 12345, nil) // nil owner ID

	// Create hydro message
	hydroMessage := createHydroMessage(0, 1, messageBytes)

	// Execute the handler
	err := handler(t.Context(), hydroMessage)

	// Verify no error - nil OwnerId should log warning and skip processing, not return error
	if err != nil {
		t.Errorf("Unexpected error with nil owner ID: %v", err)
	}
}

func TestRepoCreationHandler_StoreError(t *testing.T) {
	// Setup mocks
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	testMocks := setupMocks(ctrl)

	testMocks.flagger.EXPECT().
		IsEnabledWithDefaultValue(gomock.Any(), "configsd_persist_repo_owners", false).
		Return(true).
		AnyTimes()

	expectedError := errors.New("database connection failed")

	// Expect SetRepositoryOwner call to return error
	testMocks.store.EXPECT().
		SetRepositoryOwner(t.Context(), uint64(12345), uint64(67890)).
		Return(expectedError)

	// Expect error log for store error (changed from Fatal to Error)
	testMocks.logger.EXPECT().
		Error("Failed to set repository owner in db", kvp.String("error", expectedError.Error())).
		Times(1)

	ctxCancelled := false
	stop := func() { ctxCancelled = true }

	// Create the handler
	handler := NewRepoCreationHandler(testMocks.store, testMocks.logger, testMocks.flagger, stop)

	// Create the protobuf message
	ownerID := int32(67890)
	messageBytes := createRepositoryMessage(t, 12345, &ownerID)

	// Create hydro message
	hydroMessage := createHydroMessage(0, 1, messageBytes)

	// Execute the handler
	err := handler(t.Context(), hydroMessage)

	if !ctxCancelled {
		t.Errorf("Expected context to be cancelled on store error")
	}

	// Verify error
	if err == nil {
		t.Errorf("Expected error from store but got none")
	}
	if !strings.Contains(err.Error(), "Failed to set repository owner in db") {
		t.Errorf("Expected error message to contain 'Failed to set repository owner in db', got: %s", err.Error())
	}
}

func TestRepoCreationHandler_FeatureFlagDisabled(t *testing.T) {
	// Setup mocks
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	testMocks := setupMocks(ctrl)

	// Feature flag is disabled
	testMocks.flagger.EXPECT().
		IsEnabledWithDefaultValue(gomock.Any(), "configsd_persist_repo_owners", false).
		Return(false).
		AnyTimes()

	// No store expectations set - store should NOT be called when feature flag is disabled
	// This is the key assertion: mockStore should not receive any calls

	// Expect debug log for successful processing
	testMocks.logger.EXPECT().
		Debug("Message processed.", gomock.Any()).
		Times(1)

	stop := func() { t.Fail() } // Fail the test if stop is called unexpectedly

	// Create the handler
	handler := NewRepoCreationHandler(testMocks.store, testMocks.logger, testMocks.flagger, stop)

	// Create the protobuf message
	ownerID := int32(67890)
	messageBytes := createRepositoryMessage(t, 12345, &ownerID)

	// Create hydro message
	hydroMessage := createHydroMessage(0, 1, messageBytes)

	// Execute the handler
	err := handler(t.Context(), hydroMessage)

	// Verify no error and that processing completed successfully
	if err != nil {
		t.Errorf("Handler returned unexpected error: %v", err)
	}

	// The mock controller will automatically verify that no unexpected calls were made to the store
}
