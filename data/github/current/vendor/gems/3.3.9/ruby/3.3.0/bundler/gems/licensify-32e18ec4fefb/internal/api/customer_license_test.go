package api_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/licensify/internal/api"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/lib/globalid"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/github/licensify/testing/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/encoding/protojson"
)

type customerLicenseTestSuite struct {
	suite.Suite
	mockAqueductClient *mocks.MockAqueductClient
	mockDB             *mocks.MockDBReadWriter
	api                *api.CustomerLicenseAPI
	cfg                *config.Config
}

func (s *customerLicenseTestSuite) SetupTest() {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer
	logger := log.NewNullLogger()

	mockDB := &mocks.MockDBReadWriter{}
	mockAqueductClient := &mocks.MockAqueductClient{}
	customerLicenseEngine := engines.NewCustomerLicenseEngine(statter, tracer, mockDB)
	licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(statter, tracer, mockDB)
	s.mockAqueductClient = mockAqueductClient
	s.mockDB = mockDB
	s.api = api.NewCustomerLicenseAPI(customerLicenseEngine, licenseeLicenseEngine, mockAqueductClient, logger, cfg)
	s.cfg = cfg
}

func (s *customerLicenseTestSuite) TestGetCustomerLicenseSuccess() {
	customerID := uint64(42)
	licenseeType := models.LicenseeTypeUser
	userID := uint64(99)
	licenseeID := strconv.FormatUint(userID, 10)
	licenseGlobalID := &globalid.GlobalID{
		App:       "git-hub",
		ModelName: "User",
		ModelID:   licenseeID,
	}

	tests := map[string]struct {
		product     models.Product
		requestJSON string
	}{
		"globalId": {
			product: models.ProductSDLC,
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"globalId": "` + licenseGlobalID.String() + `"
				}
			}`,
		},
		"type and deprecated uint64 id": {
			product: models.ProductSDLC,
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"type": "` + licenseeType.ToProto().String() + `",
					"idDeprecated": "` + licenseeID + `"
				}
			}`,
		},
		"type and deprecated string id": {
			product: models.ProductSDLC,
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"type": "` + licenseeType.ToProto().String() + `",
					"id": "` + licenseeID + `"
				}
			}`,
		},
	}

	license := models.NewCustomerLicense(
		customerID,
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(licenseeType, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, []uint64{1099}),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledLicense, err := json.Marshal(license)
	s.Require().NoError(err)

	for name, test := range tests {
		s.Run(name, func() {
			reqContent, err := convertJSONToRequest(test.requestJSON)
			s.Require().NoError(err)

			wantKey := models.NewCustomerLicenseKey(
				customerID,
				test.product,
				licenseeType,
				licenseeID,
			)

			s.mockDB.On(
				"ReadItem",
				mock.Anything,
				azcosmos.NewPartitionKeyString(wantKey.PartitionKey),
				wantKey.ID,
				mock.Anything,
			).Return(azcosmos.ItemResponse{Value: marshalledLicense}, nil).Once()

			response, err := s.api.GetCustomerLicense(context.Background(), reqContent)
			s.Require().NoError(err)
			s.Require().Equal(1, len(response.GetCustomerLicenses()))
		})
	}
}

func (s *customerLicenseTestSuite) TestGetCustomerLicenseSuccessAllProducts() {
	customerID := uint64(42)
	licenseeType := models.LicenseeTypeUser
	userID := uint64(99)
	licenseeID := strconv.FormatUint(userID, 10)
	licenseGlobalID := &globalid.GlobalID{
		App:       "git-hub",
		ModelName: "User",
		ModelID:   licenseeID,
	}

	tests := map[string]struct {
		requestJSON string
	}{
		"no products in request": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"licensee": {
					"globalId": "` + licenseGlobalID.String() + `"
				}
			}`,
		},
	}

	license := models.NewCustomerLicense(
		customerID,
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(licenseeType, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, []uint64{1099}),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledLicense, err := json.Marshal(license)
	s.Require().NoError(err)

	allProducts := []models.Product{models.ProductSDLC, models.ProductGhas}

	for name, test := range tests {
		s.Run(name, func() {
			reqContent, err := convertJSONToRequest(test.requestJSON)
			s.Require().NoError(err)

			for _, product := range allProducts {
				wantKey := models.NewCustomerLicenseKey(
					customerID,
					product,
					licenseeType,
					licenseeID,
				)

				s.mockDB.On(
					"ReadItem",
					mock.Anything,
					azcosmos.NewPartitionKeyString(wantKey.PartitionKey),
					wantKey.ID,
					mock.Anything,
				).Return(azcosmos.ItemResponse{Value: marshalledLicense}, nil).Once()
			}

			response, err := s.api.GetCustomerLicense(context.Background(), reqContent)
			s.Require().NoError(err)
			s.Require().Equal(len(allProducts), len(response.GetCustomerLicenses()))
		})
	}
}

func (s *customerLicenseTestSuite) TestGetCustomerLicenseReturnsOnlyFoundProducts() {
	customerID := uint64(42)
	licenseeType := models.LicenseeTypeUser
	userID := uint64(99)
	licenseeID := strconv.FormatUint(userID, 10)
	licenseGlobalID := &globalid.GlobalID{
		App:       "git-hub",
		ModelName: "User",
		ModelID:   licenseeID,
	}

	tests := map[string]struct {
		requestJSON string
	}{
		"no products in request": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"licensee": {
					"globalId": "` + licenseGlobalID.String() + `"
				}
			}`,
		},
	}

	license := models.NewCustomerLicense(
		customerID,
		models.ProductSDLC,
		models.LicenseStatusActive,
		models.NewLicensee(licenseeType, licenseeID),
		[]*models.CustomerLicenseEnablement{
			models.NewCustomerLicenseEnablement(models.ProductEnablementTypeOrg, models.EnablementReasonOrgMembership, []uint64{1099}),
		},
		models.MaxExpiresAt,
		nil,
	)
	marshalledLicense, err := json.Marshal(license)
	s.Require().NoError(err)

	for name, test := range tests {
		s.Run(name, func() {
			reqContent, err := convertJSONToRequest(test.requestJSON)
			s.Require().NoError(err)

			wantKey := models.NewCustomerLicenseKey(
				customerID,
				models.ProductSDLC,
				licenseeType,
				licenseeID,
			)

			s.mockDB.On(
				"ReadItem",
				mock.Anything,
				azcosmos.NewPartitionKeyString(wantKey.PartitionKey),
				wantKey.ID,
				mock.Anything,
			).Return(azcosmos.ItemResponse{Value: marshalledLicense}, nil).Once()

			wantKey = models.NewCustomerLicenseKey(
				customerID,
				models.ProductGhas,
				licenseeType,
				licenseeID,
			)

			s.mockDB.On(
				"ReadItem",
				mock.Anything,
				azcosmos.NewPartitionKeyString(wantKey.PartitionKey),
				wantKey.ID,
				mock.Anything,
			).Return(azcosmos.ItemResponse{}, &azcore.ResponseError{ErrorCode: "", StatusCode: http.StatusNotFound, RawResponse: &http.Response{}}).Once()

			response, err := s.api.GetCustomerLicense(context.Background(), reqContent)
			s.Require().NoError(err)
			s.Require().Equal(1, len(response.GetCustomerLicenses()))
		})
	}
}

func (s *customerLicenseTestSuite) TestGetCustomerLicenseNotFound() {
	customerID := uint64(42)
	licenseeType := models.LicenseeTypeUser
	userID := uint64(99)
	licenseeID := strconv.FormatUint(userID, 10)
	licenseGlobalID := &globalid.GlobalID{
		App:       "git-hub",
		ModelName: "User",
		ModelID:   licenseeID,
	}

	tests := map[string]struct {
		requestJSON string
	}{
		"product not found": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"globalId": "` + licenseGlobalID.String() + `"
				}
			}`,
		},
	}

	for name, test := range tests {
		s.Run(name, func() {
			reqContent, err := convertJSONToRequest(test.requestJSON)
			s.Require().NoError(err)

			wantKey := models.NewCustomerLicenseKey(
				customerID,
				models.ProductSDLC,
				licenseeType,
				licenseeID,
			)

			s.mockDB.On(
				"ReadItem",
				mock.Anything,
				azcosmos.NewPartitionKeyString(wantKey.PartitionKey),
				wantKey.ID,
				mock.Anything,
			).Return(azcosmos.ItemResponse{}, &azcore.ResponseError{ErrorCode: "", StatusCode: http.StatusNotFound, RawResponse: &http.Response{}}).Once()

			_, err = s.api.GetCustomerLicense(context.Background(), reqContent)
			s.Require().Error(err)
			var twerr twirp.Error
			s.Require().True(errors.As(err, &twerr))
			s.Require().Contains(err.Error(), "No Licenses Found")
		})
	}
}

func (s *customerLicenseTestSuite) TestGetCustomerLicenseValidations() {
	customerID := uint64(42)
	licenseeType := models.LicenseeTypeUser
	licenseeID := uint64(99)
	licenseGlobalID := &globalid.GlobalID{
		App:       "git-hub",
		ModelName: "User",
		ModelID:   strconv.FormatUint(licenseeID, 10),
	}

	tests := map[string]struct {
		requestJSON string
		error       string
	}{
		"no customer id": {
			requestJSON: `{
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"globalId": "` + licenseGlobalID.String() + `"
				}
			}`,
			error: "request.customerId is required",
		},
		"no licensee": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"]
			}`,
			error: "request.licensee is required",
		},
		"global id, type, and deprecated uint64 id": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"globalId": "` + licenseGlobalID.String() + `",
					"type": "` + licenseeType.ToProto().String() + `",
					"idDeprecated": "` + strconv.FormatUint(licenseeID, 10) + `"
				}
			}`,
			error: "Either a licensee.globalId or a licensee.type and a licensee.id must be present",
		},
		"global id, type, and id": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"globalId": "` + licenseGlobalID.String() + `",
					"type": "` + licenseeType.ToProto().String() + `",
					"id": "` + strconv.FormatUint(licenseeID, 10) + `"
				}
			}`,
			error: "Either a licensee.globalId or a licensee.type and a licensee.id must be present",
		},
		"global id and type": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"globalId": "` + licenseGlobalID.String() + `",
					"type": "` + licenseeType.ToProto().String() + `"
				}
			}`,
			error: "Either a licensee.globalId or a licensee.type and a licensee.id must be present",
		},
		"global id and deprecated uint64 id": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"globalId": "` + licenseGlobalID.String() + `",
					"idDeprecated": "` + strconv.FormatUint(licenseeID, 10) + `"
				}
			}`,
			error: "Either a licensee.globalId or a licensee.type and a licensee.id must be present",
		},
		"global id and id": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"globalId": "` + licenseGlobalID.String() + `",
					"id": "` + strconv.FormatUint(licenseeID, 10) + `"
				}
			}`,
			error: "Either a licensee.globalId or a licensee.type and a licensee.id must be present",
		},
		"type and no id": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"type": "` + licenseeType.ToProto().String() + `"
				}
			}`,
			error: "Either a licensee.globalId or a licensee.type and a licensee.id must be present",
		},
		"deprecated uint64 id and no type": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"idDeprecated": "` + strconv.FormatUint(licenseeID, 10) + `"
				}
			}`,
			error: "Either a licensee.globalId or a licensee.type and a licensee.id must be present",
		},
		"id and no type": {
			requestJSON: `{
				"customerId": "` + strconv.FormatUint(customerID, 10) + `",
				"products": ["` + proto.Product_PRODUCT_SDLC.String() + `"],
				"licensee": {
					"id": "` + strconv.FormatUint(licenseeID, 10) + `"
				}
			}`,
			error: "Either a licensee.globalId or a licensee.type and a licensee.id must be present",
		},
	}

	for name, test := range tests {
		s.Run(name, func() {
			reqContent, err := convertJSONToRequest(test.requestJSON)
			s.Require().NoError(err)

			s.mockDB.On("ReadItem")

			_, err = s.api.GetCustomerLicense(context.Background(), reqContent)
			s.Require().Error(err)
			s.Require().Contains(err.Error(), test.error)
		})
	}
}

func (s *customerLicenseTestSuite) TestSyncOrganizationMembershipsEnqueuesJob() {
	jobID := "jobID-1234"

	tests := []struct {
		name        string
		request     *proto.SyncOrganizationMembershipsRequest
		wantSyncJob *models.SyncOrganizationMembershipsJob
	}{
		{
			name: "entity_type customer",
			request: &proto.SyncOrganizationMembershipsRequest{
				EntityId:   100,
				EntityType: proto.SyncEntityType_SYNC_ENTITY_TYPE_CUSTOMER,
			},
			wantSyncJob: &models.SyncOrganizationMembershipsJob{
				EntityID:   100,
				EntityType: models.SyncEntityTypeCustomer,
			},
		},
		{
			name: "entity_type organization",
			request: &proto.SyncOrganizationMembershipsRequest{
				EntityId:   200,
				EntityType: proto.SyncEntityType_SYNC_ENTITY_TYPE_ORGANIZATION,
			},
			wantSyncJob: &models.SyncOrganizationMembershipsJob{
				EntityID:   200,
				EntityType: models.SyncEntityTypeOrganization,
			},
		},
	}
	for _, tt := range tests {
		s.Run(tt.name, func() {
			wantPayload, err := json.Marshal(tt.wantSyncJob)
			s.Require().NoError(err)

			s.mockAqueductClient.On(
				"Send",
				mock.Anything,
				mock.MatchedBy(func(j aqueduct.Job) bool {
					return j.App == s.cfg.AqueductApp &&
						j.Queue == queues.QueueBackfillSyncOrgMemberships &&
						j.Headers[jobs.JobNameHeader] == jobs.JobNameSyncOrgMemberships &&
						bytes.Equal(j.Payload, wantPayload)
				}),
				mock.AnythingOfType("[]aqueduct.SendOption"),
			).Return(jobID, nil).Once()

			response, err := s.api.SyncOrganizationMemberships(context.Background(), tt.request)

			s.Require().NoError(err)
			s.Equal(jobID, response.JobId)
		})
	}
}

func (s *customerLicenseTestSuite) TestGetLicenseeByProductAndEnablementReasonsValidations() {
	customerID := uint64(42)

	tests := map[string]struct {
		request *proto.GetLicenseeIdsRequest
		error   string
	}{
		"no customer id": {
			request: &proto.GetLicenseeIdsRequest{
				Product:           proto.Product_PRODUCT_SDLC,
				EnablementReasons: []proto.EnablementReason{proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP},
			},
			error: "request.customerId is required",
		},
		"no product": {
			request: &proto.GetLicenseeIdsRequest{
				CustomerId:        customerID,
				EnablementReasons: []proto.EnablementReason{proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP},
			},
			error: "request.product is required",
		},
	}

	for name, test := range tests {
		s.Run(name, func() {
			_, err := s.api.GetLicenseeIds(context.Background(), test.request)
			s.Require().Error(err)
			s.Require().Contains(err.Error(), test.error)
			s.mockDB.AssertNotCalled(s.T(), "NewQueryItemsPager")
		})
	}
}

func (s *customerLicenseTestSuite) TestGetLicenseesForProductAndEnablementReasonsFiltersByReason() {
	customerID := uint64(42)
	licenseeIDs := []uint64{100, 200, 300}
	licenseeIDsAsStrings := make([]string, 0, len(licenseeIDs))
	for _, id := range licenseeIDs {
		licenseeIDsAsStrings = append(licenseeIDsAsStrings, strconv.FormatUint(id, 10))
	}

	tests := map[string]struct {
		request         *proto.GetLicenseeIdsRequest
		wantQueryString string
		wantQueryParams []azcosmos.QueryParameter
	}{
		"no reasons": {
			request: &proto.GetLicenseeIdsRequest{
				CustomerId: customerID,
				Product:    proto.Product_PRODUCT_SDLC,
			},
			wantQueryString: "SELECT DISTINCT VALUE c.Licensee.ID FROM c",
			wantQueryParams: []azcosmos.QueryParameter{},
		},
		"one reason": {
			request: &proto.GetLicenseeIdsRequest{
				CustomerId:        customerID,
				Product:           proto.Product_PRODUCT_SDLC,
				EnablementReasons: []proto.EnablementReason{proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP},
			},
			wantQueryString: "SELECT DISTINCT VALUE c.Licensee.ID FROM c JOIN e IN c.Enablements WHERE e.Reason IN (@reason0)",
			wantQueryParams: []azcosmos.QueryParameter{
				{Name: "@reason0", Value: models.EnablementReasonOrgMembership.String()},
			},
		},
		"multiple reasons": {
			request: &proto.GetLicenseeIdsRequest{
				CustomerId:        customerID,
				Product:           proto.Product_PRODUCT_SDLC,
				EnablementReasons: []proto.EnablementReason{proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP, proto.EnablementReason_ENABLEMENT_REASON_REPOSITORY_COLLABORATOR},
			},
			wantQueryString: "SELECT DISTINCT VALUE c.Licensee.ID FROM c JOIN e IN c.Enablements WHERE e.Reason IN (@reason0, @reason1)",
			wantQueryParams: []azcosmos.QueryParameter{
				{Name: "@reason0", Value: models.EnablementReasonOrgMembership.String()},
				{Name: "@reason1", Value: models.EnablementReasonRepositoryCollaborator.String()},
			},
		},
	}

	for name, test := range tests {
		s.Run(name, func() {
			itemsReturned := make([][]byte, 0)
			for _, id := range licenseeIDs {
				licenseeBytes, err := json.Marshal(id)
				s.Require().NoError(err)
				itemsReturned = append(itemsReturned, licenseeBytes)
			}
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
				test.wantQueryString,
				azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
				&azcosmos.QueryOptions{
					PageSizeHint:    -1,
					QueryParameters: test.wantQueryParams,
				},
			).Return(pager).Once()

			response, err := s.api.GetLicenseeIds(context.Background(), test.request)
			s.Require().NoError(err)

			//nolint:staticcheck // Use LicenseeIdsDeprecated for backward compatibility
			s.Equal(licenseeIDs, response.LicenseeIdsDeprecated)

			s.Equal(licenseeIDsAsStrings, response.LicenseeIds)
		})
	}
}

func convertJSONToRequest(rawJSON string) (*proto.GetCustomerLicenseRequest, error) {
	reqContent := new(proto.GetCustomerLicenseRequest)
	unmarshaler := protojson.UnmarshalOptions{DiscardUnknown: true}
	err := unmarshaler.Unmarshal([]byte(rawJSON), reqContent)
	return reqContent, err
}

func TestCustomerLicenseTestSuite(t *testing.T) {
	suite.Run(t, new(customerLicenseTestSuite))
}
