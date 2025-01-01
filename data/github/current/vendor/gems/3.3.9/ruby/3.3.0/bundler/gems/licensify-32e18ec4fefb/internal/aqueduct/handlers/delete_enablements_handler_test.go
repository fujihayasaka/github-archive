package handlers_test

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"testing"
	"time"

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
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type deleteEnablementsHandlerTestSuite struct {
	suite.Suite
	mockDB  *mocks.MockDBReadWriter
	handler *handlers.DeleteEnablementsHandler
}

func (s *deleteEnablementsHandlerTestSuite) SetupTest() {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	mockDB := &mocks.MockDBReadWriter{}
	customerLicenseEngine := engines.NewCustomerLicenseEngine(statter, tracer, mockDB)
	licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(statter, tracer, mockDB)
	customerEngine := engines.NewCustomerEngine(statter, tracer, mockDB)
	s.mockDB = mockDB
	s.handler = handlers.NewDeleteEnablementsHandler(statter, tracer, customerLicenseEngine, licenseeLicenseEngine, customerEngine)
}

func (s *deleteEnablementsHandlerTestSuite) TestHandlerErrorsFromInvalidJob() {
	tests := []struct {
		name string
		job  *models.DeleteEnablementsJob
	}{
		{
			name: "missing all job fields",
			job:  &models.DeleteEnablementsJob{},
		},
		{
			name: "missing enablement reason",
			job:  &models.DeleteEnablementsJob{EnablementID: 1},
		},
	}

	for _, tt := range tests {
		s.Run(tt.name, func() {
			logger := log.NewNullLogger()
			payload, err := json.Marshal(tt.job)
			s.Require().NoError(err)

			job := &aqueduct.Job{Payload: payload}
			rr := &aqueduct.ReceiveResult{Job: *job}
			s.Require().Error(s.handler.ProcessMessage(context.Background(), logger, *rr))

			s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything)
			s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything)
			s.mockDB.AssertNotCalled(s.T(), "NewQueryItemsPager", mock.Anything, mock.Anything, mock.Anything)
		})
	}
}

func (s *deleteEnablementsHandlerTestSuite) TestHandlerSkipsMissingIDs() {
	tests := []struct {
		name string
		job  *models.DeleteEnablementsJob
	}{
		{
			name: "missing enablement ID",
			job:  &models.DeleteEnablementsJob{EnablementReason: models.EnablementReasonOrgMembership},
		},
		{
			name: "missing customer ID",
			job:  &models.DeleteEnablementsJob{EnablementID: 1, EnablementReason: models.EnablementReasonOrgMembership},
		},
	}

	for _, tt := range tests {
		s.Run(tt.name, func() {
			logger := log.NewNullLogger()
			payload, err := json.Marshal(tt.job)
			s.Require().NoError(err)

			job := &aqueduct.Job{Payload: payload}
			rr := &aqueduct.ReceiveResult{Job: *job}
			s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))

			s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything)
			s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything)
			s.mockDB.AssertNotCalled(s.T(), "NewQueryItemsPager", mock.Anything, mock.Anything, mock.Anything)
		})
	}
}

func (s *deleteEnablementsHandlerTestSuite) TestHandlerDoesNothingIfNoLicensesFound() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	orgID := stubs.NewRandomID()

	payload, err := json.Marshal(&models.DeleteEnablementsJob{CustomerID: customerID, EnablementID: orgID, EnablementReason: models.EnablementReasonOrgMembership})
	s.Require().NoError(err)

	itemsReturned := make([][]byte, 0)

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
		"SELECT VALUE c FROM c JOIN e IN c.Enablements WHERE e.Reason = @reason AND ARRAY_CONTAINS(e.EnablementIDs, @enablementID)",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		&azcosmos.QueryOptions{
			QueryParameters: []azcosmos.QueryParameter{
				{Name: "@enablementID", Value: orgID},
				{Name: "@reason", Value: models.EnablementReasonOrgMembership.String()},
			},
		},
	).Return(pager).Once()

	customer := models.NewCustomer(customerID, 1, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customer.PartitionKey),
		customer.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerBytes}, nil).Once()

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job}
	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))

	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything)
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything)
}

func (s *deleteEnablementsHandlerTestSuite) TestHandlerDeletesLicenseWhenLastOrgMembershipIsRemoved() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	orgID := stubs.NewRandomID()

	payload, err := json.Marshal(&models.DeleteEnablementsJob{CustomerID: customerID, EnablementID: orgID, EnablementReason: models.EnablementReasonOrgMembership})
	s.Require().NoError(err)

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, stubs.NewRandomID(), orgID)
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	_, err = json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	customer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	itemsReturned := make([][]byte, 0)
	itemsReturned = append(itemsReturned, customerLicenseBytes)

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
		"SELECT VALUE c FROM c JOIN e IN c.Enablements WHERE e.Reason = @reason AND ARRAY_CONTAINS(e.EnablementIDs, @enablementID)",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		&azcosmos.QueryOptions{
			QueryParameters: []azcosmos.QueryParameter{
				{Name: "@enablementID", Value: orgID},
				{Name: "@reason", Value: models.EnablementReasonOrgMembership.String()},
			},
		},
	).Return(pager).Once()

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

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job}
	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))

	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything)
}

func (s *deleteEnablementsHandlerTestSuite) TestHandlerDeletesLicenseWhenLastOrgMembershipIsRemovedForTrial() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	orgID := stubs.NewRandomID()

	payload, err := json.Marshal(&models.DeleteEnablementsJob{CustomerID: customerID, EnablementID: orgID, EnablementReason: models.EnablementReasonOrgMembership})
	s.Require().NoError(err)

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, stubs.NewRandomID(), orgID)
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	_, err = json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	customer := models.NewCustomer(customerID, models.LicensingModelMetered, true)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	itemsReturned := make([][]byte, 0)
	itemsReturned = append(itemsReturned, customerLicenseBytes)

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
		"SELECT VALUE c FROM c JOIN e IN c.Enablements WHERE e.Reason = @reason AND ARRAY_CONTAINS(e.EnablementIDs, @enablementID)",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		&azcosmos.QueryOptions{
			QueryParameters: []azcosmos.QueryParameter{
				{Name: "@enablementID", Value: orgID},
				{Name: "@reason", Value: models.EnablementReasonOrgMembership.String()},
			},
		},
	).Return(pager).Once()

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

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job}
	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))

	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything)
}

// test that the handler upserts to update the metered customer
func (s *deleteEnablementsHandlerTestSuite) TestHandlerExpiresLicenseWhenLastOrgMembershipIsRemoved() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	orgID := stubs.NewRandomID()

	payload, err := json.Marshal(&models.DeleteEnablementsJob{CustomerID: customerID, EnablementID: orgID, EnablementReason: models.EnablementReasonOrgMembership})
	s.Require().NoError(err)

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, stubs.NewRandomID(), orgID)
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	_, err = json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	customer := models.NewCustomer(customerID, models.LicensingModelMetered, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	itemsReturned := make([][]byte, 0)
	itemsReturned = append(itemsReturned, customerLicenseBytes)

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
		"SELECT VALUE c FROM c JOIN e IN c.Enablements WHERE e.Reason = @reason AND ARRAY_CONTAINS(e.EnablementIDs, @enablementID)",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		&azcosmos.QueryOptions{
			QueryParameters: []azcosmos.QueryParameter{
				{Name: "@enablementID", Value: orgID},
				{Name: "@reason", Value: models.EnablementReasonOrgMembership.String()},
			},
		},
	).Return(pager).Once()

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

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job}
	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))

	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything)
}

func (s *deleteEnablementsHandlerTestSuite) TestHandlerReactivatesDeactivatedLicensesWhenUserStillHasEnablements() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	orgID1 := stubs.NewRandomID()
	orgID2 := stubs.NewRandomID()

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, stubs.NewRandomID(), orgID1, orgID2)
	customerLicense.LicenseStatus = models.LicenseStatusDeactivated
	customerLicense.ExpiresAt = models.EndOfMonth()
	ttl := int64(100)
	customerLicense.TTL = &ttl
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	_, err = json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	customer := models.NewCustomer(customerID, models.LicensingModelMetered, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)

	itemsReturned := make([][]byte, 0)
	itemsReturned = append(itemsReturned, customerLicenseBytes)

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
		"SELECT VALUE c FROM c JOIN e IN c.Enablements WHERE e.Reason = @reason AND ARRAY_CONTAINS(e.EnablementIDs, @enablementID)",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		&azcosmos.QueryOptions{
			QueryParameters: []azcosmos.QueryParameter{
				{Name: "@enablementID", Value: orgID1},
				{Name: "@reason", Value: models.EnablementReasonOrgMembership.String()},
			},
		},
	).Return(pager).Once()

	customerIDStr := strconv.FormatUint(customerLicense.CustomerID, 10)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString("Customer"),
		customerIDStr,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerBytes}, nil).Once()

	licenseeID, _ := strconv.ParseUint(customerLicense.Licensee.ID, 10, 64)

	wantCustomerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, licenseeID, orgID2)
	wantCustomerLicense.LicenseStatus = models.LicenseStatusActive
	wantCustomerLicense.ExpiresAt = models.MaxExpiresAt
	wantCustomerLicense.TTL = nil

	wantCustomerLicenseBytes, err := json.Marshal(wantCustomerLicense)
	s.Require().NoError(err)

	wantLicenseeLicense := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense)
	wantLicenseeLicenseBytes, err := json.Marshal(wantLicenseeLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicense.PartitionKey),
		wantCustomerLicenseBytes,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicenseBytes,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	payload, err := json.Marshal(&models.DeleteEnablementsJob{CustomerID: customerID, EnablementID: orgID1, EnablementReason: models.EnablementReasonOrgMembership})
	s.Require().NoError(err)

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job}
	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))

	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything)
}

func (s *deleteEnablementsHandlerTestSuite) TestHandlerRemovesOrgMemberships() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	orgID := stubs.NewRandomID()

	payload, err := json.Marshal(&models.DeleteEnablementsJob{CustomerID: customerID, EnablementID: orgID, EnablementReason: models.EnablementReasonOrgMembership})
	s.Require().NoError(err)

	customer := models.NewCustomer(customerID, 1, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customer.PartitionKey),
		customer.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerBytes}, nil).Once()

	extraOrgID := stubs.NewRandomID()
	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, stubs.NewRandomID(), orgID, extraOrgID)
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	_, err = json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	itemsReturned := make([][]byte, 0)
	itemsReturned = append(itemsReturned, customerLicenseBytes)

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
		"SELECT VALUE c FROM c JOIN e IN c.Enablements WHERE e.Reason = @reason AND ARRAY_CONTAINS(e.EnablementIDs, @enablementID)",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		&azcosmos.QueryOptions{
			QueryParameters: []azcosmos.QueryParameter{
				{Name: "@enablementID", Value: orgID},
				{Name: "@reason", Value: models.EnablementReasonOrgMembership.String()},
			},
		},
	).Return(pager).Once()

	licenseeID, _ := strconv.ParseUint(customerLicense.Licensee.ID, 10, 64)

	wantCustomerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, licenseeID, extraOrgID)
	wantCustomerLicenseBytes, err := json.Marshal(wantCustomerLicense)
	s.Require().NoError(err)

	wantLicenseeLicense := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense)
	wantLicenseeLicenseBytes, err := json.Marshal(wantLicenseeLicense)
	s.Require().NoError(err)

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		wantCustomerLicenseBytes,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(licenseeLicense.PartitionKey),
		wantLicenseeLicenseBytes,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job}
	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))

	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything)
}

func (s *deleteEnablementsHandlerTestSuite) TestHandlerRetriesOnPreconditionFailedError() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	orgID := stubs.NewRandomID()

	eTag := azcore.ETag("etag")

	payload, err := json.Marshal(&models.DeleteEnablementsJob{CustomerID: customerID, EnablementID: orgID, EnablementReason: models.EnablementReasonOrgMembership})
	s.Require().NoError(err)

	customer := models.NewCustomer(customerID, 1, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customer.PartitionKey),
		customer.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerBytes}, nil).Once()

	extraOrgID := stubs.NewRandomID()
	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, stubs.NewRandomID(), orgID, extraOrgID)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	_, err = json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	itemsReturned := make([][]byte, 0)
	itemsReturned = append(itemsReturned, customerLicenseBytes)

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
		"SELECT VALUE c FROM c JOIN e IN c.Enablements WHERE e.Reason = @reason AND ARRAY_CONTAINS(e.EnablementIDs, @enablementID)",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		&azcosmos.QueryOptions{
			QueryParameters: []azcosmos.QueryParameter{
				{Name: "@enablementID", Value: orgID},
				{Name: "@reason", Value: models.EnablementReasonOrgMembership.String()},
			},
		},
	).Return(pager).Once()

	licenseeID, _ := strconv.ParseUint(customerLicense.Licensee.ID, 10, 64)

	wantCustomerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, licenseeID, extraOrgID)
	wantCustomerLicense.ETag = &eTag
	wantCustomerLicenseBytes, err := json.Marshal(wantCustomerLicense)
	s.Require().NoError(err)

	wantLicenseeLicense := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense)
	wantLicenseeLicenseBytes, err := json.Marshal(wantLicenseeLicense)
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

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(licenseeLicense.PartitionKey),
		wantLicenseeLicenseBytes,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job}
	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
}

func (s *deleteEnablementsHandlerTestSuite) TestHandlerReturnsErrorWhenRetriesExhausted() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	orgID := stubs.NewRandomID()
	retries := 10

	eTag := azcore.ETag("etag")

	payload, err := json.Marshal(&models.DeleteEnablementsJob{CustomerID: customerID, EnablementID: orgID, EnablementReason: models.EnablementReasonOrgMembership})
	s.Require().NoError(err)

	customer := models.NewCustomer(customerID, 1, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customer.PartitionKey),
		customer.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerBytes}, nil).Once()

	extraOrgID := stubs.NewRandomID()
	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, stubs.NewRandomID(), orgID, extraOrgID)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	_, err = json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	itemsReturned := make([][]byte, 0)
	itemsReturned = append(itemsReturned, customerLicenseBytes)

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
		"SELECT VALUE c FROM c JOIN e IN c.Enablements WHERE e.Reason = @reason AND ARRAY_CONTAINS(e.EnablementIDs, @enablementID)",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		&azcosmos.QueryOptions{
			QueryParameters: []azcosmos.QueryParameter{
				{Name: "@enablementID", Value: orgID},
				{Name: "@reason", Value: models.EnablementReasonOrgMembership.String()},
			},
		},
	).Return(pager).Once()

	licenseeID, _ := strconv.ParseUint(customerLicense.Licensee.ID, 10, 64)

	wantCustomerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, licenseeID, extraOrgID)
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
	).Return(nil, preconditionFailedErr).Times(retries)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		customerLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerLicenseBytes}, nil).Times(retries - 1)

	job := &aqueduct.Job{Payload: payload}
	rr := &aqueduct.ReceiveResult{Job: *job}
	s.ErrorIs(s.handler.ProcessMessage(context.Background(), logger, *rr), preconditionFailedErr)
}

func TestDeleteEnablementsHandlerSuite(t *testing.T) {
	suite.Run(t, new(deleteEnablementsHandlerTestSuite))
}
