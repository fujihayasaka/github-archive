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
	"github.com/github/go-stats"
	statsmocks "github.com/github/go-stats/mocks"
	"github.com/github/licensify/internal/aqueduct/handlers"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type scheduleEmissionsHandlerTestSuite struct {
	suite.Suite
	mockAqueductClient *mocks.MockAqueductClient
	mockDB             *mocks.MockDBReadWriter
	mockStatter        *statsmocks.Client
	handler            *handlers.ScheduleEmissionsHandler
}

func (s *scheduleEmissionsHandlerTestSuite) SetupTest() {
	cfg, _ := config.Load()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	s.mockDB = &mocks.MockDBReadWriter{}
	s.mockAqueductClient = &mocks.MockAqueductClient{}
	s.mockStatter = &statsmocks.Client{}
	s.mockStatter.Mock.On("Counter", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Return(nil)
	s.mockStatter.Mock.On("Timing", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("time.Duration")).Return(nil)
	customerEngine := engines.NewCustomerEngine(s.mockStatter, tracer, s.mockDB)
	jobby := &jobs.Jobby{Cfg: cfg, AqueductClient: s.mockAqueductClient}
	s.handler = handlers.NewScheduleEmissionsHandler(cfg, customerEngine, jobby, s.mockStatter, tracer)
}

func (s *scheduleEmissionsHandlerTestSuite) setupCommonTest(usageTime int64) (*aqueduct.ReceiveResult, []models.Customer) {
	s.T().Helper()

	msg := &models.ScheduleEmissionsJob{UsageTime: usageTime}

	jobPayload, err := json.Marshal(msg)
	s.Require().NoError(err)

	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job}

	customerID1 := stubs.NewRandomID()
	customer1 := models.NewCustomer(customerID1, models.LicensingModelMetered, false)
	customerBytes1, err := json.Marshal(customer1)
	s.Require().NoError(err)

	customerID2 := stubs.NewRandomID()
	customer2 := models.NewCustomer(customerID2, models.LicensingModelMetered, false)
	customerBytes2, err := json.Marshal(customer2)
	s.Require().NoError(err)

	customersReturned := [][]byte{customerBytes1, customerBytes2}

	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{
				Items: customersReturned,
			}, nil
		},
	})

	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c where c.sdlcLicensingModel = @sdlcLicensingModel and c.sdlcTrial = @sdlcTrial",
		azcosmos.NewPartitionKeyString(models.CustomerPartitionKey),
		mock.MatchedBy(func(options *azcosmos.QueryOptions) bool {
			return len(options.QueryParameters) == 2 &&
				options.QueryParameters[0].Name == "@sdlcLicensingModel" &&
				options.QueryParameters[0].Value == "METERED" &&
				options.QueryParameters[1].Name == "@sdlcTrial" &&
				!options.QueryParameters[1].Value.(bool)
		}),
	).Return(pager).Once()

	return rr, []models.Customer{*customer1, *customer2}
}

func (s *scheduleEmissionsHandlerTestSuite) TestScheduleEmissionsHandler_UnmarshalError() {
	logger := log.NewNullLogger()
	job := &aqueduct.Job{Payload: []byte("invalid json")}
	rr := &aqueduct.ReceiveResult{Job: *job}

	err := s.handler.ProcessMessage(context.Background(), logger, *rr)
	s.Require().Error(err)
	s.Require().Contains(err.Error(), "failed to unmarshal message")
	s.mockStatter.AssertNotCalled(s.T(), "Timing", "schedule_emissions_handler.batch.send", mock.Anything, mock.Anything)
}

func (s *scheduleEmissionsHandlerTestSuite) TestScheduleEmissionsHandler_GetAllCustomersError() {
	logger := log.NewNullLogger()
	msg := &models.ScheduleEmissionsJob{UsageTime: 12345}
	jobPayload, err := json.Marshal(msg)
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job}

	pager := runtime.NewPager[azcosmos.QueryItemsResponse](runtime.PagingHandler[azcosmos.QueryItemsResponse]{
		More: func(current azcosmos.QueryItemsResponse) bool {
			return false
		},
		Fetcher: func(context.Context, *azcosmos.QueryItemsResponse) (azcosmos.QueryItemsResponse, error) {
			return azcosmos.QueryItemsResponse{}, &azcore.ResponseError{StatusCode: http.StatusPreconditionFailed}
		},
	})

	s.mockDB.On(
		"NewQueryItemsPager",
		"select * from c where c.sdlcLicensingModel = @sdlcLicensingModel and c.sdlcTrial = @sdlcTrial",
		azcosmos.NewPartitionKeyString(models.CustomerPartitionKey),
		mock.Anything,
	).Return(pager).Once()

	err = s.handler.ProcessMessage(context.Background(), logger, *rr)
	s.Require().Error(err)
	s.Require().Contains(err.Error(), "failed to get customers")
	s.mockStatter.AssertNotCalled(s.T(), "Timing", "schedule_emissions_handler.batch.send", mock.Anything, mock.Anything)
}

func (s *scheduleEmissionsHandlerTestSuite) TestScheduleEmissionsHandler_SendBatchSuccess() {
	usageTime := int64(12345)
	rr, customers := s.setupCommonTest(usageTime)

	s.mockAqueductClient.On(
		"SendBatch",
		mock.Anything,
		mock.AnythingOfType("[]aqueduct.BatchItem"),
	).Return(&aqueduct.SendBatchResult{}, nil).Once()

	err := s.handler.ProcessMessage(context.Background(), log.NewNullLogger(), *rr)
	s.Require().NoError(err)

	// Assert that the statter recorded the correct metrics
	s.mockStatter.AssertCalled(s.T(), "Timing", "schedule_emissions_handler.duration", stats.Tags{}, mock.AnythingOfType("time.Duration"))
	s.mockStatter.AssertCalled(s.T(), "Timing", "schedule_emissions_handler.batch.send", stats.Tags{}, mock.AnythingOfType("time.Duration"))
	s.mockStatter.AssertCalled(s.T(), "Counter", "schedule_emissions_handler.batch.processed", stats.Tags{}, int64(2))

	// Assert that the batch sent by the aqueduct client contains the correct data
	s.mockAqueductClient.AssertCalled(s.T(), "SendBatch", mock.Anything, mock.MatchedBy(func(batch []aqueduct.BatchItem) bool {
		// Ensure the batch contains exactly two items
		s.Require().Len(batch, 2)

		var payload1, payload2 models.PublishEmissionJob
		s.Require().NoError(json.Unmarshal(batch[0].Job.Payload, &payload1))
		s.Require().NoError(json.Unmarshal(batch[1].Job.Payload, &payload2))
		return payload1.CustomerID == customers[0].IDToUInt64() && payload1.UsageTime == usageTime &&
			payload2.CustomerID == customers[1].IDToUInt64() && payload2.UsageTime == usageTime
	}))
}

func (s *scheduleEmissionsHandlerTestSuite) TestScheduleEmissionsHandler_SendBatchError() {
	rr, _ := s.setupCommonTest(56788)

	s.mockAqueductClient.On(
		"SendBatch",
		mock.Anything,
		mock.AnythingOfType("[]aqueduct.BatchItem"),
	).Return(&aqueduct.SendBatchResult{}, &azcore.ResponseError{StatusCode: http.StatusPreconditionFailed}).Once()

	err := s.handler.ProcessMessage(context.Background(), log.NewNullLogger(), *rr)
	s.Require().Error(err)
	s.Require().Contains(err.Error(), "failed to send batch")
	s.mockStatter.AssertNotCalled(s.T(), "Timing", "schedule_emissions_handler.batch.send", mock.Anything, mock.Anything)
}

func TestScheduleEmissionsHandlerTestSuite(t *testing.T) {
	suite.Run(t, new(scheduleEmissionsHandlerTestSuite))
}
