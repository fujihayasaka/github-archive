package eventhandlers_test

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/internal/monolith"
	"github.com/github/licensify/testing/helpers"
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	entities "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
)

type repositoryAddMemberTestSuite struct {
	suite.Suite
	mockDB  *mocks.MockDBReadWriter
	handler *eventhandlers.EventHandler
}

func (s *repositoryAddMemberTestSuite) SetupTest() {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	mockDB := &mocks.MockDBReadWriter{}
	s.mockDB = mockDB
	jobby := &jobs.Jobby{Cfg: cfg, AqueductClient: &mocks.MockAqueductClient{}}

	handler, _ := eventhandlers.NewEventHandler(mockDB, jobby, &monolith.Client{}, statter, tracer)
	s.handler = handler
}

func (s *repositoryAddMemberTestSuite) TestHandleEnvelopeSkipsAdvisoryWorkspace() {
	logger := log.NewNullLogger()
	msg := stubs.NewRepositoryCollaboratorAddHydroMsg()
	msg.IsRepositoryAdvisoryWorkspace = true

	skip, err := s.handler.HandleRepositoryAddMember(context.Background(), logger, msg)
	s.Require().NoError(err.Err)

	s.False(skip.IsEmpty())
	s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *repositoryAddMemberTestSuite) TestHandleEnvelopeSkipsMissingCustomerID() {
	logger := log.NewNullLogger()
	msg := stubs.NewRepositoryCollaboratorAddHydroMsg()
	msg.RepositoryOwnerCustomerId = 0

	skip, err := s.handler.HandleRepositoryAddMember(context.Background(), logger, msg)
	s.Require().NoError(err.Err)

	s.False(skip.IsEmpty())
	s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *repositoryAddMemberTestSuite) TestHandleEnvelopeSkipsMissingRepositoryID() {
	logger := log.NewNullLogger()
	msg := stubs.NewRepositoryCollaboratorAddHydroMsg()
	msg.Repository.Id = 0

	skip, err := s.handler.HandleRepositoryAddMember(context.Background(), logger, msg)
	s.Require().NoError(err.Err)

	s.False(skip.IsEmpty())
	s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *repositoryAddMemberTestSuite) TestHandleEnvelopeSkipsForkRepos() {
	logger := log.NewNullLogger()

	msg := stubs.NewRepositoryCollaboratorAddHydroMsg()
	msg.Repository.IsFork = true

	skip, err := s.handler.HandleRepositoryAddMember(context.Background(), logger, msg)
	s.Require().NoError(err.Err)

	s.False(skip.IsEmpty())
	s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)

	msg.Repository.IsFork = false
	msg.Repository.ParentId = uint32(stubs.NewRandomID())

	skip, err = s.handler.HandleRepositoryAddMember(context.Background(), logger, msg)
	s.Require().NoError(err.Err)

	s.False(skip.IsEmpty())
	s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *repositoryAddMemberTestSuite) TestHandleEnvelopeSkipsPublicRepos() {
	logger := log.NewNullLogger()

	msg := stubs.NewRepositoryCollaboratorAddHydroMsg()
	msg.Repository.Visibility = entities.Repository_PUBLIC

	skip, err := s.handler.HandleRepositoryAddMember(context.Background(), logger, msg)
	s.Require().NoError(err.Err)

	s.False(skip.IsEmpty())
	s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)

	msg.Repository.Visibility = entities.Repository_VISIBILITY_UNKNOWN

	skip, err = s.handler.HandleRepositoryAddMember(context.Background(), logger, msg)
	s.Require().NoError(err.Err)

	s.False(skip.IsEmpty())
	s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *repositoryAddMemberTestSuite) TestHandleEnvelopeSkipsMissingLicenseeID() {
	logger := log.NewNullLogger()
	msg := stubs.NewRepositoryCollaboratorAddHydroMsg()
	msg.Member.Id = 0

	skip, err := s.handler.HandleRepositoryAddMember(context.Background(), logger, msg)
	s.Require().NoError(err.Err)

	s.False(skip.IsEmpty())
	s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *repositoryAddMemberTestSuite) TestUpsertsLicenseWhenNoneExists() {
	helpers.LockUUIDGeneration()
	defer helpers.ResetUUIDGeneration()

	logger := log.NewNullLogger()

	msg := stubs.NewRepositoryCollaboratorAddHydroMsg()

	customerID := msg.RepositoryOwnerCustomerId
	userID := msg.Member.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	wantCustomerLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{},
		models.MaxExpiresAt,
		nil,
	)
	wantCustomerLicense.AddRepositoryCollaborators(uint64(msg.Repository.Id))
	wantCustomerLicense.AddETag()

	wantMarshalledCustomerLicense, err := json.Marshal(wantCustomerLicense)
	s.Require().NoError(err)
	wantLicenseeLicense := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense)
	wantMarshalledLicenseeLicense, err := json.Marshal(wantLicenseeLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantCustomerLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, &azcore.ResponseError{StatusCode: http.StatusNotFound}).Once()
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantMarshalledCustomerLicense,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicenseKey.PartitionKey),
		wantMarshalledLicenseeLicense,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	_, herr := s.handler.HandleRepositoryAddMember(context.Background(), logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *repositoryAddMemberTestSuite) TestAddsCollaboratorToExistingLicense() {
	logger := log.NewNullLogger()

	msg := stubs.NewRepositoryCollaboratorAddHydroMsg()

	customerID := msg.RepositoryOwnerCustomerId
	userID := msg.Member.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, []uint64{1}),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledOldLicense, err := json.Marshal(oldLicense)
	s.Require().NoError(err)

	wantCustomerLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, []uint64{1}),
		},
		models.MaxExpiresAt,
		nil,
	)
	wantCustomerLicense.AddRepositoryCollaborators(uint64(msg.Repository.Id))
	wantMarshalledCustomerLicense, err := json.Marshal(wantCustomerLicense)
	s.Require().NoError(err)
	wantLicenseeLicense := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense)
	wantMarshalledLicenseeLicense, err := json.Marshal(wantLicenseeLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantCustomerLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledOldLicense}, nil).Once()
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantMarshalledCustomerLicense,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicenseKey.PartitionKey),
		wantMarshalledLicenseeLicense,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	_, herr := s.handler.HandleRepositoryAddMember(context.Background(), logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *repositoryAddMemberTestSuite) TestAddingACollaboratorAlreadyInTheLicense() {
	// Adding a collaborator that already exists in the license shouldn't be encountered,
	// but in the case it happens it will be a noop.
	logger := log.NewNullLogger()

	msg := stubs.NewRepositoryCollaboratorAddHydroMsg()

	customerID := msg.RepositoryOwnerCustomerId
	userID := msg.Member.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{},
		models.MaxExpiresAt,
		nil,
	)
	oldLicense.AddRepositoryCollaborators(uint64(msg.Repository.Id))
	marshalledOldLicense, err := json.Marshal(oldLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantKey.PartitionKey),
		wantKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledOldLicense}, nil).Once()

	_, herr := s.handler.HandleRepositoryAddMember(context.Background(), logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestRepositoryCollaboratorHandlerSuite(t *testing.T) {
	suite.Run(t, new(repositoryAddMemberTestSuite))
}
