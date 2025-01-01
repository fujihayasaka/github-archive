package handlers_test

import (
	"context"
	"encoding/json"
	"strconv"
	"testing"

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
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type backfillLicenseStatusHandlerSuite struct {
	suite.Suite
	mockDB  *mocks.MockDBReadWriter
	handler *handlers.BackfillLicenseStatusHandler
}

func (s *backfillLicenseStatusHandlerSuite) SetupTest() {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer
	s.mockDB = &mocks.MockDBReadWriter{}
	customerLicenseEngine := engines.NewCustomerLicenseEngine(statter, tracer, s.mockDB)
	licenseeLicenseeEngine := engines.NewLicenseeLicenseEngine(statter, tracer, s.mockDB)
	s.handler = handlers.NewBackfillLicenseStatusHandler(statter, tracer, s.mockDB, customerLicenseEngine, licenseeLicenseeEngine)
}

func (s *backfillLicenseStatusHandlerSuite) TestHandlerPatchesLicenseStatus() {
	logger := log.NewNullLogger()
	customerID := uint64(1)
	userID := uint64(2)
	licenseeID := strconv.FormatUint(userID, 10)
	ctx := context.Background()

	licenseeBytes, err := json.Marshal(userID)
	s.Require().NoError(err)

	licenseesReturned := make([][]byte, 0)
	licenseesReturned = append(licenseesReturned, licenseeBytes)

	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: licenseesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"SELECT DISTINCT VALUE c.Licensee.ID FROM c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		&azcosmos.QueryOptions{
			PageSizeHint:    -1,
			QueryParameters: []azcosmos.QueryParameter{},
		},
	).Return(pager).Once()

	wantOps := azcosmos.PatchOperations{}
	wantOps.AppendAdd("/LicenseStatus", models.LicenseStatusActive)
	wantOps.SetCondition("from c where not is_defined(c.LicenseStatus) or c.LicenseStatus = ''")
	s.mockDB.On(
		"PatchItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		models.NewCustomerLicenseID(models.LicenseeTypeUser, licenseeID),
		wantOps,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()
	s.mockDB.On(
		"PatchItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(models.NewLicenseeLicensePartitionKey(licenseeID, models.LicenseeTypeUser)),
		models.NewLicenseeLicenseID(models.ProductSDLC, customerID),
		wantOps,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	jobPayload, err := json.Marshal(&models.BackfillLicenseStatusJob{CustomerID: customerID})
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().NoError(s.handler.ProcessMessage(ctx, logger, *rr))
}

func (s *backfillLicenseStatusHandlerSuite) TestHandlerHandlesNoLicensesFound() {
	logger := log.NewNullLogger()
	customerID := uint64(1)
	ctx := context.Background()

	licenseesReturned := make([][]byte, 0)

	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{Items: licenseesReturned}, nil
		},
	})
	s.mockDB.On(
		"NewQueryItemsPager",
		"SELECT DISTINCT VALUE c.Licensee.ID FROM c",
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		&azcosmos.QueryOptions{
			PageSizeHint:    -1,
			QueryParameters: []azcosmos.QueryParameter{},
		},
	).Return(pager).Once()

	jobPayload, err := json.Marshal(&models.BackfillLicenseStatusJob{CustomerID: customerID})
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job, MaxDeliveryAttempts: 2}

	s.Require().NoError(s.handler.ProcessMessage(ctx, logger, *rr))

	s.mockDB.AssertNotCalled(s.T(), "PatchItem", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)
}

func TestBackfillLicenseStatusHandlerSuite(t *testing.T) {
	suite.Run(t, new(backfillLicenseStatusHandlerSuite))
}
