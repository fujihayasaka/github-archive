package accountdetails

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

	"github.com/github/launch/auth"
	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/testutils"
)

var rawSignature = []byte("random_signature")

func TestAccountDetails(t *testing.T) {
	suite.Run(t, new(accountDetailsTestSuite))
}

const (
	httpsScheme = "https"
)

type accountDetailsTestSuite struct {
	suite.Suite
	svc          *Service
	db           deployer.MockAzpResourcesLoader
	twirpClient  *ghtwirp.MockClient
	log          testutils.RecordingLogger
	verifier     *auth.MockVerifier
	tenantId     string
	httpVerifier *hmac.HTTPVerifier
	authVerifier *auth.MockVerifier
	keyFetcher   *hmac.MockKeyFetcher
}

func (s *accountDetailsTestSuite) SetupTest() {
	s.tenantId = "test-tenant-id"
	s.authVerifier = &auth.MockVerifier{}
	s.keyFetcher = &hmac.MockKeyFetcher{}
	s.twirpClient = &ghtwirp.MockClient{}
	s.db = deployer.MockAzpResourcesLoader{}

	s.keyFetcher.On("GetHMACKeys", mock.Anything).Return([2]auth.Key{[]byte("hmacKey"), []byte("hmacKey")}, nil)
	obs := observability.New(testutils.NewRecordingLogger().Logger, statter.NullStatter())
	s.httpVerifier = hmac.NewHTTPVerifier(s.keyFetcher, obs, s.authVerifier, httpsScheme)
	s.svc = NewService(
		obs,
		&s.db,
		s.httpVerifier,
		s.twirpClient,
	)
}

func (s *accountDetailsTestSuite) getAuthorizationHeader() string {
	return fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString(rawSignature))
}

func (s *accountDetailsTestSuite) TestGettingAccountDetails_EmptyTenantId() {
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.On("GetByTenantID", mock.Anything, mock.Anything).Return(&deployer.AzpResource{
		EntityID: "test-entity-id",
		TenantID: s.tenantId,
	}, true, nil)

	s.twirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsAccountDetailsCheckEntityExists, mock.Anything).Return(false)
	s.twirpClient.On("GetAccountDetails", mock.Anything, mock.Anything).Return(&ghtwirp.AccountDetails{
		AccountType:    "Organization",
		IsBillingOwner: true,
	}, nil)

	res := httptest.NewRecorder()

	request_url := "/actions/account_details"
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetAccountDetails(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *accountDetailsTestSuite) TestGettingAccountDetails_UnknownTenantId() {
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.On("GetByTenantID", mock.Anything, mock.Anything).Return(nil, false, nil)

	s.twirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsAccountDetailsCheckEntityExists, mock.Anything).Return(false)
	s.twirpClient.On("GetAccountDetails", mock.Anything, mock.Anything).Return(nil, nil)

	res := httptest.NewRecorder()

	request_url := "/actions/account_details?tenantId=" + s.tenantId
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetAccountDetails(res, req)
	s.Equal(http.StatusNotFound, res.Code)
}

func (s *accountDetailsTestSuite) TestGettingAccountDetails_FailedGettingResponseFromDotcom() {
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.On("GetByTenantID", mock.Anything, mock.Anything).Return(&deployer.AzpResource{
		EntityID: "test-entity-id",
		TenantID: s.tenantId,
	}, true, nil)

	s.twirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsAccountDetailsCheckEntityExists, mock.Anything).Return(false)
	s.twirpClient.On("GetAccountDetails", mock.Anything, mock.Anything).Return(nil, errors.New("failed to get account details"))

	res := httptest.NewRecorder()

	request_url := "/actions/account_details?tenantId=" + s.tenantId
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetAccountDetails(res, req)
	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *accountDetailsTestSuite) TestGettingAccountDetails_GettingEntityNotFoundResponseFromDotcom() {
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.On("GetByTenantID", mock.Anything, mock.Anything).Return(&deployer.AzpResource{
		EntityID: "test-entity-id",
		TenantID: s.tenantId,
	}, true, nil)

	s.twirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsAccountDetailsCheckEntityExists, mock.Anything).Return(true)
	s.twirpClient.On("GetAccountDetails", mock.Anything, mock.Anything).Return(nil, twirp.NewError(twirp.NotFound, "entity does not exist"))

	res := httptest.NewRecorder()

	request_url := "/actions/account_details?tenantId=" + s.tenantId + "&checkEntityExists=true"
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetAccountDetails(res, req)
	s.Equal(http.StatusNotFound, res.Code)
}

func (s *accountDetailsTestSuite) TestGettingAccountDetails_GettingEntityNotFoundResponseFromDotcom_BackCompact() {
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.On("GetByTenantID", mock.Anything, mock.Anything).Return(&deployer.AzpResource{
		EntityID: "test-entity-id",
		TenantID: s.tenantId,
	}, true, nil)

	s.twirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsAccountDetailsCheckEntityExists, mock.Anything).Return(true)
	s.twirpClient.On("GetAccountDetails", mock.Anything, mock.Anything).Return(nil, twirp.NewError(twirp.NotFound, "entity does not exist"))

	res := httptest.NewRecorder()

	request_url := "/actions/account_details?tenantId=" + s.tenantId
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetAccountDetails(res, req)
	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *accountDetailsTestSuite) TestGettingAccountDetails() {
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.On("GetByTenantID", mock.Anything, mock.Anything).Return(&deployer.AzpResource{
		EntityID: "test-entity-id",
		TenantID: s.tenantId,
	}, true, nil)

	s.twirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsAccountDetailsCheckEntityExists, mock.Anything).Return(false)
	s.twirpClient.On("GetAccountDetails", mock.Anything, mock.Anything).Return(&ghtwirp.AccountDetails{
		AccountType:    "Organization",
		IsBillingOwner: true,
		CustomerID:     int64(10),
		TrustTier:      1,
	}, nil)

	res := httptest.NewRecorder()

	request_url := "/actions/account_details?tenantId=" + s.tenantId
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetAccountDetails(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"accountType\":\"Organization\",\"customerId\":10,\"isBillingOwner\":true,\"trustTier\":1}\n", res.Body.String())
}

func (s *accountDetailsTestSuite) TestGettingAccountDetailsNoCustomerID() {
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.On("GetByTenantID", mock.Anything, mock.Anything).Return(&deployer.AzpResource{
		EntityID: "test-entity-id",
		TenantID: s.tenantId,
	}, true, nil)

	s.twirpClient.On("IsFeatureEnabledForActor", mock.Anything, github.ActionsAccountDetailsCheckEntityExists, mock.Anything).Return(false)
	s.twirpClient.On("GetAccountDetails", mock.Anything, mock.Anything).Return(&ghtwirp.AccountDetails{
		AccountType:    "Organization",
		IsBillingOwner: true,
		TrustTier:      1,
	}, nil)

	res := httptest.NewRecorder()

	request_url := "/actions/account_details?tenantId=" + s.tenantId
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetAccountDetails(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"accountType\":\"Organization\",\"customerId\":0,\"isBillingOwner\":true,\"trustTier\":1}\n", res.Body.String())
}
