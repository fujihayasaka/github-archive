package api_test

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/licensify/internal/api"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/github/licensify/testing/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type customerTestSuite struct {
	suite.Suite
	mockAqueductClient *mocks.MockAqueductClient
	mockDB             *mocks.MockDBReadWriter
	api                *api.CustomerAPI
	cfg                *config.Config
}

func (s *customerTestSuite) SetupTest() {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer
	logger := log.NewNullLogger()

	mockDB := &mocks.MockDBReadWriter{}
	mockAqueductClient := &mocks.MockAqueductClient{}
	customerEngine := engines.NewCustomerEngine(statter, tracer, mockDB)
	s.mockAqueductClient = mockAqueductClient
	s.mockDB = mockDB
	s.api = api.NewCustomerAPI(customerEngine, mockAqueductClient, logger, cfg)
	s.cfg = cfg
}

func TestCustomerTestSuite(t *testing.T) {
	suite.Run(t, new(customerTestSuite))
}

func (s *customerTestSuite) TestUpsertCustomer() {
	customer := models.NewCustomer(1, 1, true)
	marshalledCustomer, err1 := json.Marshal(customer)
	s.Require().NoError(err1)

	s.mockDB.On(
		"UpsertItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString("Customer"),
		marshalledCustomer,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, nil).Once()

	upsertReq := &proto.UpsertCustomerRequest{Customer: customer.ToProto()}
	_, err := s.api.UpsertCustomer(context.Background(), upsertReq)
	s.Require().NoError(err)
}

func (s *customerTestSuite) TestUpsertCustomerWithoutID() {
	customer := models.NewCustomer(0, 1, true)

	upsertReq := &proto.UpsertCustomerRequest{Customer: customer.ToProto()}
	_, err := s.api.UpsertCustomer(context.Background(), upsertReq)
	s.Require().EqualError(err, "twirp error invalid_argument: id is required")
}

func (s *customerTestSuite) TestUpsertCustomerWithoutLicensingModel() {
	customer := models.NewCustomer(1, 0, true)

	upsertReq := &proto.UpsertCustomerRequest{Customer: customer.ToProto()}
	_, err := s.api.UpsertCustomer(context.Background(), upsertReq)
	s.Require().EqualError(err, "twirp error invalid_argument: sdlcLicensingModel is required")
}
