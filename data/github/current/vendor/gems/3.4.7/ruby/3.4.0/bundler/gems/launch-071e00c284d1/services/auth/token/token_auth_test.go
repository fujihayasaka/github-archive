package tokenauth

import (
	"context"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

type AuthSuite struct {
	suite.Suite
}

func TestAuth(t *testing.T) {
	suite.Run(t, new(AuthSuite))
}

func (s *AuthSuite) Test_LaunchReceiverScopesValid() {
	cases := []struct {
		name               string
		inWorkflowRunID    string
		inWorkflowJobRunID string
		inRunnerClaims     *runnerClaims
		expected           bool
	}{
		{
			name:               "valid scope",
			inWorkflowRunID:    "test_123",
			inWorkflowJobRunID: "test_456",
			inRunnerClaims: &runnerClaims{
				Scopes: "Actions.Runner:test_123:test_456",
			},
			expected: true,
		},
		{
			name:               "unauthorized scope",
			inWorkflowRunID:    "test_123",
			inWorkflowJobRunID: "test_456",
			inRunnerClaims: &runnerClaims{
				Scopes: "Actions.Runner:test_789:test_123",
			},
			expected: false,
		},
		{
			name:               "no scope exists",
			inWorkflowRunID:    "test_123",
			inWorkflowJobRunID: "test_456",
			inRunnerClaims:     nil,
			expected:           false,
		},
	}

	for _, c := range cases {
		s.Run(c.name, func() {
			client := &Client{}
			ctx := context.WithValue(context.Background(), contextKeyRunnerClaims, c.inRunnerClaims)
			actual := client.LaunchReceiverScopesValid(ctx, c.inWorkflowRunID, c.inWorkflowJobRunID)

			s.Equal(c.expected, actual)
		})
	}
}

func (s *AuthSuite) Test_GetRunnerTypeClaim() {
	cases := []struct {
		name           string
		inRunnerClaims *runnerClaims
		expected       string
	}{
		{
			name: "valid runner type",
			inRunnerClaims: &runnerClaims{
				RunnerType: "hosted",
			},
			expected: "hosted",
		},
		{
			name:           "no runner type",
			inRunnerClaims: nil,
			expected:       "",
		},
	}

	for _, c := range cases {
		s.Run(c.name, func() {
			client := &Client{}
			ctx := context.WithValue(context.Background(), contextKeyRunnerClaims, c.inRunnerClaims)
			actual := client.GetRunnerTypeClaim(ctx)

			s.Equal(c.expected, actual)
		})
	}
}

func (s *AuthSuite) Test_GetOwnerIDClaim() {
	cases := []struct {
		name           string
		inRunnerClaims *runnerClaims
		expected       types.GlobalID
	}{
		{
			name: "valid owner ID",
			inRunnerClaims: &runnerClaims{
				OwnerID: "test_123",
			},
			expected: types.GlobalID("test_123"),
		},
		{
			name:           "no owner ID",
			inRunnerClaims: nil,
			expected:       types.NilGlobalID,
		},
	}

	for _, c := range cases {
		s.Run(c.name, func() {
			client := &Client{}
			ctx := context.WithValue(context.Background(), contextKeyRunnerClaims, c.inRunnerClaims)
			actual := client.GetOwnerIDClaim(ctx)

			s.Equal(c.expected, actual)
		})
	}
}

func (s *AuthSuite) Test_ConvertX5TToKID() {
	cases := []struct {
		name        string
		x5t         string
		kid         string
		expectedErr error
	}{
		{
			name:        "happy path",
			x5t:         "t3M6ZePqXwZkpBJ5rvMs2EwvN5A",
			kid:         "B7733A65E3EA5F0664A41279AEF32CD84C2F3790",
			expectedErr: nil,
		},
		{
			name:        "invalid x5t",
			x5t:         "YW55ICsgb2xkICYgZGF0YQ==",
			kid:         "",
			expectedErr: base64.CorruptInputError(22),
		},
	}

	for _, c := range cases {
		s.Run(c.name, func() {
			actualKID, err := convertX5TToKID(c.x5t)
			if c.expectedErr != nil {
				s.Equal(c.expectedErr, err)
				return
			}

			s.NoError(err)

			s.Equal(actualKID, c.kid)
		})
	}
}

func (s *AuthSuite) Test_AuthenticationMiddleware() {
	var (
		testRunID   = uuid.NewString()
		testJobID   = uuid.NewString()
		testJobName = "test-job"
	)

	log := testutils.NewRecordingLogger()
	obs := observability.New(log.Logger, statter.NullStatter())
	jwksServer := testutils.NewJWKSServer(s.T())
	defer jwksServer.Close()

	authClient, err := New(
		context.Background(),
		&Config{
			JWKSURL:                     jwksServer.JWKSURL(),
			MultiTenantEnterpriseIssuer: jwksServer.Server.URL,
		}, obs)
	s.NoError(err)

	tests := []struct {
		name          string
		isMultiTenant bool
	}{
		{
			name:          "test auth middleware in multi-tenant mode",
			isMultiTenant: true,
		},
		{
			name:          "test auth middleware in dotcom mode",
			isMultiTenant: false,
		},
	}

	for _, tt := range tests {
		s.Run(tt.name, func() {
			issuer := ""
			if tt.isMultiTenant {
				issuer = "https://token.actions.staffship-01.ghe.com"
				testutils.SetIsMultiTenant(s.T(), tt.isMultiTenant)
			}
			testToken := jwksServer.MintToken(testRunID, testJobID, testJobName, issuer)

			tc := []struct {
				name    string
				setup   func(req *http.Request)
				handler func(w http.ResponseWriter, r *http.Request)
				expect  func(resp *http.Response)
			}{
				{
					name: "no token",
					setup: func(_ *http.Request) {
					},
					expect: func(resp *http.Response) {
						s.Equal(http.StatusUnauthorized, resp.StatusCode)
						s.Contains(log.String(), "unable to extract token from request")
					},
				},
				{
					name: "bad token",
					setup: func(req *http.Request) {
						req.Header.Set("Authorization", "Bearer garbage")
					},
					expect: func(resp *http.Response) {
						s.Equal(http.StatusUnauthorized, resp.StatusCode)
						s.Contains(log.String(), "unable to validate token")
					},
				},
				{
					name: "valid token",
					setup: func(req *http.Request) {
						req.Header.Set("Authorization", "Bearer "+testToken)
					},
					expect: func(resp *http.Response) {
						s.Equal(http.StatusOK, resp.StatusCode)
					},
				},
				{
					name: "adds claims to context",
					setup: func(req *http.Request) {
						req.Header.Set("Authorization", "Bearer "+testToken)
					},
					handler: func(w http.ResponseWriter, r *http.Request) {
						ctx := r.Context()

						launchScopeValid := authClient.LaunchReceiverScopesValid(ctx, testRunID, testJobID)
						s.True(launchScopeValid, "launch scopes should be valid")

						orchID := ctxstash.From(ctx).Correlations().VSS.OrchestrationID
						s.Equal(fmt.Sprintf("%s.%s.__default", testRunID, testJobName), orchID)

						w.WriteHeader(http.StatusOK)
					},
					expect: func(resp *http.Response) {
						s.Equal(http.StatusOK, resp.StatusCode)
					},
				},
			}

			for _, c := range tc {
				s.Run(c.name, func() {
					if c.handler == nil {
						c.handler = func(w http.ResponseWriter, _ *http.Request) {
							w.WriteHeader(http.StatusOK)
						}
					}

					log.Reset()
					authMiddleware := authClient.AuthenticationMiddleware((log.Logger))
					httpServer := httptest.NewServer(authMiddleware(http.HandlerFunc(c.handler)))
					defer httpServer.Close()

					req, err := http.NewRequest(http.MethodGet, httpServer.URL, nil)
					s.NoError(err)

					c.setup(req)

					resp, err := httpServer.Client().Do(req)
					s.NoError(err)
					if resp.Body != nil {
						defer resp.Body.Close()
					}

					c.expect(resp)
				})
			}
		})
	}
}
