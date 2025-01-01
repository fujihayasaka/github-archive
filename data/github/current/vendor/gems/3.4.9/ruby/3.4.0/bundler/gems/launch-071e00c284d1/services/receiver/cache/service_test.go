package cache

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/mock"

	"github.com/stretchr/testify/suite"

	"github.com/github/launch/auth"
	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/testutils"
)

const (
	httpsScheme = "https"
)

func TestCache(t *testing.T) {
	suite.Run(t, new(cacheTestSuite))
}

type cacheTestSuite struct {
	suite.Suite
	svc          *Service
	hydro        *events.MockHydro
	httpVerifier *hmac.HTTPVerifier
	authVerifier *auth.MockVerifier
	keyFetcher   *hmac.MockKeyFetcher
	db           *deployer.MockAzpResourcesLoader
}

func (s *cacheTestSuite) SetupTest() {
	s.hydro = events.NewMockHydro(s.T())
	s.authVerifier = auth.NewMockVerifier(s.T())
	s.keyFetcher = hmac.NewMockKeyFetcher(s.T())
	s.keyFetcher.On("GetHMACKeys", mock.Anything).Return([2]auth.Key{[]byte("hmacKey"), []byte("hmacKey")}, nil).Maybe()
	s.db = deployer.NewMockAzpResourcesLoader(s.T())
	obs := observability.New(testutils.NewRecordingLogger().Logger, statter.NullStatter())
	s.httpVerifier = hmac.NewHTTPVerifier(s.keyFetcher, obs, s.authVerifier, httpsScheme)
	s.svc = NewService(
		obs,
		s.hydro,
		s.httpVerifier,
		s.db,
	)
}

func (s *cacheTestSuite) TestUpdateCacheStatusSuccessful() {
	res := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPatch, updateCacheUsageCallbackRoute, bytes.NewReader([]byte(`{"HostId":"test_host", "TotalSizeInBytes":1024 ,"TotalCachesCount":2}`)))
	req.Header.Add("Authorization", fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString([]byte("signature"))))
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.On("GetByTenantName", mock.Anything, "test_host").Return(&deployer.AzpResourceByName{
		EntityID: "R_kgAB",
	}, true, nil)
	s.hydro.On("Emit", mock.Anything)
	s.svc.UpdateCacheUsage(res, req)
	_, err := io.ReadAll(res.Body)
	s.NoError(err)
	s.Equal(http.StatusAccepted, res.Code)
}

func (s *cacheTestSuite) TestUpdateCacheStatusHostIsNotRepository() {
	res := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPatch, updateCacheUsageCallbackRoute, bytes.NewReader([]byte(`{"HostId":"test_host", "TotalSizeInBytes":1024 ,"TotalCachesCount":2}`)))
	req.Header.Add("Authorization", fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString([]byte("signature"))))
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.db.On("GetByTenantName", mock.Anything, "test_host").Return(&deployer.AzpResourceByName{
		EntityID: "E_kgAB",
	}, true, nil)
	s.svc.UpdateCacheUsage(res, req)
	_, err := io.ReadAll(res.Body)
	s.NoError(err)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *cacheTestSuite) TestUpdateCacheStatusForbidden() {
	res := httptest.NewRecorder()
	// Test with no Authorization header
	req := httptest.NewRequest(http.MethodPatch, updateCacheUsageCallbackRoute, bytes.NewReader([]byte("{}")))
	s.svc.UpdateCacheUsage(res, req)
	s.Equal(http.StatusForbidden, res.Code)
	// Test with invalid Authorization header
	req.Header.Add("Authorization", fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString([]byte("signature"))))
	s.svc.UpdateCacheUsage(res, req)
	s.Equal(http.StatusForbidden, res.Code)
}

func (s *cacheTestSuite) TestUpdateCacheBadRequest() {
	res := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPatch, updateCacheUsageCallbackRoute, bytes.NewReader([]byte(``)))
	req.Header.Add("Authorization", fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString([]byte("signature"))))

	// Test with empty body
	s.svc.UpdateCacheUsage(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
	// Test with Invalid body
	req = httptest.NewRequest(http.MethodPatch, updateCacheUsageCallbackRoute, bytes.NewReader([]byte(`{"HostId":"test_host", "TotalSizeInBytes":"non numeric string" ,"TotalCachesCount":2}`)))
	s.svc.UpdateCacheUsage(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}
