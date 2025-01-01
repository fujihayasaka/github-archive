package globalid

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/twitchtv/twirp"

	"github.com/stretchr/testify/suite"

	"github.com/github/launch/auth"
	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

const (
	httpsScheme = "https"
)

var rawSignature = []byte("random_signature")

func TestGlobalID(t *testing.T) {
	suite.Run(t, new(globalIDTestSuite))
}

type globalIDTestSuite struct {
	suite.Suite
	svc          *Service
	httpVerifier *hmac.HTTPVerifier
	authVerifier *auth.MockVerifier
	keyFetcher   *hmac.MockKeyFetcher
	twirpClient  *ghtwirp.MockClient
}

func (s *globalIDTestSuite) SetupTest() {
	s.authVerifier = &auth.MockVerifier{}
	s.keyFetcher = &hmac.MockKeyFetcher{}
	s.keyFetcher.On("GetHMACKeys", mock.Anything).Return([2]auth.Key{[]byte("hmacKey"), []byte("hmacKey")}, nil)
	obs := observability.New(testutils.NewRecordingLogger().Logger, statter.NullStatter())
	s.httpVerifier = hmac.NewHTTPVerifier(s.keyFetcher, obs, s.authVerifier, httpsScheme)
	s.twirpClient = &ghtwirp.MockClient{}

	s.svc = NewService(
		obs,
		s.twirpClient,
		s.httpVerifier,
	)
}

func (s *globalIDTestSuite) getAuthorizationHeader() string {
	return fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString(rawSignature))
}

func (s *globalIDTestSuite) getGlobalIDRequest(globalID string) *http.Request {
	body := bytes.NewReader([]byte("{}"))

	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("escaped_legacy_id", globalID)

	url := fmt.Sprintf("/actions/nextglobalid/%s", globalID)
	req := httptest.NewRequest(http.MethodGet, url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	ctx := measurehttp.WithThresholdLogging(req.Context())
	req = req.WithContext(ctx)

	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

func (s *globalIDTestSuite) getGlobalIDRequestNoAuth(globalID string) *http.Request {
	body := bytes.NewReader([]byte("{}"))

	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("escaped_legacy_id", globalID)

	url := fmt.Sprintf("/actions/nextglobalid/%s", globalID)
	req := httptest.NewRequest(http.MethodGet, url, body)

	ctx := measurehttp.WithThresholdLogging(req.Context())
	req = req.WithContext(ctx)

	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

func (s *globalIDTestSuite) getBulkGlobalIDRequest(globalID1, globalID2 string) *http.Request {
	body := fmt.Sprintf("{\"globalIds\":[\"%v\",\"%v\"]}", globalID1, globalID2)
	rctx := chi.NewRouteContext()

	url := "/actions/nextglobalids"
	req := httptest.NewRequest(http.MethodPost, url, bytes.NewReader([]byte(body)))
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	ctx := measurehttp.WithThresholdLogging(req.Context())
	req = req.WithContext(ctx)

	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

func (s *globalIDTestSuite) getBulkGlobalIDRequestNoAuth(globalID1, globalID2 string) *http.Request {
	body := fmt.Sprintf("{\"globalIds\":[\"%v\",\"%v\"]}", globalID1, globalID2)

	rctx := chi.NewRouteContext()

	url := "/actions/nextglobalids"
	req := httptest.NewRequest(http.MethodPost, url, bytes.NewReader([]byte(body)))

	ctx := measurehttp.WithThresholdLogging(req.Context())
	req = req.WithContext(ctx)

	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

func (s *globalIDTestSuite) TestGetNextGlobalIDStatusSuccessful() {
	res := httptest.NewRecorder()
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.twirpClient.On("GetNextGlobalID", mock.Anything, "test_global_id").Return(types.GlobalID("next_id"), nil)
	req := s.getGlobalIDRequest("test_global_id")
	s.svc.GetNextGlobalID(res, req)
	body, err := io.ReadAll(res.Body)
	s.NoError(err)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"nextGlobalId\":\"next_id\"}\n", string(body))
}

func (s *globalIDTestSuite) TestGetNextGlobalIDStatusNotFound() {
	res := httptest.NewRecorder()
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.twirpClient.On("GetNextGlobalID", mock.Anything, "test_global_id").Return(types.NilGlobalID,
		errors.Wrap(twirp.NotFoundError("not found"), "another error"))

	req := s.getGlobalIDRequest("test_global_id")
	s.svc.GetNextGlobalID(res, req)
	s.Equal(http.StatusNotFound, res.Code)
}

func (s *globalIDTestSuite) TestGetNextGlobalIDStatusInternal() {
	res := httptest.NewRecorder()
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)
	s.twirpClient.On("GetNextGlobalID", mock.Anything, "test_global_id").Return(types.NilGlobalID,
		errors.Wrap(twirp.InternalError("could not get next global id"), "another error"))

	req := s.getGlobalIDRequest("test_global_id")
	s.svc.GetNextGlobalID(res, req)
	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *globalIDTestSuite) TestGetNextGlobalIDStatusForbidden() {
	res := httptest.NewRecorder()
	// Test with no Authorization header
	req := s.getGlobalIDRequestNoAuth("test_global_id")
	s.svc.GetNextGlobalID(res, req)
	s.Equal(http.StatusForbidden, res.Code)
	// Test with invalid Authorization header
	req.Header.Add("Authorization", fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString([]byte("signature"))))
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(false)
	s.svc.GetNextGlobalID(res, req)
	s.Equal(http.StatusForbidden, res.Code)
}

func (s *globalIDTestSuite) TestGetBulkNextGlobalIDsAllFound() {
	res := httptest.NewRecorder()
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)

	legacyIds := []string{"test_global_id", "test_global_id2"}
	nextIds := map[string]types.GlobalID{
		"test_global_id":  types.GlobalID("next_id"),
		"test_global_id2": types.GlobalID("next_id2"),
	}
	s.twirpClient.On("GetNextGlobalIDs", mock.Anything, legacyIds).Return(nextIds, true, nil)

	req := s.getBulkGlobalIDRequest("test_global_id", "test_global_id2")
	s.svc.GetBulkNextGlobalIDs(res, req)
	body, err := io.ReadAll(res.Body)
	s.NoError(err)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"nextGlobalIdMap\":{\"test_global_id\":\"next_id\",\"test_global_id2\":\"next_id2\"},\"allIdsFound\":true}\n", string(body))
}

func (s *globalIDTestSuite) TestGetBulkNextGlobalIDsNoneFound() {
	res := httptest.NewRecorder()
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)

	legacyIds := []string{"test_global_id", "test_global_id2"}
	nextIds := map[string]types.GlobalID{}
	s.twirpClient.On("GetNextGlobalIDs", mock.Anything, legacyIds).Return(nextIds, false, nil)

	req := s.getBulkGlobalIDRequest("test_global_id", "test_global_id2")
	s.svc.GetBulkNextGlobalIDs(res, req)
	body, err := io.ReadAll(res.Body)
	s.NoError(err)
	s.Equal(http.StatusOK, res.Code)
	s.Equal("{\"nextGlobalIdMap\":{},\"allIdsFound\":false}\n", string(body))
}

func (s *globalIDTestSuite) TestGetBulkNextGlobalIDStatusInternal() {
	res := httptest.NewRecorder()
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(true)

	legacyIds := []string{"test_global_id", "test_global_id2"}
	s.twirpClient.On("GetNextGlobalIDs", mock.Anything, legacyIds).Return(nil, false,
		errors.Wrap(twirp.InternalError("could not get next global id"), "another error"))

	req := s.getBulkGlobalIDRequest("test_global_id", "test_global_id2")
	s.svc.GetBulkNextGlobalIDs(res, req)
	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *globalIDTestSuite) TestGetBulkNextGlobalIDStatusForbidden() {
	res := httptest.NewRecorder()

	// Test with no Authorization header
	req := s.getBulkGlobalIDRequestNoAuth("test_global_id", "test_global_id2")
	s.svc.GetBulkNextGlobalIDs(res, req)
	s.Equal(http.StatusForbidden, res.Code)

	// Test with invalid Authorization header
	req.Header.Add("Authorization", fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString([]byte("signature"))))
	s.authVerifier.On("Verify", mock.Anything, mock.Anything, mock.Anything).Return(false)
	s.svc.GetBulkNextGlobalIDs(res, req)
	s.Equal(http.StatusForbidden, res.Code)
}
