package eventhandlers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"strconv"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/internal/monolith"
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type userDestroyTestSuite struct {
	suite.Suite
	cfg                *config.Config
	mockDB             *mocks.MockDBReadWriter
	mockAqueductClient *mocks.MockAqueductClient
	handler            *eventhandlers.EventHandler
	logger             log.Logger
}

func (s *userDestroyTestSuite) SetupTest() {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	mockDB := &mocks.MockDBReadWriter{}

	s.cfg = cfg
	s.mockAqueductClient = &mocks.MockAqueductClient{}
	s.mockDB = mockDB
	s.logger = log.NewNullLogger()
	jobby := &jobs.Jobby{Cfg: cfg, AqueductClient: s.mockAqueductClient}

	handler, _ := eventhandlers.NewEventHandler(mockDB, jobby, &monolith.Client{}, statter, tracer)
	s.handler = handler
}

func (s *userDestroyTestSuite) TestHandlerDoesNotQueueDeleteJobWhenMissingData() {
	tests := []struct {
		name           string
		userType       entities.User_Type
		customerID     uint64
		organizationID uint64
	}{
		{
			name:           "missing organization customer ID",
			userType:       entities.User_ORGANIZATION,
			customerID:     0,
			organizationID: 1234,
		},
		{
			name:           "missing organization ID",
			userType:       entities.User_ORGANIZATION,
			customerID:     1234,
			organizationID: 0,
		},
		{
			name:           "user type is unknown",
			userType:       entities.User_UNKNOWN,
			customerID:     1,
			organizationID: 2,
		},
	}
	for _, tt := range tests {
		s.Run(tt.name, func() {
			msg := stubs.NewOrganizationDestroyHydroMsg()
			msg.User.Type = tt.userType
			msg.OrganizationCustomerId = int64(tt.customerID)
			msg.User.Id = uint32(tt.organizationID)

			_, err := s.handler.HandleUserDestroy(context.Background(), s.logger, msg)
			s.Require().NoError(err.Err)

			s.mockAqueductClient.AssertNotCalled(s.T(), "Send", mock.Anything, mock.Anything, mock.Anything)
		})
	}
}

func (s *userDestroyTestSuite) TestHandlerDoesNotDeleteUserWhenMissingData() {
	tests := []struct {
		name     string
		userType entities.User_Type
		userID   uint32
	}{
		{
			name:     "missing user ID",
			userType: entities.User_USER,
			userID:   0,
		},
	}
	for _, tt := range tests {
		s.Run(tt.name, func() {
			msg := stubs.NewUserDestroyHydroMsg()
			msg.User.Type = tt.userType
			msg.User.Id = tt.userID

			s.mockDB.On(
				"DeleteItem",
				mock.Anything,
				mock.Anything,
				mock.Anything,
				mock.Anything,
			).Return(azcosmos.ItemResponse{}, nil).Times(0)

			_, err := s.handler.HandleUserDestroy(context.Background(), s.logger, msg)
			s.Require().NoError(err.Err)
		})
	}
}

func (s *userDestroyTestSuite) TestHandlerQueuesDeleteJobForOrgs() {
	jobID := "jobID-1234"

	msg := stubs.NewOrganizationDestroyHydroMsg()

	wantPayload, err := json.Marshal(&models.DeleteEnablementsJob{
		CustomerID:       uint64(msg.GetOrganizationCustomerId()),
		EnablementReason: models.EnablementReasonOrgMembership,
		EnablementID:     uint64(msg.GetUser().GetId()),
	})
	s.Require().NoError(err)

	s.mockAqueductClient.On(
		"Send",
		mock.Anything,
		mock.MatchedBy(func(j aqueduct.Job) bool {
			return j.App == s.cfg.AqueductApp &&
				j.Queue == queues.QueueDeleteEnablements &&
				j.Headers[jobs.JobNameHeader] == jobs.JobNameDeleteEnablements &&
				bytes.Equal(j.Payload, wantPayload)
		}),
		mock.AnythingOfType("[]aqueduct.SendOption"),
	).Return(jobID, nil).Once()

	_, herr := s.handler.HandleUserDestroy(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
}

func (s *userDestroyTestSuite) TestHandlerDeletesUserDocuments() {
	msg := stubs.NewUserDestroyHydroMsg()

	userID := uint64(msg.GetUser().GetId())
	licenseeID := strconv.FormatUint(userID, 10)

	licensee := models.NewLicensee(models.LicenseeTypeUser, licenseeID)
	licenseeLicense := models.NewLicenseeLicense(
		licensee,
		models.ProductSDLC,
		models.LicenseStatusActive,
		uint64(1),
		0,
		nil,
	)
	licenseeLicenseBytes, err := json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	itemsReturned := make([][]byte, 0)
	itemsReturned = append(itemsReturned, licenseeLicenseBytes)

	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: itemsReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewLicenseeLicensePartitionKey(licenseeID, models.LicenseeTypeUser)),
		mock.Anything,
	).Return(pager).Once()

	customerLicense := licenseeLicense.BuildCustomerLicense()

	customer := models.NewCustomer(customerLicense.CustomerID, models.LicensingModelVolume, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	customerIDStr := strconv.FormatUint(customerLicense.CustomerID, 10)
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
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		customerLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"DeleteItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(licenseeLicense.PartitionKey),
		licenseeLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	_, herr := s.handler.HandleUserDestroy(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
}

func (s *userDestroyTestSuite) TestHandlerDeletesUserDocumentsForTrial() {
	msg := stubs.NewUserDestroyHydroMsg()

	userID := uint64(msg.GetUser().GetId())
	licenseeID := strconv.FormatUint(userID, 10)

	licensee := models.NewLicensee(models.LicenseeTypeUser, licenseeID)
	licenseeLicense := models.NewLicenseeLicense(
		licensee,
		models.ProductSDLC,
		models.LicenseStatusActive,
		uint64(1),
		0,
		nil,
	)
	licenseeLicenseBytes, err := json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	itemsReturned := make([][]byte, 0)
	itemsReturned = append(itemsReturned, licenseeLicenseBytes)

	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: itemsReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewLicenseeLicensePartitionKey(licenseeID, models.LicenseeTypeUser)),
		mock.Anything,
	).Return(pager).Once()

	customerLicense := licenseeLicense.BuildCustomerLicense()
	customer := models.NewCustomer(customerLicense.CustomerID, models.LicensingModelMetered, true)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	customerIDStr := strconv.FormatUint(customerLicense.CustomerID, 10)
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
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		customerLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"DeleteItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(licenseeLicense.PartitionKey),
		licenseeLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	_, herr := s.handler.HandleUserDestroy(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
}

func (s *userDestroyTestSuite) TestHandlerExpiresUserDocuments() {
	msg := stubs.NewUserDestroyHydroMsg()

	userID := uint64(msg.GetUser().GetId())
	licenseeID := strconv.FormatUint(userID, 10)

	licensee := models.NewLicensee(models.LicenseeTypeUser, licenseeID)
	licenseeLicense := models.NewLicenseeLicense(
		licensee,
		models.ProductSDLC,
		models.LicenseStatusActive,
		uint64(1),
		0,
		nil,
	)
	licenseeLicenseBytes, err := json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	itemsReturned := make([][]byte, 0)
	itemsReturned = append(itemsReturned, licenseeLicenseBytes)

	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: itemsReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewLicenseeLicensePartitionKey(licenseeID, models.LicenseeTypeUser)),
		mock.Anything,
	).Return(pager).Once()

	customerLicense := licenseeLicense.BuildCustomerLicense()
	customer := models.NewCustomer(customerLicense.CustomerID, models.LicensingModelMetered, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	customerIDStr := strconv.FormatUint(customerLicense.CustomerID, 10)
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
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		mock.MatchedBy(matcher),
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(licenseeLicense.PartitionKey),
		mock.MatchedBy(matcher),
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	_, herr := s.handler.HandleUserDestroy(context.Background(), s.logger, msg)
	s.Require().NoError(herr.Err)
}

func TestUserDestroyTestSuite(t *testing.T) {
	suite.Run(t, new(userDestroyTestSuite))
}
