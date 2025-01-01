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
	customersV1 "github.com/github/licensify/lib/monolith-twirp/customers/v1"
	"github.com/github/licensify/testing/helpers"
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type syncOrgMembershipsHandlerTestSuite struct {
	suite.Suite
	mockDB          *mocks.MockDBReadWriter
	mockMonolithAPI *mocks.MockMonolithAPI
	handler         *handlers.SyncOrgMembershipsHandler
}

func (s *syncOrgMembershipsHandlerTestSuite) SetupTest() {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	s.mockDB = &mocks.MockDBReadWriter{}
	s.mockMonolithAPI = &mocks.MockMonolithAPI{}
	customerEngine := engines.NewCustomerEngine(statter, tracer, s.mockDB)
	customerLicenseEngine := engines.NewCustomerLicenseEngine(statter, tracer, s.mockDB)
	licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(statter, tracer, s.mockDB)
	s.handler = handlers.NewSyncOrgMembershipsHandler(customerEngine, customerLicenseEngine, licenseeLicenseEngine, s.mockMonolithAPI, statter, tracer)
}

func (s *syncOrgMembershipsHandlerTestSuite) TestHandlerRetriesOnPreconditionFailedError() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()

	eTag := azcore.ETag("etag")

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: userID, OrganizationMemberships: []uint64{10}},
		},
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Twice()

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

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 100)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	customerLicensesReturned := make([][]byte, 0)
	customerLicensesReturned = append(customerLicensesReturned, customerLicenseBytes)
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: customerLicensesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	wantCustomerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 10)
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

	jobPayload, err := json.Marshal(models.NewCustomerSyncJob(customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
}

func (s *syncOrgMembershipsHandlerTestSuite) TestHandlerReturnsErrorWhenRetriesExhausted() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()
	retries := 10

	eTag := azcore.ETag("etag")

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: userID, OrganizationMemberships: []uint64{10}},
		},
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Twice()

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

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 100)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	customerLicensesReturned := make([][]byte, 0)
	customerLicensesReturned = append(customerLicensesReturned, customerLicenseBytes)
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: customerLicensesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	wantCustomerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 10)
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
	).Return(nil, wantErr).Times(retries)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customerLicense.PartitionKey),
		customerLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerLicenseBytes}, nil).Times(retries - 1)

	jobPayload, err := json.Marshal(models.NewCustomerSyncJob(customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.ErrorIs(s.handler.ProcessMessage(context.Background(), logger, *rr), wantErr)
}

func (s *syncOrgMembershipsHandlerTestSuite) TestHandlerDoesNotUpsertLicenseeLicenseWhenRecordExists() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()

	eTag := azcore.ETag("etag")

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: userID, OrganizationMemberships: []uint64{10}},
		},
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Twice()

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

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 100)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	customerLicensesReturned := make([][]byte, 0)
	customerLicensesReturned = append(customerLicensesReturned, customerLicenseBytes)
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: customerLicensesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	wantCustomerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 10)
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

	jobPayload, err := json.Marshal(models.NewCustomerSyncJob(customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))

	s.mockDB.AssertNotCalled(s.T(),
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicenseBytes,
		mock.Anything,
	)
}

func (s *syncOrgMembershipsHandlerTestSuite) TestHandlerDeletesLicensesWhenLastOrgMembershipIsRemoved() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()

	eTag := azcore.ETag("etag")

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: userID, OrganizationMemberships: []uint64{}},
		},
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Twice()

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 100)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	customerLicensesReturned := make([][]byte, 0)
	customerLicensesReturned = append(customerLicensesReturned, customerLicenseBytes)
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: customerLicensesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	customer := models.NewCustomer(customerID, models.LicensingModelVolume, false)
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

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)

	s.mockDB.On(
		"DeleteItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(licenseeLicense.PartitionKey),
		licenseeLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	jobPayload, err := json.Marshal(models.NewCustomerSyncJob(customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything)
}

func (s *syncOrgMembershipsHandlerTestSuite) TestHandlerDeletesLicensesWhenLastOrgMembershipIsRemovedForTrial() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()

	eTag := azcore.ETag("etag")

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: userID, OrganizationMemberships: []uint64{}},
		},
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Twice()

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 100)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	customerLicensesReturned := make([][]byte, 0)
	customerLicensesReturned = append(customerLicensesReturned, customerLicenseBytes)
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: customerLicensesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	customer := models.NewCustomer(customerID, models.LicensingModelMetered, true)
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

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)

	s.mockDB.On(
		"DeleteItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(licenseeLicense.PartitionKey),
		licenseeLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	jobPayload, err := json.Marshal(models.NewCustomerSyncJob(customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
	s.mockDB.AssertNotCalled(s.T(), "UpsertItem", mock.Anything, mock.Anything, mock.Anything)
}

func (s *syncOrgMembershipsHandlerTestSuite) TestHandlerExpiresLicensesWhenLastOrgMembershipIsRemoved() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()

	eTag := azcore.ETag("etag")

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: userID, OrganizationMemberships: []uint64{}},
		},
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Twice()

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 100)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	customerLicensesReturned := make([][]byte, 0)
	customerLicensesReturned = append(customerLicensesReturned, customerLicenseBytes)
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: customerLicensesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	customer := models.NewCustomer(customerID, models.LicensingModelMetered, false)
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

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)

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

	jobPayload, err := json.Marshal(models.NewCustomerSyncJob(customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything)
}

func (s *syncOrgMembershipsHandlerTestSuite) TestHandlerReactivatesDeactivatedLicensesWhenUserIsReadded() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()

	eTag := azcore.ETag("etag")

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: userID, OrganizationMemberships: []uint64{200}},
		},
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Once()

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID)
	customerLicense.LicenseStatus = models.LicenseStatusDeactivated
	customerLicense.ExpiresAt = models.EndOfMonth()
	ttl := int64(100)
	customerLicense.TTL = &ttl
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	customerLicensesReturned := make([][]byte, 0)
	customerLicensesReturned = append(customerLicensesReturned, customerLicenseBytes)
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: customerLicensesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	customer := models.NewCustomer(customerID, models.LicensingModelMetered, false)
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

	wantCustomerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 200)
	wantCustomerLicense.ETag = &eTag
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

	jobPayload, err := json.Marshal(models.NewCustomerSyncJob(customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything)
}

func (s *syncOrgMembershipsHandlerTestSuite) TestHandlerGetsAllUsersWhenThereArePages() {
	helpers.LockUUIDGeneration()
	defer helpers.ResetUUIDGeneration()

	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()

	request1 := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response1 := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: 1, OrganizationMemberships: []uint64{10}},
			{Id: 3, CollaboratingRepositories: []uint64{100}},
		},
		NextPageToken: "10",
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request1).Return(response1, nil).Once()

	customer := models.NewCustomer(customerID, 1, false)
	customerBytes, err := json.Marshal(customer)
	s.Require().NoError(err)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customer.PartitionKey),
		customer.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: customerBytes}, nil).Times(3)

	request2 := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
		PageToken:  "10",
	}
	response2 := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: 1, OrganizationMemberships: []uint64{11}},
			{Id: 2, OrganizationMemberships: []uint64{11}},
			{Id: 3, OrganizationMemberships: []uint64{11}, CollaboratingRepositories: []uint64{200}},
		},
		NextPageToken: "",
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request2).Return(response2, nil).Once()

	customerLicensesReturned := make([][]byte, 0)
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: customerLicensesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	wantCustomerLicense1 := models.NewCustomerLicenseForUserWithMemberships(customerID, 1, []uint64{10, 11}, nil)
	wantCustomerLicense1.AddETag()
	wantCustomerLicenseBytes1, err := json.Marshal(wantCustomerLicense1)
	s.Require().NoError(err)

	wantCustomerLicense2 := models.NewCustomerLicenseForUserWithMemberships(customerID, 2, []uint64{11}, nil)
	wantCustomerLicense2.AddETag()
	wantCustomerLicenseBytes2, err := json.Marshal(wantCustomerLicense2)
	s.Require().NoError(err)

	wantCustomerLicense3 := models.NewCustomerLicenseForUserWithMemberships(customerID, 3, []uint64{11}, []uint64{100, 200})
	wantCustomerLicense3.AddETag()
	wantCustomerLicenseBytes3, err := json.Marshal(wantCustomerLicense3)
	s.Require().NoError(err)

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicense1.PartitionKey),
		wantCustomerLicenseBytes1,
		mock.AnythingOfType("*azcosmos.ItemOptions"),
	).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicense2.PartitionKey),
		wantCustomerLicenseBytes2,
		mock.AnythingOfType("*azcosmos.ItemOptions"),
	).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantCustomerLicense3.PartitionKey),
		wantCustomerLicenseBytes3,
		mock.AnythingOfType("*azcosmos.ItemOptions"),
	).Return(azcosmos.ItemResponse{}, nil).Once()

	wantLicenseeLicense1 := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense1)
	wantLicenseeLicenseBytes1, err := json.Marshal(wantLicenseeLicense1)
	s.Require().NoError(err)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense1.PartitionKey),
		wantLicenseeLicense1.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: wantLicenseeLicenseBytes1}, nil).Once()

	wantLicenseeLicense2 := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense2)
	wantLicenseeLicenseBytes2, err := json.Marshal(wantLicenseeLicense2)
	s.Require().NoError(err)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense2.PartitionKey),
		wantLicenseeLicense2.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: wantLicenseeLicenseBytes2}, nil).Once()

	wantLicenseeLicense3 := models.NewLicenseeLicenseForCustomerLicense(wantCustomerLicense3)
	wantLicenseeLicenseBytes3, err := json.Marshal(wantLicenseeLicense3)
	s.Require().NoError(err)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense3.PartitionKey),
		wantLicenseeLicense3.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: wantLicenseeLicenseBytes3}, nil).Once()

	jobPayload, err := json.Marshal(models.NewCustomerSyncJob(customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
}

func (s *syncOrgMembershipsHandlerTestSuite) TestHandlerReturnsErrorWhenCustomerNotFound() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()

	eTag := azcore.ETag("etag")

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users:      []*customersV1.User{},
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Once()

	wantErr := runtime.NewResponseError(&http.Response{StatusCode: http.StatusNotFound})

	customer := models.NewCustomer(customerID, 1, false)
	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(customer.PartitionKey),
		customer.ID,
		mock.Anything,
	).Return(nil, wantErr).Once()

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 100)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	customerLicensesReturned := make([][]byte, 0)
	customerLicensesReturned = append(customerLicensesReturned, customerLicenseBytes)
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: customerLicensesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	jobPayload, err := json.Marshal(models.NewCustomerSyncJob(customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().ErrorIs(s.handler.ProcessMessage(context.Background(), logger, *rr), wantErr)
}

func (s *syncOrgMembershipsHandlerTestSuite) TestCustomerSyncUpdatesSuspendedAt() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	userID := stubs.NewRandomID()
	orgID := stubs.NewRandomID()
	suspendedAt := time.Now().UTC().Unix()
	eTag := azcore.ETag("etag")

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_CUSTOMER,
		EntityId:   customerID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: userID, OrganizationMemberships: []uint64{orgID}, SuspendedAt: timestamppb.New(time.Unix(suspendedAt, 0))},
		},
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Once()

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, orgID)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	licenseeLicenseBytes, err := json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	customerLicensesReturned := make([][]byte, 0)
	customerLicensesReturned = append(customerLicensesReturned, customerLicenseBytes)
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: customerLicensesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	customer := models.NewCustomer(customerID, models.LicensingModelMetered, false)
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

	wantCustomerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, orgID)
	wantCustomerLicense.LicenseStatus = models.LicenseStatusSuspended
	wantCustomerLicense.SuspendedAt = &suspendedAt
	wantCustomerLicense.ETag = &eTag
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
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: licenseeLicenseBytes}, nil).Once()

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicenseBytes,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	jobPayload, err := json.Marshal(models.NewCustomerSyncJob(customerID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything)
}

func (s *syncOrgMembershipsHandlerTestSuite) TestOrganizationSyncUpdatesSuspendedAt() {
	logger := log.NewNullLogger()
	customerID := stubs.NewRandomID()
	orgID := stubs.NewRandomID()
	userID := stubs.NewRandomID()
	suspendedAt := time.Now().UTC().Unix()
	eTag := azcore.ETag("etag")

	request := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType_ENTITY_TYPE_ORGANIZATION,
		EntityId:   orgID,
	}
	response := &customersV1.GetUsersResponse{
		CustomerId: customerID,
		Users: []*customersV1.User{
			{Id: userID, OrganizationMemberships: []uint64{orgID}, SuspendedAt: timestamppb.New(time.Unix(suspendedAt, 0))},
		},
	}
	s.mockMonolithAPI.On("GetUsers", mock.Anything, request).Return(response, nil).Once()

	customerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, orgID)
	customerLicense.ETag = &eTag
	customerLicenseBytes, err := json.Marshal(customerLicense)
	s.Require().NoError(err)

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	licenseeLicenseBytes, err := json.Marshal(licenseeLicense)
	s.Require().NoError(err)

	customerLicensesReturned := make([][]byte, 0)
	customerLicensesReturned = append(customerLicensesReturned, customerLicenseBytes)
	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: customerLicensesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	customer := models.NewCustomer(customerID, models.LicensingModelMetered, false)
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

	wantCustomerLicense := models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, orgID)
	wantCustomerLicense.LicenseStatus = models.LicenseStatusSuspended
	wantCustomerLicense.SuspendedAt = &suspendedAt
	wantCustomerLicense.ETag = &eTag
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
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicense.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: licenseeLicenseBytes}, nil).Once()

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(wantLicenseeLicense.PartitionKey),
		wantLicenseeLicenseBytes,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	jobPayload, err := json.Marshal(models.NewOrganizationSyncJob(orgID))
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().NoError(s.handler.ProcessMessage(context.Background(), logger, *rr))
	s.mockDB.AssertNotCalled(s.T(), "DeleteItem", mock.Anything, mock.Anything, mock.Anything)
}

func TestSyncOrgMembershipsHandlerTestSuite(t *testing.T) {
	suite.Run(t, new(syncOrgMembershipsHandlerTestSuite))
}
