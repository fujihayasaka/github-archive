package twirp

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/middleware/headers"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/golang-jwt/jwt/v4"
	"github.com/stretchr/testify/suite"
)

func TestValidateAuthHandler(t *testing.T) {
	suite.Run(t, new(ValidateAuthHandlerTestSuite))
}

type ValidateAuthHandlerTestSuite struct {
	suite.Suite
}

type validateAuthHandlerTestCase struct {
	testName         string
	hmacAuthAllowed  bool
	hmacAuthEnabled  bool
	hmacKey          string
	hmacVerifyKeys   string
	vssfAuthAllowed  bool
	vssfAuthEnabled  bool
	vssfToken        string
	vssfAllowedToken string
	expectedError    string
}

type mockVssfService struct {
	allowedToken string
}

func (c *mockVssfService) ValidateToken(tokenString string) (*jwt.RegisteredClaims, error) {
	if tokenString == c.allowedToken {
		return nil, nil
	}

	return nil, fmt.Errorf("invalid token")
}

func (s *ValidateAuthHandlerTestSuite) buildRequest(hmacKey string, vssfToken string) *http.Request {
	req, err := http.NewRequest("GET", "/test-url", nil)
	s.Require().NoError(err)

	if hmacKey != "" {
		req.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(hmacKey).String())
	}
	if vssfToken != "" {
		req.Header.Set("Authorization", vssfToken)
	}

	return req
}

func (s *ValidateAuthHandlerTestSuite) validateHandler(test validateAuthHandlerTestCase) {
	s.Run(test.testName, func() {
		authConfig := &Config{
			HmacAuthEnabled: test.hmacAuthEnabled,
			VssfAuthEnabled: test.vssfAuthEnabled,
		}
		if test.hmacVerifyKeys != "" {
			authConfig.HmacAuthVerifyKeys = strings.Split(test.hmacVerifyKeys, " ")
		}
		vssfService := &mockVssfService{allowedToken: test.vssfAllowedToken}
		logger := telemetry.NewReportingLogger(log.NewNullLogger(), nil, nil)
		okHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		})

		respRecorder := httptest.NewRecorder()
		validateAuthHandler(okHandler, test.hmacAuthAllowed, test.vssfAuthAllowed, authConfig, vssfService, logger).ServeHTTP(respRecorder, s.buildRequest(test.hmacKey, test.vssfToken))
		if test.expectedError == "" {
			s.Assert().Equal(200, respRecorder.Code)
			s.Assert().Empty(respRecorder.Body)
		} else {
			s.Assert().Equal(401, respRecorder.Code)
			s.Assert().Contains(respRecorder.Body.String(), test.expectedError)
		}
	})
}

func (s *ValidateAuthHandlerTestSuite) Test_OnlyHmacAllowed() {
	testCases := []validateAuthHandlerTestCase{
		{
			testName:        "no HMAC verify keys defined",
			hmacAuthEnabled: true,
			hmacKey:         "",
			hmacVerifyKeys:  "",
			expectedError:   "no HMAC verify keys are defined",
		},
		{
			testName:        "no Request-HMAC provided",
			hmacAuthEnabled: true,
			hmacKey:         "",
			hmacVerifyKeys:  "hmac-test",
			expectedError:   "no Request-HMAC provided",
		},
		{
			testName:        "invalid hmac",
			hmacAuthEnabled: true,
			hmacKey:         "fake-hmac",
			hmacVerifyKeys:  "hmac-test",
			expectedError:   "is invalid",
		},
		{
			testName:        "valid hmac",
			hmacAuthEnabled: true,
			hmacKey:         "hmac-test",
			hmacVerifyKeys:  "hmac-test",
			expectedError:   "",
		},
		{
			testName:        "multiple verify keys",
			hmacAuthEnabled: true,
			hmacKey:         "hmac-test-2",
			hmacVerifyKeys:  "hmac-test-1 hmac-test-2",
			expectedError:   "",
		},
		{
			testName:        "auth disabled",
			hmacAuthEnabled: false,
			hmacKey:         "",
			hmacVerifyKeys:  "",
			expectedError:   "",
		},
	}

	for _, test := range testCases {
		test.hmacAuthAllowed = true
		test.vssfAuthAllowed = false
		test.vssfAuthEnabled = false
		s.validateHandler(test)
	}
}

func (s *ValidateAuthHandlerTestSuite) Test_OnlyVssfAllowed() {
	testCases := []validateAuthHandlerTestCase{
		{
			testName:         "no token provided",
			vssfAuthEnabled:  true,
			vssfToken:        "",
			vssfAllowedToken: "my-token-",
			expectedError:    "no bearer token provided",
		},
		{
			testName:         "invalid token",
			vssfAuthEnabled:  true,
			vssfToken:        "my-token-1",
			vssfAllowedToken: "my-token-2",
			expectedError:    "failed to validate bearer token: invalid token",
		},
		{
			testName:         "valid token",
			vssfAuthEnabled:  true,
			vssfToken:        "my-token",
			vssfAllowedToken: "my-token",
			expectedError:    "",
		},
		{
			testName:        "auth disabled",
			vssfAuthEnabled: false,
			vssfToken:       "",
			expectedError:   "",
		},
	}

	for _, test := range testCases {
		test.hmacAuthAllowed = false
		test.hmacAuthEnabled = false
		test.vssfAuthAllowed = true
		s.validateHandler(test)
	}
}

func (s *ValidateAuthHandlerTestSuite) Test_HmacAndVssfAllowed() {
	testCases := []validateAuthHandlerTestCase{
		{
			testName:         "auth passes because HMAC auth is disabled",
			hmacAuthEnabled:  false,
			vssfAuthEnabled:  true,
			hmacKey:          "",
			hmacVerifyKeys:   "ims-hmac",
			vssfToken:        "",
			vssfAllowedToken: "my-token",
			expectedError:    "",
		},
		{
			testName:         "success because Vssf auth is disabled",
			hmacAuthEnabled:  true,
			vssfAuthEnabled:  false,
			hmacKey:          "",
			hmacVerifyKeys:   "ims-hmac",
			vssfToken:        "",
			vssfAllowedToken: "my-token",
			expectedError:    "",
		},
		{
			testName:         "success because both auths are disabled",
			hmacAuthEnabled:  false,
			vssfAuthEnabled:  false,
			hmacKey:          "",
			hmacVerifyKeys:   "ims-hmac",
			vssfToken:        "",
			vssfAllowedToken: "my-token",
			expectedError:    "",
		},
		{
			testName:         "success because HMAC is valid",
			hmacAuthEnabled:  true,
			vssfAuthEnabled:  true,
			hmacKey:          "ims-hmac",
			hmacVerifyKeys:   "ims-hmac",
			vssfToken:        "",
			vssfAllowedToken: "my-token",
			expectedError:    "",
		},
		{
			testName:         "success because Vssf token is valid",
			hmacAuthEnabled:  true,
			vssfAuthEnabled:  true,
			hmacKey:          "",
			hmacVerifyKeys:   "ims-hmac",
			vssfToken:        "my-token",
			vssfAllowedToken: "my-token",
			expectedError:    "",
		},
		{
			testName:         "success because both auths are valid",
			hmacAuthEnabled:  true,
			vssfAuthEnabled:  true,
			hmacKey:          "ims-hmac",
			hmacVerifyKeys:   "ims-hmac",
			vssfToken:        "my-token",
			vssfAllowedToken: "my-token",
			expectedError:    "",
		},
		{
			testName:         "success because HMAC is valid and vssf is invalid",
			hmacAuthEnabled:  true,
			vssfAuthEnabled:  true,
			hmacKey:          "ims-hmac-1",
			hmacVerifyKeys:   "ims-hmac-1",
			vssfToken:        "my-token-2",
			vssfAllowedToken: "my-token-1",
			expectedError:    "",
		},
		{
			testName:         "success because HMAC is invalid and vssf is valid",
			hmacAuthEnabled:  true,
			vssfAuthEnabled:  true,
			hmacKey:          "ims-hmac-1",
			hmacVerifyKeys:   "ims-hmac-2",
			vssfToken:        "my-token-1",
			vssfAllowedToken: "my-token-1",
			expectedError:    "",
		},
		{
			testName:         "fail because both auths are not provided",
			hmacAuthEnabled:  true,
			vssfAuthEnabled:  true,
			hmacKey:          "",
			hmacVerifyKeys:   "ims-hmac",
			vssfToken:        "",
			vssfAllowedToken: "my-token",
			expectedError:    "no Request-HMAC provided\\nno bearer token provided",
		},
		{
			testName:         "fail because HMAC is invalid and Vssf is not provided",
			hmacAuthEnabled:  true,
			vssfAuthEnabled:  true,
			hmacKey:          "ims-hmac-2",
			hmacVerifyKeys:   "ims-hmac-1",
			vssfToken:        "",
			vssfAllowedToken: "my-token-1",
			expectedError:    "is invalid\\nno bearer token provided",
		},
		{
			testName:         "fail because HMAC is not provided and Vssf is invalid",
			hmacAuthEnabled:  true,
			vssfAuthEnabled:  true,
			hmacKey:          "",
			hmacVerifyKeys:   "ims-hmac-1",
			vssfToken:        "my-token-2",
			vssfAllowedToken: "my-token-1",
			expectedError:    "no Request-HMAC provided\\nfailed to validate bearer token: invalid token",
		},
		{
			testName:         "fail because both auths are invalid",
			hmacAuthEnabled:  true,
			vssfAuthEnabled:  true,
			hmacKey:          "ims-hmac-2",
			hmacVerifyKeys:   "ims-hmac-1",
			vssfToken:        "my-token-2",
			vssfAllowedToken: "my-token-1",
			expectedError:    "is invalid\\nfailed to validate bearer token: invalid token",
		},
	}

	for _, test := range testCases {
		test.hmacAuthAllowed = true
		test.vssfAuthAllowed = true
		s.validateHandler(test)
	}
}

func (s *ValidateAuthHandlerTestSuite) Test_NoAuthAllowed() {
	testCases := []validateAuthHandlerTestCase{
		{
			testName:        "both auth enabled",
			hmacAuthEnabled: true,
			vssfAuthEnabled: true,
			expectedError:   "unknown error",
		},
		{
			testName:        "both auth disabled",
			hmacAuthEnabled: false,
			vssfAuthEnabled: false,
			expectedError:   "unknown error",
		},
	}

	for _, test := range testCases {
		test.hmacAuthAllowed = false
		test.vssfAuthAllowed = false
		s.validateHandler(test)
	}
}
