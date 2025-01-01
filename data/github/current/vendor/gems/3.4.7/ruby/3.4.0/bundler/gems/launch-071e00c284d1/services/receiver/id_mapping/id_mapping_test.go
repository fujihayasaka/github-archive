package idmapping

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/auth"
	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

var rawSignature = []byte("random_signature")

func TestIDMapping(t *testing.T) {
	suite.Run(t, new(idMappingTestSuite))
}

const (
	httpsScheme = "https"
)

type idMappingTestSuite struct {
	suite.Suite
	svc          *Service
	db           deployer.MockAzpResourcesLoader
	log          testutils.RecordingLogger
	verifier     *auth.MockVerifier
	httpVerifier *hmac.HTTPVerifier
	authVerifier *auth.MockVerifier
	keyFetcher   *hmac.MockKeyFetcher
}

func (s *idMappingTestSuite) SetupTest() {
	s.authVerifier = &auth.MockVerifier{}
	s.keyFetcher = &hmac.MockKeyFetcher{}

	s.keyFetcher.On("GetHMACKeys", mock.Anything).Return([2]auth.Key{[]byte("hmacKey"), []byte("hmacKey")}, nil)
	obs := observability.New(testutils.NewRecordingLogger().Logger, statter.NullStatter())
	s.httpVerifier = hmac.NewHTTPVerifier(s.keyFetcher, obs, s.authVerifier, httpsScheme)
	s.svc = NewService(
		obs,
		&s.db,
		s.httpVerifier,
	)
}

func (s *idMappingTestSuite) getAuthorizationHeader() string {
	return fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString(rawSignature))
}

func (s *idMappingTestSuite) TestHandleGetIDMapping_ByTenantID() {
	azpResource := &deployer.AzpResource{
		EntityID:    "test-global-id",
		TenantID:    "test-vssf-id",
		Environment: "lab",
	}
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.On("GetByTenantID", mock.Anything, mock.Anything).Return(azpResource, true, nil)

	res := httptest.NewRecorder()

	request_url := "/actions/id_mapping?tenantId=test-vssf-id"
	body := bytes.NewReader([]byte(""))
	req := httptest.NewRequest(http.MethodGet, request_url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	s.svc.HandleGetIDMapping(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"tenantId\":\"test-vssf-id\",\"entityId\":\"test-global-id\",\"environment\":\"lab\"}\n", res.Body.String())
}

func (s *idMappingTestSuite) TestHandleGetIDMapping_ByEntityID() {
	var tests = []struct {
		name                 string
		environment          string
		url                  string
		pipelinesScaleUnitId string
	}{
		{"default to production environment", launchconfig.ProductionAppEnv.String(), "/actions/id_mapping?entityId=O_kgAF", "6bfa0b85-0342-b826-1c9f-bc636d8425af"},
		{"honor environment query parameter", "foo", "/actions/id_mapping?entityId=O_kgAF&environment=foo", "6bfa0b85-0342-b826-1c9f-bc636d8425af"},
		{"empty pipelines scale unit id", "bar", "/actions/id_mapping?entityId=O_kgAF&environment=bar", "00000000-0000-0000-0000-000000000000"},
	}
	for _, st := range tests {
		s.Run(st.name, func() {
			pipelinesScaleUnitId, _ := types.ParseScaleUnitID(st.pipelinesScaleUnitId)
			tenantInfo := &deployer.TenantInfo{
				TenantName:           "test-vssf-name",
				TenantID:             "test-vssf-id",
				PipelinesScaleUnitID: pipelinesScaleUnitId,
			}
			s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
			s.db.On("GetByGlobalID", mock.Anything, mock.Anything, st.environment).Return(tenantInfo, true, nil)

			res := httptest.NewRecorder()

			request_url := st.url
			body := bytes.NewReader([]byte(""))
			req := httptest.NewRequest(http.MethodGet, request_url, body)
			req.Header.Set("Authorization", s.getAuthorizationHeader())

			s.svc.HandleGetIDMapping(res, req)
			s.Equal(http.StatusOK, res.Code)
			s.Equal(fmt.Sprintf("{\"tenantId\":\"test-vssf-id\",\"entityId\":\"O_kgAF\",\"environment\":\"%s\",\"pipelinesScaleUnitId\":\"%s\"}\n", st.environment, pipelinesScaleUnitId), res.Body.String())
		})
	}
}
