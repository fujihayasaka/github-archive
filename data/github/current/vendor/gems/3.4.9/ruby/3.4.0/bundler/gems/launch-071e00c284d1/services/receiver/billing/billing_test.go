package billing

import (
	"bytes"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/twitchtv/twirp"

	billingplatformProto "github.com/github/actions-proto/gen/go/billing-platform/api/v1"

	"github.com/github/launch/auth"
	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/clients/billingplatform"
	"github.com/github/launch/clients/ghtwirp"
	githubFF "github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

var rawSignature = []byte("random_signature")

func TestBilling(t *testing.T) {
	suite.Run(t, new(billingTestSuite))
}

const (
	httpsScheme = "https"
)

type billingTestSuite struct {
	suite.Suite
	svc                   *Service
	db                    deployer.MockAzpResourcesLoader
	twirpClient           *ghtwirp.MockClient
	log                   testutils.RecordingLogger
	verifier              *auth.MockVerifier
	tenantId              string
	httpVerifier          *hmac.HTTPVerifier
	authVerifier          *auth.MockVerifier
	keyFetcher            *hmac.MockKeyFetcher
	billingPlatformClient *billingplatform.MockClient
}

func (s *billingTestSuite) SetupTest() {
	s.tenantId = "test-tenant-id"
	s.authVerifier = &auth.MockVerifier{}
	s.keyFetcher = &hmac.MockKeyFetcher{}
	s.twirpClient = &ghtwirp.MockClient{}
	s.billingPlatformClient = &billingplatform.MockClient{}

	s.keyFetcher.EXPECT().GetHMACKeys(mock.Anything).Return([2]auth.Key{[]byte("hmacKey"), []byte("hmacKey")}, nil)
	obs := observability.New(testutils.NewRecordingLogger().Logger, statter.NullStatter())
	s.httpVerifier = hmac.NewHTTPVerifier(s.keyFetcher, obs, s.authVerifier, httpsScheme)
	s.svc = NewService(
		obs,
		&s.db,
		s.httpVerifier,
		s.twirpClient,
		s.billingPlatformClient,
	)
}

func (s *billingTestSuite) getAuthorizationHeader() string {
	return fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString(rawSignature))
}

func (s *billingTestSuite) TestGettingBillingDetails() {
	azpResource := &deployer.AzpResource{
		EntityID: types.GlobalID("O_kgAE"),
		TenantID: s.tenantId,
	}
	getOrgOwnerResponse := &ghtwirp.OrganizationOwner{
		Organization: ghtwirp.Entity{
			ID:       4,
			GlobalID: azpResource.EntityID,
		},
		OrganizationPlanName: ghtwirp.EnterprisePlan,
		Business:             nil,
	}
	_, orgDatabaseID, err := azpResource.EntityID.Decode()
	s.NoError(err)
	s.authVerifier.EXPECT().Verify(mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.EXPECT().GetByTenantID(mock.Anything, mock.Anything).Return(azpResource, true, nil)

	s.twirpClient.EXPECT().GetOrganizationOwner(mock.Anything, orgDatabaseID).Return(getOrgOwnerResponse, nil)
	s.twirpClient.EXPECT().IsFeatureEnabledForActor(mock.Anything, githubFF.BillingCanProceedWithUsageProductEnabled, azpResource.EntityID).Return(false)
	s.twirpClient.EXPECT().IsFeatureEnabledForActor(mock.Anything, githubFF.ActionsUseBillingPlatform, azpResource.EntityID).Return(false)

	s.twirpClient.EXPECT().GetBillingDetailsForEntity(mock.Anything, mock.Anything, mock.Anything).Return(&ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           true,
	}, nil)

	res := httptest.NewRecorder()

	request_url := "/actions/billing/limits?tenantId=" + s.tenantId
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetBillingDetails(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"IsActionsUsageAllowed\":true,\"IsActionsStorageAllowed\":true,\"IsOwnerSpammy\":true}\n", res.Body.String())
}

func (s *billingTestSuite) TestGettingBillingDetailsWithBillingPlatform() {
	azpResource := &deployer.AzpResource{
		EntityID: types.GlobalID("O_kgAE"),
		TenantID: s.tenantId,
	}
	getOrgOwnerResponse := &ghtwirp.OrganizationOwner{
		Organization: ghtwirp.Entity{
			ID:       4,
			GlobalID: azpResource.EntityID,
		},
		OrganizationPlanName: ghtwirp.EnterprisePlan,
		Business: &ghtwirp.Entity{
			ID:       1,
			GlobalID: types.GlobalID("E_kgAB"),
		},
	}
	_, orgDatabaseID, err := azpResource.EntityID.Decode()
	s.NoError(err)
	s.authVerifier.EXPECT().Verify(mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.EXPECT().GetByTenantID(mock.Anything, mock.Anything).Return(azpResource, true, nil)

	s.twirpClient.EXPECT().GetOrganizationOwner(mock.Anything, orgDatabaseID).Return(getOrgOwnerResponse, nil)
	s.twirpClient.EXPECT().IsFeatureEnabledForActor(mock.Anything, githubFF.BillingCanProceedWithUsageProductEnabled, getOrgOwnerResponse.Business.GlobalID).Return(false)
	s.twirpClient.EXPECT().IsFeatureEnabledForActor(mock.Anything, githubFF.ActionsUseBillingPlatform, getOrgOwnerResponse.Business.GlobalID).Return(true)
	s.twirpClient.EXPECT().GetAccountDetails(mock.Anything, azpResource.EntityID).Return(&ghtwirp.AccountDetails{
		CustomerID: 10,
	}, nil)

	customerID := int64(10)
	s.billingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		"test-sku",
		&customerID,
		azpResource.EntityID,
		types.NilGlobalID,
		types.NilGlobalID,
		statter.Tags{"caller": "larger_runners"},
	).Return(
		&billingplatform.CanProceedWithUsageResp{
			IsActionsStorageAllowed: true,
			IsActionsUsageAllowed:   true,
			IsOwnerSpammy:           true,
		},
		nil,
	)

	res := httptest.NewRecorder()

	request_url := fmt.Sprintf("/actions/billing/limits?tenantId=%s&productSku=%s", s.tenantId, "test-sku")
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetBillingDetails(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"IsActionsUsageAllowed\":true,\"IsActionsStorageAllowed\":true,\"IsOwnerSpammy\":true}\n", res.Body.String())
}

func (s *billingTestSuite) TestGettingBillingDetailsWithBillingPlatformOrgNotFound() {
	azpResource := &deployer.AzpResource{
		EntityID: types.GlobalID("O_kgAE"),
		TenantID: s.tenantId,
	}
	_, orgDatabaseID, err := azpResource.EntityID.Decode()
	s.NoError(err)
	s.authVerifier.EXPECT().Verify(mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.EXPECT().GetByTenantID(mock.Anything, mock.Anything).Return(azpResource, true, nil)

	s.twirpClient.EXPECT().GetOrganizationOwner(mock.Anything, orgDatabaseID).Return(nil, twirp.NotFoundError("org not found"))

	res := httptest.NewRecorder()

	request_url := fmt.Sprintf("/actions/billing/limits?tenantId=%s&productSku=%s", s.tenantId, "test-sku")
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetBillingDetails(res, req)
	s.Equal(http.StatusNotFound, res.Code)
}

func (s *billingTestSuite) TestGettingBillingDetailsWithBillingPlatform_NewCheck() {
	azpResource := &deployer.AzpResource{
		EntityID: types.GlobalID("O_kgAE"),
		TenantID: s.tenantId,
	}
	getOrgOwnerResponse := &ghtwirp.OrganizationOwner{
		Organization: ghtwirp.Entity{
			ID:       4,
			GlobalID: azpResource.EntityID,
		},
		OrganizationPlanName: ghtwirp.EnterprisePlan,
		Business: &ghtwirp.Entity{
			ID:       1,
			GlobalID: types.GlobalID("E_kgAB"),
		},
	}
	_, orgDatabaseID, err := azpResource.EntityID.Decode()
	s.NoError(err)
	s.authVerifier.EXPECT().Verify(mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.EXPECT().GetByTenantID(mock.Anything, mock.Anything).Return(azpResource, true, nil)

	s.twirpClient.EXPECT().GetOrganizationOwner(mock.Anything, orgDatabaseID).Return(getOrgOwnerResponse, nil)
	s.twirpClient.EXPECT().IsFeatureEnabledForActor(mock.Anything, githubFF.BillingCanProceedWithUsageProductEnabled, getOrgOwnerResponse.Business.GlobalID).Return(true)
	s.twirpClient.EXPECT().GetAccountDetails(mock.Anything, azpResource.EntityID).Return(&ghtwirp.AccountDetails{
		CustomerID: 10,
	}, nil)

	customerID := int64(10)
	s.billingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		"test-sku",
		&customerID,
		azpResource.EntityID,
		types.NilGlobalID,
		types.NilGlobalID,
		statter.Tags{"caller": "larger_runners"},
	).Return(
		&billingplatform.CanProceedWithUsageResp{
			IsActionsStorageAllowed: true,
			IsActionsUsageAllowed:   true,
			IsOwnerSpammy:           true,
		},
		nil,
	)

	res := httptest.NewRecorder()

	request_url := fmt.Sprintf("/actions/billing/limits?tenantId=%s&productSku=%s", s.tenantId, "test-sku")
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetBillingDetails(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"IsActionsUsageAllowed\":true,\"IsActionsStorageAllowed\":true,\"IsOwnerSpammy\":true}\n", res.Body.String())
}

func (s *billingTestSuite) TestGettingBillingDetailsWithBillingPlatform_CustomerNotFound_NewCheck() {
	azpResource := &deployer.AzpResource{
		EntityID: types.GlobalID("O_kgAE"),
		TenantID: s.tenantId,
	}
	getOrgOwnerResponse := &ghtwirp.OrganizationOwner{
		Organization: ghtwirp.Entity{
			ID:       4,
			GlobalID: azpResource.EntityID,
		},
		OrganizationPlanName: ghtwirp.EnterprisePlan,
		Business: &ghtwirp.Entity{
			ID:       1,
			GlobalID: types.GlobalID("E_kgAB"),
		},
	}
	_, orgDatabaseID, err := azpResource.EntityID.Decode()
	s.NoError(err)
	s.authVerifier.EXPECT().Verify(mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.EXPECT().GetByTenantID(mock.Anything, mock.Anything).Return(azpResource, true, nil)

	s.twirpClient.EXPECT().GetOrganizationOwner(mock.Anything, orgDatabaseID).Return(getOrgOwnerResponse, nil)
	s.twirpClient.EXPECT().IsFeatureEnabledForActor(mock.Anything, githubFF.BillingCanProceedWithUsageProductEnabled, getOrgOwnerResponse.Business.GlobalID).Return(true)
	s.twirpClient.EXPECT().GetAccountDetails(mock.Anything, azpResource.EntityID).Return(&ghtwirp.AccountDetails{
		CustomerID: 10,
	}, nil)

	customerID := int64(10)
	s.billingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		"test-sku",
		&customerID,
		azpResource.EntityID,
		types.NilGlobalID,
		types.NilGlobalID,
		statter.Tags{"caller": "larger_runners"},
	).Return(
		nil,
		twirp.NotFoundError(fmt.Sprintf("Customer with id %d not found", customerID)),
	)

	// assert that we make a call to get billing details if the customer does not exist in billing platform
	s.twirpClient.EXPECT().GetBillingDetailsForEntity(mock.Anything, mock.Anything, mock.Anything).Return(&ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           true,
	}, nil)

	res := httptest.NewRecorder()

	request_url := fmt.Sprintf("/actions/billing/limits?tenantId=%s&productSku=%s", s.tenantId, "test-sku")
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetBillingDetails(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"IsActionsUsageAllowed\":true,\"IsActionsStorageAllowed\":true,\"IsOwnerSpammy\":true}\n", res.Body.String())
}

func (s *billingTestSuite) TestGettingBillingDetailsWithBillingPlatform_CustomerNotFoundTwice_NewCheck() {
	azpResource := &deployer.AzpResource{
		EntityID: types.GlobalID("O_kgAE"),
		TenantID: s.tenantId,
	}
	getOrgOwnerResponse := &ghtwirp.OrganizationOwner{
		Organization: ghtwirp.Entity{
			ID:       4,
			GlobalID: azpResource.EntityID,
		},
		OrganizationPlanName: ghtwirp.EnterprisePlan,
		Business: &ghtwirp.Entity{
			ID:       1,
			GlobalID: types.GlobalID("E_kgAB"),
		},
	}
	_, orgDatabaseID, err := azpResource.EntityID.Decode()
	s.NoError(err)
	s.authVerifier.EXPECT().Verify(mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.EXPECT().GetByTenantID(mock.Anything, mock.Anything).Return(azpResource, true, nil)

	s.twirpClient.EXPECT().GetOrganizationOwner(mock.Anything, orgDatabaseID).Return(getOrgOwnerResponse, nil)
	s.twirpClient.EXPECT().IsFeatureEnabledForActor(mock.Anything, githubFF.BillingCanProceedWithUsageProductEnabled, getOrgOwnerResponse.Business.GlobalID).Return(true)
	s.twirpClient.EXPECT().GetAccountDetails(mock.Anything, azpResource.EntityID).Return(&ghtwirp.AccountDetails{
		CustomerID: 10,
	}, nil)

	customerID := int64(10)

	var errs error
	errs = errors.Join(errs, twirp.NotFoundError(fmt.Sprintf("Customer with id %d not found", customerID)))
	errs = errors.Join(errs, twirp.NotFoundError(fmt.Sprintf("Customer with id %d not found", customerID)))

	s.billingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		"test-sku",
		&customerID,
		azpResource.EntityID,
		types.NilGlobalID,
		types.NilGlobalID,
		statter.Tags{"caller": "larger_runners"},
	).Return(
		nil,
		errs,
	)

	// assert that we make a call to get billing details if the customer does not exist in billing platform
	s.twirpClient.EXPECT().GetBillingDetailsForEntity(mock.Anything, mock.Anything, mock.Anything).Return(&ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           true,
	}, nil)

	res := httptest.NewRecorder()

	request_url := fmt.Sprintf("/actions/billing/limits?tenantId=%s&productSku=%s", s.tenantId, "test-sku")
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetBillingDetails(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"IsActionsUsageAllowed\":true,\"IsActionsStorageAllowed\":true,\"IsOwnerSpammy\":true}\n", res.Body.String())
}

func (s *billingTestSuite) TestGettingBillingDetailsWithBillingPlatform_ProductNotEnabled_NewCheck() {
	azpResource := &deployer.AzpResource{
		EntityID: types.GlobalID("O_kgAE"),
		TenantID: s.tenantId,
	}
	getOrgOwnerResponse := &ghtwirp.OrganizationOwner{
		Organization: ghtwirp.Entity{
			ID:       4,
			GlobalID: azpResource.EntityID,
		},
		OrganizationPlanName: ghtwirp.EnterprisePlan,
		Business: &ghtwirp.Entity{
			ID:       1,
			GlobalID: types.GlobalID("E_kgAB"),
		},
	}
	_, orgDatabaseID, err := azpResource.EntityID.Decode()
	s.NoError(err)
	s.authVerifier.EXPECT().Verify(mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.EXPECT().GetByTenantID(mock.Anything, mock.Anything).Return(azpResource, true, nil)

	s.twirpClient.EXPECT().GetOrganizationOwner(mock.Anything, orgDatabaseID).Return(getOrgOwnerResponse, nil)
	s.twirpClient.EXPECT().IsFeatureEnabledForActor(mock.Anything, githubFF.BillingCanProceedWithUsageProductEnabled, getOrgOwnerResponse.Business.GlobalID).Return(true)
	s.twirpClient.EXPECT().GetAccountDetails(mock.Anything, azpResource.EntityID).Return(&ghtwirp.AccountDetails{
		CustomerID: 10,
	}, nil)

	customerID := int64(10)
	s.billingPlatformClient.EXPECT().CanProceedWithUsage(
		mock.Anything,
		"test-sku",
		&customerID,
		azpResource.EntityID,
		types.NilGlobalID,
		types.NilGlobalID,
		statter.Tags{"caller": "larger_runners"},
	).Return(
		&billingplatform.CanProceedWithUsageResp{
			IsActionsStorageAllowed: true,
			IsActionsUsageAllowed:   true,
			IsOwnerSpammy:           true,
			Status:                  billingplatformProto.CanProceedWithUsageStatus_ProductNotEnabled,
		},
		nil,
	)
	// assert that we make a call to get billing details if the customer is not enabled for the product on billing platform
	s.twirpClient.EXPECT().GetBillingDetailsForEntity(mock.Anything, mock.Anything, mock.Anything).Return(&ghtwirp.WorkflowBillingDetails{
		IsActionsStorageAllowed: true,
		IsActionsUsageAllowed:   true,
		IsOwnerSpammy:           true,
	}, nil)

	res := httptest.NewRecorder()

	request_url := fmt.Sprintf("/actions/billing/limits?tenantId=%s&productSku=%s", s.tenantId, "test-sku")
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetBillingDetails(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"IsActionsUsageAllowed\":true,\"IsActionsStorageAllowed\":true,\"IsOwnerSpammy\":true}\n", res.Body.String())
}
