package handlers_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/licensify/internal/aqueduct/handlers"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	repositoriesV1 "github.com/github/licensify/lib/monolith-twirp/repositories/v1"
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type createRepositoryCollaboratorsHandlerTestSuite struct {
	suite.Suite
	cfg             *config.Config
	mockDB          *mocks.MockDBReadWriter
	mockMonolithAPI *mocks.MockMonolithAPI
	handler         *handlers.CreateRepositoryCollaboratorsHandler
}

func (s *createRepositoryCollaboratorsHandlerTestSuite) SetupTest() {
	cfg, _ := config.Load()
	s.cfg = cfg
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	s.mockDB = &mocks.MockDBReadWriter{}
	s.mockMonolithAPI = &mocks.MockMonolithAPI{}
	customerLicenseEngine := engines.NewCustomerLicenseEngine(statter, tracer, s.mockDB)
	licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(statter, tracer, s.mockDB)
	s.handler = handlers.NewCreateRepositoryCollaboratorsHandler(statter, tracer, s.mockMonolithAPI, customerLicenseEngine, licenseeLicenseEngine)
}

func (s *createRepositoryCollaboratorsHandlerTestSuite) TestHandlerSkipsInvalidRepositories() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()
	repoID := stubs.NewRandomID()

	baseResponse := stubs.NewRepositoryFromHydroEntity()
	baseResponse.Id = repoID
	baseResponse.OwnerCustomerId = int64(customerID)

	skipsInactive := baseResponse
	skipsInactive.IsActive = false

	skipsFork1 := baseResponse
	skipsFork1.IsFork = true
	skipsFork2 := baseResponse
	skipsFork2.ParentId = 1

	skipsAdvisoryWorkspace := baseResponse
	skipsAdvisoryWorkspace.IsAdvisoryWorkspace = true

	tests := []struct {
		name         string
		twirpReponse *repositoriesV1.GetRepositoryInformationResponse
	}{
		{
			name: "skips inactive repository",
			twirpReponse: &repositoriesV1.GetRepositoryInformationResponse{
				Repository:      skipsInactive,
				CollaboratorIds: []uint64{userID},
			},
		},
		{
			name: "skips repository that's flagged a fork",
			twirpReponse: &repositoriesV1.GetRepositoryInformationResponse{
				Repository:      skipsFork1,
				CollaboratorIds: []uint64{userID},
			},
		},
		{
			name: "skips repository with parent ID set (aka a fork)",
			twirpReponse: &repositoriesV1.GetRepositoryInformationResponse{
				Repository:      skipsFork2,
				CollaboratorIds: []uint64{userID},
			},
		},
		{
			name: "skips repository that's an advisory workspace",
			twirpReponse: &repositoriesV1.GetRepositoryInformationResponse{
				Repository:      skipsAdvisoryWorkspace,
				CollaboratorIds: []uint64{userID},
			},
		},
		{
			name: "skips repository with no collaborators",
			twirpReponse: &repositoriesV1.GetRepositoryInformationResponse{
				Repository:      baseResponse,
				CollaboratorIds: []uint64{},
			},
		},
	}
	for _, tt := range tests {
		s.Run(tt.name, func() {
			payload, err := json.Marshal(&models.CreateRepositoryCollaboratorsJob{RepositoryID: repoID})
			s.Require().NoError(err)

			request := &repositoriesV1.GetRepositoryInformationRequest{
				Id:                   repoID,
				IncludeCollaborators: true,
			}
			s.mockMonolithAPI.On("GetRepositoryInformation", mock.Anything, request).Return(tt.twirpReponse, nil).Once()

			job := &aqueduct.Job{Payload: payload}
			rr := &aqueduct.ReceiveResult{Job: *job}
			s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))

			s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything)
			s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything)
			s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything)
		})
	}
}

func (s *createRepositoryCollaboratorsHandlerTestSuite) TestHandlerRetriesOnPreconditionFailedError() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()
	repoID := stubs.NewRandomID()

	request := &repositoriesV1.GetRepositoryInformationRequest{
		Id:                   repoID,
		IncludeCollaborators: true,
	}
	repoResponse := stubs.NewRepositoryFromHydroEntity()
	repoResponse.Id = repoID
	repoResponse.OwnerCustomerId = int64(customerID)
	response := &repositoriesV1.GetRepositoryInformationResponse{
		Repository:      repoResponse,
		CollaboratorIds: []uint64{userID},
	}
	s.mockMonolithAPI.On("GetRepositoryInformation", mock.Anything, request).Return(response, nil).Once()

	eTag := azcore.ETag("etag")

	customerLicense := models.NewCustomerLicenseForUserWithRepositoryCollaborator(customerID, userID, repoID)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	wantCustomerLicense := models.NewCustomerLicenseForUserWithRepositoryCollaborator(customerID, userID, 10)
	wantCustomerLicense.ETag = &eTag
	wantCustomerLicenseBytes, err := json.Marshal(wantCustomerLicense)
	s.Require().NoError(err)

	preconditionFailedErr := runtime.NewResponseError(&http.Response{StatusCode: http.StatusPreconditionFailed})
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		wantCustomerLicenseBytes,
		&azcosmos.ItemOptions{IfMatchEtag: &eTag},
	).Return(nil, preconditionFailedErr).Once()
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		wantCustomerLicenseBytes,
		&azcosmos.ItemOptions{IfMatchEtag: &eTag},
	).Return(azcosmos.ItemResponse{}, nil).Once()

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		customerLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerLicenseBytes}, nil).Once()

	wantLicenseeLicense := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense)
	wantLicenseeLicenseBytes, err := json.Marshal(wantLicenseeLicense)
	s.Require().NoError(err)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicense.ID,
		mock.Anything,
	).Return(nil, &azcore.ResponseError{StatusCode: http.StatusNotFound}).Once()
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicenseBytes,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	jobPayload, err := json.Marshal(models.NewCreateRepositoryCollaboratorsJob(repoID, customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
}

func (s *createRepositoryCollaboratorsHandlerTestSuite) TestHandlerReturnsErrorWhenRetriesExhausted() {
	telem, _ := telemetry.NewFromEnv()
	logger := s.cfg.ConfigureLogger(telem.Logger, s.cfg.ServiceName).Named("queue-worker")
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()
	existingRepoID := stubs.NewRandomID()
	newRepoID := stubs.NewRandomID()
	attempts := 10

	request := &repositoriesV1.GetRepositoryInformationRequest{
		Id:                   newRepoID,
		IncludeCollaborators: true,
	}
	repoResponse := stubs.NewRepositoryFromHydroEntity()
	repoResponse.Id = newRepoID
	repoResponse.OwnerCustomerId = int64(customerID)
	response := &repositoriesV1.GetRepositoryInformationResponse{
		Repository:      repoResponse,
		CollaboratorIds: []uint64{userID},
	}
	s.mockMonolithAPI.On("GetRepositoryInformation", mock.Anything, request).Return(response, nil).Once()

	eTag := azcore.ETag("etag")

	customerLicense := models.NewCustomerLicenseForUserWithRepositoryCollaborator(customerID, userID, existingRepoID)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	wantCustomerLicense := models.NewCustomerLicenseForUserWithRepositoryCollaborator(customerID, userID, existingRepoID)
	wantCustomerLicense.AddRepositoryCollaborators(newRepoID)
	wantCustomerLicense.ETag = &eTag
	wantCustomerLicenseBytes, err := json.Marshal(wantCustomerLicense)
	s.Require().NoError(err)

	wantErr := runtime.NewResponseError(&http.Response{StatusCode: http.StatusPreconditionFailed})

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		wantCustomerLicenseBytes,
		&azcosmos.ItemOptions{IfMatchEtag: &eTag},
	).Return(nil, wantErr).Times(attempts)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		customerLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerLicenseBytes}, nil).Times(attempts)

	job := models.NewCreateRepositoryCollaboratorsJob(newRepoID, customerID)
	jobPayload, err := json.Marshal(job)
	s.Require().NoError(err)
	aqueductJob := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *aqueductJob}

	s.Require().Error(s.handler.ProcessMessage(context.Background(), logger, *rr))
}

func (s *createRepositoryCollaboratorsHandlerTestSuite) TestHandlerDoesNotUpsertLicenseeLicenseWhenRecordExists() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()
	repoID := stubs.NewRandomID()

	request := &repositoriesV1.GetRepositoryInformationRequest{
		Id:                   repoID,
		IncludeCollaborators: true,
	}
	repoResponse := stubs.NewRepositoryFromHydroEntity()
	repoResponse.Id = repoID
	repoResponse.OwnerCustomerId = int64(customerID)
	response := &repositoriesV1.GetRepositoryInformationResponse{
		Repository:      repoResponse,
		CollaboratorIds: []uint64{userID},
	}
	s.mockMonolithAPI.On("GetRepositoryInformation", mock.Anything, request).Return(response, nil).Once()

	eTag := azcore.ETag("etag")

	customerLicense := models.NewCustomerLicenseForUserWithRepositoryCollaborator(customerID, userID, repoID)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		customerLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerLicenseBytes}, nil).Once()

	wantCustomerLicense := models.NewCustomerLicenseForUserWithRepositoryCollaborator(customerID, userID, 10)
	wantCustomerLicense.ETag = &eTag
	wantCustomerLicenseBytes, err := json.Marshal(wantCustomerLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		wantCustomerLicenseBytes,
		&azcosmos.ItemOptions{IfMatchEtag: &eTag},
	).Return(&azcosmos.ItemResponse{}, nil).Once()

	wantLicenseeLicense := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense)
	wantLicenseeLicenseBytes, err := json.Marshal(wantLicenseeLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: wantCustomerLicenseBytes}, nil).Once()

	jobPayload, err := json.Marshal(models.NewCreateRepositoryCollaboratorsJob(repoID, customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))

	s.mockDB.AssertNotCalled(s.T(),
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicenseBytes,
		mock.Anything,
	)
}

func (s *createRepositoryCollaboratorsHandlerTestSuite) TestHandlerCreatesCollaborators() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	repoID := stubs.NewRandomID()
	collaboratorID := stubs.NewRandomID()

	request := &repositoriesV1.GetRepositoryInformationRequest{
		Id:                   repoID,
		IncludeCollaborators: true,
	}
	repoResponse := stubs.NewRepositoryFromHydroEntity()
	repoResponse.Id = repoID
	repoResponse.OwnerCustomerId = int64(customerID)
	response := &repositoriesV1.GetRepositoryInformationResponse{
		Repository:      repoResponse,
		CollaboratorIds: []uint64{collaboratorID},
	}
	s.mockMonolithAPI.On("GetRepositoryInformation", mock.Anything, request).Return(response, nil).Once()

	wantCustomerLicense := models.NewCustomerLicenseForUserWithRepositoryCollaborator(customerID, collaboratorID, repoID)
	wantCustomerLicenseBytes, err := json.Marshal(wantCustomerLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicense.PartitionKey),
		wantCustomerLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: wantCustomerLicenseBytes}, nil).Once()

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicense.PartitionKey),
		wantCustomerLicenseBytes,
		mock.AnythingOfType("*azcosmos.ItemOptions"),
	).Return(azcosmos.ItemResponse{}, nil).Once()

	wantLicenseeLicense := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense)
	wantLicenseeLicenseBytes, err := json.Marshal(wantLicenseeLicense)
	s.Require().NoError(err)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: wantLicenseeLicenseBytes}, nil).Once()

	job := models.NewCreateRepositoryCollaboratorsJob(repoID, customerID)
	jobPayload, err := json.Marshal(job)
	s.Require().NoError(err)
	aqueductJob := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *aqueductJob}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
}

func (s *createRepositoryCollaboratorsHandlerTestSuite) TestHandlerAddsCollaboratorOnExistingLicense() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	repoID := stubs.NewRandomID()
	orgID := stubs.NewRandomID()
	collaboratorID := stubs.NewRandomID()

	request := &repositoriesV1.GetRepositoryInformationRequest{
		Id:                   repoID,
		IncludeCollaborators: true,
	}
	repoResponse := stubs.NewRepositoryFromHydroEntity()
	repoResponse.Id = repoID
	repoResponse.OwnerCustomerId = int64(customerID)
	response := &repositoriesV1.GetRepositoryInformationResponse{
		Repository:      repoResponse,
		CollaboratorIds: []uint64{collaboratorID},
	}
	s.mockMonolithAPI.On("GetRepositoryInformation", mock.Anything, request).Return(response, nil).Once()

	initialCustomerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, collaboratorID, orgID)
	initialCustomerLicenseBytes, err := json.Marshal(initialCustomerLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(initialCustomerLicense.PartitionKey),
		initialCustomerLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: initialCustomerLicenseBytes}, nil).Once()

	wantCustomerLicense := models.NewCustomerLicenseForUserWithMemberships(customerID, collaboratorID, []uint64{orgID}, []uint64{repoID})
	wantCustomerLicenseBytes, err := json.Marshal(wantCustomerLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicense.PartitionKey),
		wantCustomerLicenseBytes,
		mock.AnythingOfType("*azcosmos.ItemOptions"),
	).Return(azcosmos.ItemResponse{}, nil).Once()

	wantLicenseeLicense := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense)
	wantLicenseeLicenseBytes, err := json.Marshal(wantLicenseeLicense)
	s.Require().NoError(err)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: wantLicenseeLicenseBytes}, nil).Once()

	job := models.NewCreateRepositoryCollaboratorsJob(repoID, customerID)
	jobPayload, err := json.Marshal(job)
	s.Require().NoError(err)
	aqueductJob := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *aqueductJob}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
}

func TestCreateRepositoryCollaboratorsHandlerTestSuite(t *testing.T) {
	suite.Run(t, new(createRepositoryCollaboratorsHandlerTestSuite))
}
