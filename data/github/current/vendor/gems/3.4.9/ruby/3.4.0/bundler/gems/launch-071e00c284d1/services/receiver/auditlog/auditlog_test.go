package auditlog

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/github/launch/auth"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/utils/testutils"
)

func TestAuditLog(t *testing.T) {
	suite.Run(t, new(auditLogTestSuite))
}

type auditLogTestSuite struct {
	suite.Suite
	svc *Service

	hydro          *events.MockHydro
	azpResources   deployer.MockAzpResourcesLoader
	keyVaultClient *azp.MockKeyVaultClient
	verifier       *auth.MockVerifier
	twirpClient    *ghtwirp.MockClient
	log            testutils.RecordingLogger
}

func (s *auditLogTestSuite) SetupTest() {
	s.hydro = &events.MockHydro{}
	s.azpResources = deployer.MockAzpResourcesLoader{}
	s.keyVaultClient = &azp.MockKeyVaultClient{}
	s.verifier = &auth.MockVerifier{}
	s.twirpClient = &ghtwirp.MockClient{}
	s.log = testutils.NewRecordingLogger()

	s.svc = NewService(
		&Config{},
		observability.New(s.log.Logger, statter.NullStatter()),
		s.hydro,
		&s.azpResources,
		authVaultName,
		s.keyVaultClient,
		s.verifier,
		s.twirpClient)
}

func (s *auditLogTestSuite) TearDownTest() {
	s.hydro.AssertExpectations(s.T())
	s.azpResources.AssertExpectations(s.T())
	s.keyVaultClient.AssertExpectations(s.T())
	s.verifier.AssertExpectations(s.T())
	s.twirpClient.AssertExpectations(s.T())
}

func (s *auditLogTestSuite) handleExample(resp http.ResponseWriter, req *http.Request) {
	resp.Write([]byte("Hello World"))
	resp.WriteHeader(http.StatusOK)
}

func (s *auditLogTestSuite) handle() http.HandlerFunc {
	return s.svc.withThreshold(s.handleExample, "SomeErrorName")
}

func (s *auditLogTestSuite) TestErrorIfNoThresholdValud() {
	res := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/some/endpoint", bytes.NewReader([]byte("some-body")))

	s.handle()(res, req)

	body, err := io.ReadAll(res.Body)
	s.NoError(err)
	s.Contains(string(body), "Internal Server Error")
	s.Contains(s.log.String(), "couldn't find measurement struct in context: No threshold in context")
	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *auditLogTestSuite) TestHappyIfThresholdSet() {
	res := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/some/endpoint", bytes.NewReader([]byte("some-body")))

	// Setup the request properly
	req = req.WithContext(measurehttp.WithThresholdLogging(req.Context()))
	s.handle()(res, req)

	body, err := io.ReadAll(res.Body)
	s.NoError(err)
	s.Contains(string(body), "Hello World")
	s.NotContains(s.log.String(), "error")
	s.Equal(http.StatusOK, res.Code)
}
