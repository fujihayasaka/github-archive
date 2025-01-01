package eventhandlers_test

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
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
)

type membershipUpdateTestSuite struct {
	suite.Suite
	mockDB  *mocks.MockDBReadWriter
	handler *eventhandlers.EventHandler
	logger  log.Logger
}

func (s *membershipUpdateTestSuite) SetupTest() {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	mockDB := &mocks.MockDBReadWriter{}
	s.mockDB = mockDB
	s.logger = log.NewNullLogger()
	jobby := &jobs.Jobby{Cfg: cfg, AqueductClient: &mocks.MockAqueductClient{}}

	handler, _ := eventhandlers.NewEventHandler(mockDB, jobby, &monolith.Client{}, statter, tracer)
	s.handler = handler
}

func (s *membershipUpdateTestSuite) TestHandlerSkipsMessage() {
	tests := []struct {
		name       string
		context    githubv1.MembershipUpdate_Context
		action     githubv1.MembershipUpdate_Action
		customerID int64
	}{
		{
			name:       "missing customer ID",
			context:    *githubv1.MembershipUpdate_ORGANIZATION.Enum(),
			action:     *githubv1.MembershipUpdate_ADD.Enum(),
			customerID: 0,
		},
		{
			name:       "skips unsupported context",
			context:    *githubv1.MembershipUpdate_TEAM.Enum(),
			action:     *githubv1.MembershipUpdate_ADD.Enum(),
			customerID: -1,
		},
		{
			name:       "skips unknown context",
			context:    *githubv1.MembershipUpdate_CONTEXT_UNKNOWN.Enum(),
			action:     *githubv1.MembershipUpdate_ADD.Enum(),
			customerID: -1,
		},
	}
	for _, tt := range tests {
		s.Run(tt.name, func() {
			msg := stubs.NewMembershipUpdateHydroMsg(tt.context, tt.action)
			if tt.customerID >= 0 {
				msg.CustomerId = tt.customerID
			}

			_, skip, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
			s.Require().NoError(herr.Err)
			s.False(skip.IsEmpty())
			s.mockDB.AssertNotCalled(s.T(), "ReadItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
			s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
			s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
		})
	}
}

func (s *membershipUpdateTestSuite) TestUpsertsLicenseWhenNoneExists() {
	helpers.LockUUIDGeneration()
	defer helpers.ResetUUIDGeneration()

	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_ADD.Enum())

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	wantCustomerLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, []uint64{msg.GroupId}),
		},
		models.MaxExpiresAt,
		nil,
	)
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

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *membershipUpdateTestSuite) TestAddsOrgToExistingLicense() {
	oldOrgIDs := []uint64{100, 200, 300}

	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_ADD.Enum())

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, oldOrgIDs),
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
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, append(oldOrgIDs, msg.GroupId)),
		},
		models.MaxExpiresAt,
		nil,
	)
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

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *membershipUpdateTestSuite) TestAddsOrgToAnExistingLicenseWithoutAnyEnablements() {
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_ADD.Enum())

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{},
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
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, []uint64{msg.GroupId}),
		},
		models.MaxExpiresAt,
		nil,
	)
	wantLicenseeLicense := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense)

	wantMarshalledCustomerLicense, err := json.Marshal(wantCustomerLicense)
	s.Require().NoError(err)
	wantMarshalledLicenseeLicense, err := json.Marshal(wantLicenseeLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantCustomerLicenseKey.ID,
		mock.Anything).Return(azcosmos.ItemResponse{Value: marshalledOldLicense}, nil).Once()
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantMarshalledCustomerLicense,
		mock.Anything).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicenseKey.PartitionKey),
		wantMarshalledLicenseeLicense,
		mock.Anything).Return(azcosmos.ItemResponse{}, nil).Once()

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *membershipUpdateTestSuite) TestRemovesOrgFromExistingLicense() {
	oldOrgIDs := []uint64{100, 200, 300}

	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())
	msg.GroupId = 200

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, oldOrgIDs),
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
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, []uint64{100, 300}),
		},
		models.MaxExpiresAt,
		nil,
	)
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

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *membershipUpdateTestSuite) TestRemovesRepoCollaboratorFromExistingLicense() {
	oldRepoIDs := []uint64{100, 200, 300}

	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_REPOSITORY.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())
	msg.GroupId = 200

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeRepo, models.EnablementReasonRepositoryCollaborator, oldRepoIDs),
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
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeRepo, models.EnablementReasonRepositoryCollaborator, []uint64{100, 300}),
		},
		models.MaxExpiresAt,
		nil,
	)
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

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *membershipUpdateTestSuite) TestRemovingTheLastOrgMembershipDeletesLicense() {
	oldOrgIDs := []uint64{100}

	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())
	msg.GroupId = 100

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, oldOrgIDs),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledOldLicense, err := json.Marshal(oldLicense)
	s.Require().NoError(err)

	customer := models.NewCustomer(uint64(customerID), models.LicensingModelVolume, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	customerIDStr := strconv.FormatInt(customerID, 10)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString("Customer"),
		customerIDStr,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerBytes}, nil).Once()

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantCustomerLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledOldLicense}, nil).Once()
	s.mockDB.On(
		"DeleteItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantCustomerLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"DeleteItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicenseKey.PartitionKey),
		wantLicenseeLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
}

func (s *membershipUpdateTestSuite) TestRemovingTheLastOrgMembershipDeletesLicenseForMeteredForTrial() {
	oldOrgIDs := []uint64{100}

	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())
	msg.GroupId = 100

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, oldOrgIDs),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledOldLicense, err := json.Marshal(oldLicense)
	s.Require().NoError(err)

	customer := models.NewCustomer(uint64(customerID), models.LicensingModelMetered, true)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	customerIDStr := strconv.FormatInt(customerID, 10)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString("Customer"),
		customerIDStr,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerBytes}, nil).Once()

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantCustomerLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledOldLicense}, nil).Once()
	s.mockDB.On(
		"DeleteItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantCustomerLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"DeleteItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicenseKey.PartitionKey),
		wantLicenseeLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
}

func (s *membershipUpdateTestSuite) TestRemovingTheLastOrgMembershipExpiresLicenseForMetered() {
	oldOrgIDs := []uint64{100}

	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())
	msg.GroupId = 100

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, oldOrgIDs),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledOldLicense, err := json.Marshal(oldLicense)
	s.Require().NoError(err)

	customer := models.NewCustomer(uint64(customerID), models.LicensingModelMetered, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	customerIDStr := strconv.FormatInt(customerID, 10)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString("Customer"),
		customerIDStr,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerBytes}, nil).Once()

	// Define the expected data
	expectedData := map[string]interface{}{
		"LicenseStatus": "deactivated",
		"ExpiresAt":     float64(models.EndOfMonth()),
	}

	// Define a matcher function to check specific key-value pairs
	matcher := func(input []byte) bool {
		var actualMap map[string]interface{}
		err := json.Unmarshal(input, &actualMap)
		if err != nil {
			return false
		}
		// Check specific key-value pairs
		for key, value := range expectedData {
			if actualMap[key] != value {
				return false
			}
		}

		return true
	}

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		mock.MatchedBy(matcher),
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicenseKey.PartitionKey),
		mock.MatchedBy(matcher),
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantCustomerLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledOldLicense}, nil).Once()

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *membershipUpdateTestSuite) TestRemovingTheLastRepositoryCollaboratorDeletesLicense() {
	oldRepoIDs := []uint64{100}

	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_REPOSITORY.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())
	msg.GroupId = 100

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeRepo, models.EnablementReasonRepositoryCollaborator, oldRepoIDs),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledOldLicense, err := json.Marshal(oldLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantCustomerLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledOldLicense}, nil).Once()

	customer := models.NewCustomer(uint64(customerID), models.LicensingModelVolume, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	customerIDStr := strconv.FormatInt(customerID, 10)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString("Customer"),
		customerIDStr,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerBytes}, nil).Once()

	s.mockDB.On(
		"DeleteItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantCustomerLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"DeleteItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicenseKey.PartitionKey),
		wantLicenseeLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
}

func (s *membershipUpdateTestSuite) TestRemovingTheLastRepositoryCollaboratorExpiresLicense() {
	oldRepoIDs := []uint64{100}

	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_REPOSITORY.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())
	msg.GroupId = 100

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeRepo, models.EnablementReasonRepositoryCollaborator, oldRepoIDs),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledOldLicense, err := json.Marshal(oldLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		wantCustomerLicenseKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledOldLicense}, nil).Once()

	customer := models.NewCustomer(uint64(customerID), models.LicensingModelMetered, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	customerIDStr := strconv.FormatInt(customerID, 10)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString("Customer"),
		customerIDStr,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerBytes}, nil).Once()

	// Mock the now time var to freeze time to currentTime
	currentTime := time.Now().UTC()
	models.Now = func() time.Time {
		return currentTime
	}
	year, month, _ := currentTime.Date()
	nextMonth := time.Date(year, month+1, 1, 0, 0, 0, 0, currentTime.Location())
	expectedRemainingSeconds := int64(nextMonth.Sub(currentTime).Seconds())

	// Define the expected data
	expectedData := map[string]interface{}{
		"LicenseStatus": "deactivated",
		"ExpiresAt":     float64(models.EndOfMonth()),
	}

	// Define a matcher function to check specific key-value pairs
	matcher := func(input []byte) bool {
		var actualMap map[string]interface{}
		err := json.Unmarshal(input, &actualMap)
		if err != nil {
			return false
		}
		// Check specific key-value pairs
		for key, value := range expectedData {
			if actualMap[key] != value {
				return false
			}
		}

		// Check the TTL is present
		if actualMap["ttl"] == nil {
			return false
		}

		if actualMap["ttl"].(float64) != float64(expectedRemainingSeconds) {
			return false
		}

		return true
	}

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicenseKey.PartitionKey),
		mock.MatchedBy(matcher),
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicenseKey.PartitionKey),
		mock.MatchedBy(matcher),
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *membershipUpdateTestSuite) TestRemovingAnOrgNotAlreadyInTheLicense() {
	// Removing an org membership that doesn't already exist in the license shouldn't be encountered,
	// but in the case it happens it will be a noop.
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, []uint64{100, 200, 300}),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledOldLicense, err := json.Marshal(oldLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantKey.PartitionKey),
		wantKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledOldLicense}, nil).Once()

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *membershipUpdateTestSuite) TestAddingAnOrgAlreadyInTheLicense() {
	// Adding an org membership that already exists in the license shouldn't be encountered,
	// but in the case it happens it will be a noop.
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_ADD.Enum())

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, []uint64{msg.GroupId}),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledOldLicense, err := json.Marshal(oldLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantKey.PartitionKey),
		wantKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledOldLicense}, nil).Once()

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *membershipUpdateTestSuite) TestRemovingARepoCollaboratorNotAlreadyInTheLicense() {
	// Removing a repo collaborator that doesn't already exist in the license shouldn't be encountered,
	// but in the case it happens it will be a noop.
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_REPOSITORY.Enum(), *githubv1.MembershipUpdate_REMOVE.Enum())

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeRepo, models.EnablementReasonRepositoryCollaborator, []uint64{100, 200, 300}),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledOldLicense, err := json.Marshal(oldLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantKey.PartitionKey),
		wantKey.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledOldLicense}, nil).Once()

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func (s *membershipUpdateTestSuite) TestAddingAnOrgReactivatesDeactivatedLicense() {
	msg := stubs.NewMembershipUpdateHydroMsg(*githubv1.MembershipUpdate_ORGANIZATION.Enum(), *githubv1.MembershipUpdate_ADD.Enum())

	customerID := msg.CustomerId
	userID := msg.User.Id
	licenseeID := strconv.FormatUint(uint64(userID), 10)

	wantCustomerLicenseKey := models.NewCustomerLicenseKey(uint64(customerID), models.ProductSDLC, models.LicenseeTypeUser, licenseeID)
	wantLicenseeLicenseKey := models.NewLicenseeLicenseKey(licenseeID, models.LicenseeTypeUser, models.ProductSDLC, uint64(customerID))

	oldLicense := models.NewCustomerLicense(
		uint64(customerID),
		models.ProductSDLC,
		models.LicenseStatusDeactivated,
		models.NewLicensee(models.LicenseeTypeUser, licenseeID),
		[]*models.CustomerLicenseEnablement{},
		int64(1000),
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
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, []uint64{msg.GroupId}),
		},
		models.MaxExpiresAt,
		nil,
	)
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

	_, _, herr := s.handler.HandleMembershipUpdate(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
	s.mockDB.AssertExpectations(s.T())
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestMembershipUpdateHandlerSuite(t *testing.T) {
	suite.Run(t, new(membershipUpdateTestSuite))
}
