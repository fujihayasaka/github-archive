package handlers_test

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	billingplatformv1 "github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1"
	entities "github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1/entities"
	licensifyv0 "github.com/github/hydro-schemas-go/hydro/schemas/licensify/v0"
	"github.com/github/licensify/internal/aqueduct/handlers"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type publishEmissionHandlerTestSuite struct {
	suite.Suite
	mockDB              *mocks.MockDBReadWriter
	mockHydroPublisher  *mocks.MockHydroPublisher
	mockFeatureFlagsAPI *mocks.MockFeatureFlagsAPI
	handler             *handlers.PublishEmissionHandler
	cfg                 *config.Config
}

func (s *publishEmissionHandlerTestSuite) SetupTest() {
	cfg, _ := config.Load()
	s.cfg = cfg
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	s.mockDB = &mocks.MockDBReadWriter{}
	customerEngine := engines.NewCustomerEngine(statter, tracer, s.mockDB)
	customerLicenseEngine := engines.NewCustomerLicenseEngine(statter, tracer, s.mockDB)
	s.mockHydroPublisher = &mocks.MockHydroPublisher{}
	s.mockFeatureFlagsAPI = &mocks.MockFeatureFlagsAPI{}
	s.handler = handlers.NewPublishEmissionHandler(cfg, customerEngine, customerLicenseEngine, s.mockFeatureFlagsAPI, s.mockHydroPublisher, statter, tracer)
}

func (s *publishEmissionHandlerTestSuite) setupCommonTestData() (
	logger log.Logger,
	rr *aqueduct.ReceiveResult,
	customer models.Customer,
	testUsage *licensifyv0.TestLicenseUsage,
	usage *billingplatformv1.Usage,
) {
	s.T().Helper()
	logger = log.NewNullLogger()

	secondsSinceEpoch := int64(1728675888)
	unixTime := time.Unix(secondsSinceEpoch, 0)

	userID := uint64(200)
	customerID := uint64(105)
	customer = *models.NewCustomer(customerID, models.LicensingModelMetered, false)
	marshalledCustomer, err := json.Marshal(customer)
	s.Require().NoError(err)

	msg := &models.PublishEmissionJob{UsageTime: secondsSinceEpoch, CustomerID: customerID}
	jobPayload, err := json.Marshal(msg)
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr = &aqueduct.ReceiveResult{Job: *job}

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(models.CustomerPartitionKey),
		customer.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledCustomer}, nil).Once()

	eTag := azcore.ETag("etag")
	customerLicense := *models.NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 100)
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
		mock.Anything,
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		mock.MatchedBy(func(options *azcosmos.QueryOptions) bool {
			return len(options.QueryParameters) == 3 &&
				options.QueryParameters[0].Name == "@licenseStatusDeactivated" &&
				options.QueryParameters[0].Value == "deactivated" &&
				options.QueryParameters[1].Name == "@orgMembershipReason" &&
				options.QueryParameters[1].Value == "organizationMembership" &&
				options.QueryParameters[2].Name == "@repoCollaboratorReason" &&
				options.QueryParameters[2].Value == "repositoryCollaborator"
		}),
	).Return(pager).Once()

	wantHash := sha256.Sum256([]byte(fmt.Sprintf("%s:%d:%s:%d:%s", models.ProductSDLC, customerID, models.LicenseeTypeUser, userID, unixTime.Format("01/02/2006:15:04:05"))))
	wantUsageUUID := hex.EncodeToString(wantHash[:])

	testUsage = &licensifyv0.TestLicenseUsage{
		Entity: &entities.EntityDetail{
			ActorId:    int64(userID),
			CustomerId: int64(customerID),
		},
		Quantity:  0.03225806451612903,
		Sku:       "ghec_licenses",
		SourceUri: fmt.Sprintf("gid://git-hub/User/%d", userID),
		UsageAt:   timestamppb.New(unixTime),
		UsageUuid: wantUsageUUID,
	}
	usage = &billingplatformv1.Usage{
		Entity: &entities.EntityDetail{
			ActorId:    int64(userID),
			CustomerId: int64(customerID),
		},
		Quantity:  0.03225806451612903,
		Sku:       "ghec_licenses",
		SourceUri: fmt.Sprintf("gid://git-hub/User/%d", userID),
		UsageAt:   timestamppb.New(unixTime),
		UsageUuid: wantUsageUUID,
	}

	return logger, rr, customer, testUsage, usage
}

func (s *publishEmissionHandlerTestSuite) mockFeatureFlagResponse(customerID uint64, isEnabled bool) {
	s.mockFeatureFlagsAPI.On(
		"CheckActorFeature",
		mock.Anything,
		&twirpFeatures.CheckActorFeatureRequest{
			ActorId: fmt.Sprintf("Customer:%d", customerID),
			Feature: "ghec_bill_through_licensify",
		},
	).Return(&twirpFeatures.CheckActorFeatureResponse{IsEnabled: isEnabled}, nil).Once()
}

func (s *publishEmissionHandlerTestSuite) TestPublishEmissionHandler_UnmarshalError() {
	logger := log.NewNullLogger()
	job := &aqueduct.Job{Payload: []byte("invalid json")}
	rr := &aqueduct.ReceiveResult{Job: *job}

	err := s.handler.ProcessMessage(context.Background(), logger, *rr)
	s.Require().Error(err)
	s.Require().Contains(err.Error(), "failed to unmarshal message")
}

func (s *publishEmissionHandlerTestSuite) TestPublishEmissionHandler_CustomerLicensesRetrievalError() {
	logger := log.NewNullLogger()

	usageTime := time.Now().Unix()
	customer := models.NewCustomer(stubs.NewRandomID(), models.LicensingModelMetered, false)
	marshalledCustomer, err := json.Marshal(customer)
	s.Require().NoError(err)

	msg := &models.PublishEmissionJob{UsageTime: usageTime, CustomerID: customer.IDToUInt64()}
	jobPayload, err := json.Marshal(msg)
	s.Require().NoError(err)
	job := &aqueduct.Job{Payload: jobPayload}
	rr := &aqueduct.ReceiveResult{Job: *job}

	s.mockFeatureFlagResponse(customer.IDToUInt64(), false)

	s.mockDB.On(
		"ReadItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(models.CustomerPartitionKey),
		customer.ID,
		mock.Anything,
	).Return(azcosmos.ItemResponse{Value: marshalledCustomer}, nil).Once()

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
		mock.Anything,
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customer.IDToUInt64(), models.ProductSDLC)),
		mock.Anything,
	).Return(pager).Once()

	err = s.handler.ProcessMessage(context.Background(), logger, *rr)
	s.Require().Error(err)
	s.Require().Contains(err.Error(), "failed to get customer licenses")
}

func (s *publishEmissionHandlerTestSuite) TestPublishEmissionHandler_PublishSuccess() {
	logger, rr, customer, testUsage, _ := s.setupCommonTestData()

	s.mockFeatureFlagResponse(customer.IDToUInt64(), false)

	s.mockHydroPublisher.On("Publish", testUsage, mock.Anything).Return(nil).Once()

	err := s.handler.ProcessMessage(context.Background(), logger, *rr)
	s.Require().NoError(err)

	s.mockHydroPublisher.AssertExpectations(s.T())
}

func (s *publishEmissionHandlerTestSuite) TestPublishEmissionHandler_PublishesToBillingPlatform() {
	logger, rr, customer, testUsage, usage := s.setupCommonTestData()
	handlers.BillingPlatformCustomerIDs[s.cfg.HeavenEnv] = make(map[uint64]struct{})
	handlers.BillingPlatformCustomerIDs[s.cfg.HeavenEnv][customer.IDToUInt64()] = struct{}{}

	s.mockFeatureFlagResponse(customer.IDToUInt64(), false)
	s.mockHydroPublisher.On("Publish", testUsage, mock.Anything).Return(nil).Once()
	s.mockHydroPublisher.On("Publish", usage, mock.Anything).Return(nil).Once()

	err := s.handler.ProcessMessage(context.Background(), logger, *rr)
	s.Require().NoError(err)

	s.mockHydroPublisher.AssertExpectations(s.T())
}

func (s *publishEmissionHandlerTestSuite) TestPublishEmissionHandler_PublishesToBillingPlatformWhenFeatureFlagEnabled() {
	logger, rr, customer, testUsage, usage := s.setupCommonTestData()

	s.mockFeatureFlagResponse(customer.IDToUInt64(), true)
	s.mockHydroPublisher.On("Publish", testUsage, mock.Anything).Return(nil).Once()
	s.mockHydroPublisher.On("Publish", usage, mock.Anything).Return(nil).Once()

	err := s.handler.ProcessMessage(context.Background(), logger, *rr)
	s.Require().NoError(err)

	s.mockHydroPublisher.AssertExpectations(s.T())
}

func (s *publishEmissionHandlerTestSuite) TestPublishEmissionHandler_PublishFail() {
	logger, rr, customer, testUsage, _ := s.setupCommonTestData()

	s.mockFeatureFlagResponse(customer.IDToUInt64(), false)
	s.mockHydroPublisher.On("Publish", testUsage, mock.Anything).Return(errors.New("failed to publish emission message")).Once()

	err := s.handler.ProcessMessage(context.Background(), logger, *rr)
	s.Require().Error(err)

	expectedFailedMessages := []protoreflect.ProtoMessage{testUsage}
	expectedErrorMessage := fmt.Sprintf("failed to publish emission messages for licenses: %v", expectedFailedMessages)
	s.Require().Contains(err.Error(), expectedErrorMessage)

	s.mockHydroPublisher.AssertExpectations(s.T())
}

func TestPublishEmissionHandlerTestSuite(t *testing.T) {
	suite.Run(t, new(publishEmissionHandlerTestSuite))
}
