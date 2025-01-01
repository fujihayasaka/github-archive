package tokens

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/facebookgo/clock"
	"github.com/golang-jwt/jwt/v4"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/cache/cachemem"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/pkg/launchhttp/httpmock"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/testutils"
)

const (
	appID          = 1
	installationID = 1
	repositoryID   = int64(1)
	pullRequest    = 42
	ownerID        = int64(3)
)

var (
	env                = launchconfig.AppEnv("test")
	repositoryGlobalID = types.GlobalID(testutils.EncodeGlobalID("Repository", repositoryID))
	appPrivateKey, _   = os.ReadFile("../fixtures/test.key")
	repoNWO            = types.RepositoryFullName{Owner: "owner", Name: "repo"}
)

func (s *TokenTestSuite) fakeActorFFChecker(ctx context.Context, flag string, globalID types.GlobalID) bool {
	return false
}

func (s *TokenTestSuite) fakeGlobalFFChecker(ctx context.Context, flag string) bool {
	return false
}

func (s *TokenTestSuite) fakeGetRepositoryOwnerID(ctx context.Context, repoID int64, useCache bool) (int64, error) {
	return ownerID, nil
}

// Default permissions for RO or RW tokens
var defaultReadPermissions = *NewInstallationPermissions(ReadPermissions)
var defaultWritePermissions = *NewInstallationPermissions(WritePermissions)

func (s *TokenTestSuite) writeToken() *AccessToken {
	return s.buildToken("write-token", defaultWritePermissions, 60, nil)
}

func (s *TokenTestSuite) readToken() *AccessToken {
	return s.buildToken("read-token", defaultReadPermissions, 60, nil)
}

func (s *TokenTestSuite) actionReadToken(validAfter *time.Time) *AccessToken {
	readActionPermissions := InstallationPermissions{
		Contents: ReadAccess,
		Metadata: ReadAccess,
		Actions:  ReadAccess,
	}

	return s.buildToken("read-action-token", readActionPermissions, 60, validAfter)
}

func (s *TokenTestSuite) buildToken(token string, perms InstallationPermissions, mins int64, validAfter *time.Time) *AccessToken {
	return &AccessToken{Token: token, Permissions: perms, Expiry: s.clock.Now().UTC().Add(time.Duration(mins) * time.Minute), ValidAfter: validAfter}
}

func installationTokenJSON(installationToken *AccessToken) string {
	if installationToken.ValidAfter == nil {
		return fmt.Sprintf(`{"token":"%s","expires_at":"%s"}`, installationToken.Token, installationToken.Expiry.Format(time.RFC3339))
	}

	validAfter := *installationToken.ValidAfter
	return fmt.Sprintf(`{"token":"%s","expires_at":"%s","valid_after":"%s"}`, installationToken.Token, installationToken.Expiry.Format(time.RFC3339), validAfter.Format(time.RFC3339Nano))
}

type TokenTestSuite struct {
	suite.Suite

	router *testRouter
	clock  *clock.Mock

	ts *httptest.Server
}

func (s *TokenTestSuite) newLaunchCache() launchcache.GitHubCache {
	return launchcache.NewNamespacedCache(cachemem.NewExpiringCache(1<<20), observability.NewTestObservability()).GitHub()
}

// option allows modifying the service in tests
type option func(*service)

// withEnabledFlags returns an option that enables the given flags
// Usage:
// service := s.newService(withEnabledFlags(c.enabledFlags))
func withEnabledFlags(flags []string) func(*service) {
	flagEnabled := func(flag string) bool {
		for _, f := range flags {
			if f == flag {
				return true
			}
		}
		return false
	}

	return func(s *service) {
		s.actorFFChecker = func(_ context.Context, flag string, _ types.GlobalID) bool {
			return flagEnabled(flag)
		}
		s.globalFFChecker = func(_ context.Context, flag string) bool {
			return flagEnabled(flag)
		}
	}
}

func (s *TokenTestSuite) newService(options ...option) *service {
	s.ts = httptest.NewServer(s.router.Route(s.T()))
	url, err := url.Parse(s.ts.URL)
	require.NoError(s.T(), err)
	service, err := newService(env,
		observability.NewNullObservability(),
		url,
		appID,
		appPrivateKey,
		s.clock,
		testutils.NewNoopBreaker(),
		httpclient.New(http.DefaultClient),
		s.newLaunchCache(),
		s.fakeActorFFChecker,
		s.fakeGlobalFFChecker,
		s.fakeGetRepositoryOwnerID,
		httpclient.NewClientHooks(),
		false,
	)

	for _, opt := range options {
		opt(service)
	}

	s.Require().NoError(err)
	s.Require().NotNil(service)
	return service
}

func TestTokenTestSuite(t *testing.T) {
	suite.Run(t, new(TokenTestSuite))
}

func (s *TokenTestSuite) SetupTest() {
	testClock := clock.NewMock()
	router := NewTestRouter()
	s.router = router
	s.clock = testClock
}

func (s *TokenTestSuite) TearDownTest() {
	if s.ts != nil {
		s.ts.Close()
	}
}

func (s *TokenTestSuite) TestNewService() {
	obs := observability.NewNullObservability()
	_, err := NewService(
		env,
		obs,
		&url.URL{},
		appID,
		[]byte("garble"),
		testutils.NewNoopBreaker(),
		httpclient.New(http.DefaultClient),
		s.newLaunchCache(),
		s.fakeActorFFChecker,
		s.fakeGlobalFFChecker,
		func(ctx context.Context, repoID int64, useCache bool) (int64, error) { return 0, nil },
		httpclient.NewClientHooks(),
		false,
	)
	s.Equal(jwt.ErrKeyMustBePEMEncoded, errors.Cause(err))

	service, err := newService(
		env,
		observability.NewNullObservability(),
		&url.URL{},
		appID,
		appPrivateKey,
		s.clock,
		testutils.NewNoopBreaker(),
		httpclient.New(http.DefaultClient),
		s.newLaunchCache(),
		s.fakeActorFFChecker,
		s.fakeGlobalFFChecker,
		func(ctx context.Context, repoID int64, useCache bool) (int64, error) { return 0, nil },
		httpclient.NewClientHooks(),
		false,
	)
	s.NoError(err)
	s.NotNil(service)
}

type ownerIDCall struct {
	ownerID  int64
	useCache bool
}

func (s *TokenTestSuite) TestSiteScopedTokenForRepositoryOwner() {
	testOwnerID := ownerID
	intitialOwnerID := int64(5678)

	writePermissions := NewInstallationPermissions(WritePermissions)
	cases := []struct {
		description   string
		ownerID       int64
		useCache      bool
		perms         *InstallationPermissions
		extendedPerms *ExtendedPermissions
		ownerIDCalls  []ownerIDCall
		response      func(w http.ResponseWriter, r *http.Request)
		retryResponse func(w http.ResponseWriter, r *http.Request)
		expectError   bool
	}{
		{
			description: "basic write permissions",
			ownerID:     testOwnerID,
			useCache:    false,
			perms:       writePermissions,
			// Owner ID is set, so we should not be fetching it
			ownerIDCalls: []ownerIDCall{},
			response: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      testOwnerID,
					RepositoryIDs: []int64{},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))
				_, _ = fmt.Fprintln(w, installationTokenJSON(s.writeToken()))
			},
		},
		{
			description: "owner ID not set",
			ownerID:     0,
			useCache:    false,
			perms:       writePermissions,
			// Owner ID is fetched once with caching enabled
			ownerIDCalls: []ownerIDCall{{testOwnerID, true}},
			response: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      testOwnerID,
					RepositoryIDs: []int64{},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))
				_, _ = fmt.Fprintln(w, installationTokenJSON(s.writeToken()))
			},
		},
		{
			description: "retry and fetch owner ID on 404",
			ownerID:     intitialOwnerID,
			useCache:    false,
			perms:       writePermissions,
			// Owner ID is fetched with caching disabled
			ownerIDCalls: []ownerIDCall{{testOwnerID, false}},
			response: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      intitialOwnerID,
					RepositoryIDs: []int64{},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))

				// 404 for the initial request
				http.NotFound(w, r)
			},
			retryResponse: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      testOwnerID, // New owner ID fetched
					RepositoryIDs: []int64{},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))
				_, _ = fmt.Fprintln(w, installationTokenJSON(s.writeToken()))
			},
		},
		{
			description: "retry on 422 when owner ID is not set",
			ownerID:     0,
			useCache:    false,
			perms:       writePermissions,
			// Owner ID is fetched initially with caching disabled, then with caching enabled on fallback
			ownerIDCalls: []ownerIDCall{{intitialOwnerID, true}, {testOwnerID, false}},
			response: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      intitialOwnerID,
					RepositoryIDs: []int64{},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))

				// 422 for the initial request
				http.Error(w, "422 Unprocessable Content", http.StatusUnprocessableEntity)
			},
			retryResponse: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      testOwnerID, // New owner ID fetched
					RepositoryIDs: []int64{},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))
				_, _ = fmt.Fprintln(w, installationTokenJSON(s.writeToken()))
			},
		},
	}

	for _, c := range cases {
		s.Run(c.description, func() {
			path := "/app/global/access_tokens"
			s.router.SetResponses(path, c.response)
			if c.retryResponse != nil {
				s.router.SetResponses(path, c.response, c.retryResponse)
			}

			ownerIDCallCount := 0
			getRepositoryOwnerID := func(_ context.Context, repoID int64, useCache bool) (int64, error) {
				s.Equal(repositoryID, repoID, "unexpected repository ID in getRepositoryOwnerID call")

				ownerIDCallCount++
				if len(c.ownerIDCalls) < ownerIDCallCount {
					s.FailNowf("unexpected getRepositoryOwnerID call", "expected %d calls", len(c.ownerIDCalls))
				}

				callInfo := c.ownerIDCalls[ownerIDCallCount-1]

				s.Equal(callInfo.useCache, useCache, "unexpected useCache in getRepositoryOwnerID call")

				return callInfo.ownerID, nil
			}

			var flags []string
			service := s.newService(withEnabledFlags(flags), func(s *service) {
				s.getRepositoryOwnerID = getRepositoryOwnerID
			})

			ctx := context.Background()

			token, err := service.SiteScopedTokenForRepositoryOwner(ctx, repositoryGlobalID, c.ownerID, c.useCache, c.perms, c.extendedPerms)

			expectedCalls := 1
			if c.retryResponse != nil {
				expectedCalls = 2
			}

			s.Equal(expectedCalls, s.router.PathRequests(path), "expected %d calls to %q", expectedCalls, path)

			if c.expectError {
				s.Error(err)
				s.Nil(token)
			} else {
				s.NoError(err)
				s.NotNil(token)
			}
		})
	}
}

func (s *TokenTestSuite) TestSiteScopedTokenForRepository() {
	testOwnerID := ownerID
	intitialOwnerID := int64(5678)

	writePermissions := NewInstallationPermissions(WritePermissions)
	testExtendedPerms := &ExtendedPermissions{
		PerPullRequestPermissions: &PerPullRequestPermissions{
			Number: 123,
			Permissions: PullRequestInstallationPermissions{
				Sarifs: WriteAccess,
			},
		},
		PerWorkflowRunPermissions: &PerWorkflowRunPermissions{
			ID: int64(567),
			Permissions: &WorkflowRunInstallationPermissions{
				CodespacesPrebuild: WriteAccess,
			},
		},
	}
	cases := []struct {
		description   string
		repoID        types.GlobalID
		ownerID       int64
		useCache      bool
		perms         *InstallationPermissions
		extendedPerms *ExtendedPermissions
		response      func(w http.ResponseWriter, r *http.Request)
		retryResponse func(w http.ResponseWriter, r *http.Request)
		expectError   bool
	}{
		{
			description: "basic write permissions",
			repoID:      repositoryGlobalID,
			ownerID:     testOwnerID,
			useCache:    false,
			perms:       writePermissions,
			response: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      testOwnerID,
					RepositoryIDs: []int64{repositoryID},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))
				_, _ = fmt.Fprintln(w, installationTokenJSON(s.writeToken()))
			},
		},
		{
			description:   "extended permissions",
			repoID:        repositoryGlobalID,
			ownerID:       testOwnerID,
			useCache:      false,
			perms:         writePermissions,
			extendedPerms: testExtendedPerms,
			response: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      testOwnerID,
					RepositoryIDs: []int64{repositoryID},
					Permissions:   writePermissions,
					ExtendedPermissions: []repoExtendedPermissions{
						{
							RepositoryID: repositoryID,
							PullRequests: []PerPullRequestPermissions{*testExtendedPerms.PerPullRequestPermissions},
							WorkflowRuns: []PerWorkflowRunPermissions{*testExtendedPerms.PerWorkflowRunPermissions},
						},
					},
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))
				_, _ = fmt.Fprintln(w, installationTokenJSON(s.writeToken()))
			},
		},
		{
			description: "owner ID not set",
			repoID:      repositoryGlobalID,
			ownerID:     0,
			useCache:    false,
			perms:       writePermissions,
			response: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      testOwnerID,
					RepositoryIDs: []int64{repositoryID},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))
				_, _ = fmt.Fprintln(w, installationTokenJSON(s.writeToken()))
			},
		},
		{
			description: "retry and fetch owner ID on 404",
			repoID:      repositoryGlobalID,
			ownerID:     intitialOwnerID,
			useCache:    false,
			perms:       writePermissions,
			response: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      intitialOwnerID,
					RepositoryIDs: []int64{repositoryID},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))

				// 404 for the initial request
				http.NotFound(w, r)
			},
			retryResponse: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      testOwnerID, // New owner ID fetched
					RepositoryIDs: []int64{repositoryID},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))
				_, _ = fmt.Fprintln(w, installationTokenJSON(s.writeToken()))
			},
		},
		{
			description: "retry and fetch owner ID on 422",
			repoID:      repositoryGlobalID,
			ownerID:     intitialOwnerID,
			useCache:    false,
			perms:       writePermissions,
			response: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      intitialOwnerID,
					RepositoryIDs: []int64{repositoryID},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))

				// 422 for the initial request
				http.Error(w, "422 Unprocessable Content", http.StatusUnprocessableEntity)
			},
			retryResponse: func(w http.ResponseWriter, r *http.Request) {
				expectedBody, err := json.Marshal(siteScopedTokenBody{
					TargetID:      testOwnerID, // New owner ID fetched
					RepositoryIDs: []int64{repositoryID},
					Permissions:   writePermissions,
				})
				s.NoError(err)
				defer r.Body.Close()
				body, err := io.ReadAll(r.Body)
				s.NoError(err)
				s.Equal(string(expectedBody), string(body))
				_, _ = fmt.Fprintln(w, installationTokenJSON(s.writeToken()))
			},
		},
	}

	for _, c := range cases {
		path := "/app/global/access_tokens"
		s.router.SetResponses(path, c.response)
		if c.retryResponse != nil {
			s.router.SetResponses(path, c.response, c.retryResponse)
		}

		service := s.newService()
		ctx := context.Background()

		token, err := service.SiteScopedTokenForRepository(ctx, c.repoID, c.ownerID, c.useCache, c.perms, c.extendedPerms)

		expectedCalls := 1
		if c.retryResponse != nil {
			expectedCalls = 2
		}

		s.Equal(expectedCalls, s.router.PathRequests(path), "expected %d calls to %q", expectedCalls, path)

		if c.expectError {
			s.Error(err)
			s.Nil(token)
			continue
		}

		s.NoError(err)
		s.NotNil(token)
	}
}

func (s *TokenTestSuite) TestSiteScopedTokenMultitenant() {
	testOwnerID := int64(1234)
	writePermissions := NewInstallationPermissions(WritePermissions)

	cases := []struct {
		description     string
		isMultiTenant   bool
		includeTenantID bool
		ghTenantID      int64
		expectError     bool
	}{
		{
			description: "non-multi-tenant",
		},
		{
			description:     "multi-tenant/valid-id",
			isMultiTenant:   true,
			includeTenantID: true,
			ghTenantID:      4,
		},
		{
			description:   "multi-tenant/missing-id",
			isMultiTenant: true,
			expectError:   true,
		},
	}

	for _, c := range cases {
		s.Run(c.description, func() {
			s.SetupTest()

			s.router.SetResponses("/app/global/access_tokens",
				func(w http.ResponseWriter, r *http.Request) {

					tenantHeaderValue := r.Header.Get(ghtenant.GitHubTenantIDHeader)

					if c.isMultiTenant {
						s.Equal(fmt.Sprintf("%d", c.ghTenantID), tenantHeaderValue)
					} else {
						s.Empty(tenantHeaderValue)
					}

					expectedBody, err := json.Marshal(siteScopedTokenBody{
						TargetID:      testOwnerID,
						RepositoryIDs: []int64{repositoryID},
						Permissions:   writePermissions,
					})
					s.NoError(err)
					defer r.Body.Close()
					body, err := io.ReadAll(r.Body)
					s.NoError(err)
					s.Equal(string(expectedBody), string(body))
					_, _ = fmt.Fprintln(w, installationTokenJSON(s.writeToken()))
				})

			service := s.newService()
			service.isMultiTenant = c.isMultiTenant

			ctx := context.Background()

			if c.includeTenantID {
				var err error
				ctx, err = ghtenant.ContextWithTenantID(ctx, c.ghTenantID, c.isMultiTenant)
				s.NoError(err)
			}

			token, err := service.SiteScopedTokenForRepository(ctx, repositoryGlobalID, testOwnerID, false, writePermissions, nil)

			if c.expectError {
				s.Error(err)
				s.Nil(token)
				return
			}

			s.NoError(err)
			s.NotNil(token)
		})
	}
}

func (s *TokenTestSuite) TestRefreshToken_Succeed() {
	// Expect that we'll be asking for a read only token
	s.router.SetResponses(
		"/app/installation/access_tokens",
		func(w http.ResponseWriter, r *http.Request) {
			_, _ = fmt.Fprintln(w, installationTokenJSON(s.writeToken()))
		},
	)

	ctx := context.Background()
	token := AccessToken{
		Token: "write-token",
	}

	service := s.newService()
	refreshedtoken, err := service.RefreshToken(ctx, &token)

	s.NoError(err)
	s.Equal(s.writeToken().Token, refreshedtoken.Token)
}

func (s *TokenTestSuite) TestRefreshToken_InvalidToken() {
	// Expect that we'll be asking for a read only token
	s.router.SetResponses(
		"/app/installation/access_tokens",
		func(w http.ResponseWriter, r *http.Request) {
			http.NotFound(w, r)
		},
	)

	service := s.newService()
	ctx := context.Background()
	token := AccessToken{
		Token: "write-token",
	}
	got, err := service.RefreshToken(ctx, &token)
	s.Contains(err.Error(), "invalid installation token")
	s.Nil(got)
}

func (s *TokenTestSuite) TestRevokeToken_Succeed() {
	// Expect that we'll be asking for a read only token
	s.router.SetResponses(
		"/installation/token",
		func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, "", http.StatusNoContent)
		},
	)

	service := s.newService()
	ctx := context.Background()
	token := AccessToken{
		Token: "write-token",
	}
	err := service.RevokeToken(ctx, repositoryGlobalID, &token)
	s.NoError(err)
}

func (s *TokenTestSuite) TestRevokeToken_InvalidToken() {
	// Expect that we'll be asking for a read only token
	s.router.SetResponses(
		"/installation/token",
		func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, "invalid token", http.StatusUnauthorized)
		},
	)

	service := s.newService()
	ctx := context.Background()
	token := AccessToken{
		Token: "write-token",
	}
	err := service.RevokeToken(ctx, repositoryGlobalID, &token)
	s.NoError(err)
}

func (s *TokenTestSuite) TestRevokeToken_InternalError() {
	// Expect that we'll be asking for a read only token
	s.router.SetResponses(
		"/installation/token",
		func(w http.ResponseWriter, r *http.Request) {
			http.NotFound(w, r)
		},
	)

	service := s.newService()
	ctx := context.Background()
	token := AccessToken{
		Token: "write-token",
	}

	err := service.RevokeToken(ctx, repositoryGlobalID, &token)
	s.Error(err)
	s.Contains(err.Error(), "404")
}

func (s *TokenTestSuite) TestReportsRateLimiting() {
	tests := []struct {
		operation      string
		path           string
		customerScoped bool
		function       func(context.Context, *service) (any, error)
	}{
		{
			operation: "createSiteScopedInstallationTokenCommon",
			path:      "/app/global/access_tokens",
			function: func(ctx context.Context, s *service) (any, error) {
				return s.SiteScopedTokenForRepositoryOwner(ctx, repositoryGlobalID, 0, false, nil, nil)
			},
		},
		{
			operation: "createSiteScopedInstallationTokenCommon",
			path:      "/app/global/access_tokens",
			function: func(ctx context.Context, s *service) (any, error) {
				return s.SiteScopedTokenForRepository(ctx, repositoryGlobalID, 0, false, nil, nil)
			},
		},
		{
			operation:      "RefreshToken",
			path:           "/app/installation/access_tokens",
			customerScoped: false,
			function: func(ctx context.Context, s *service) (any, error) {
				token := AccessToken{
					Token: "write-token",
				}
				return s.RefreshToken(ctx, &token)
			},
		},
		{
			operation:      "RevokeToken",
			path:           "/installation/token",
			customerScoped: true,
			function: func(ctx context.Context, s *service) (any, error) {
				token := AccessToken{
					Token: "write-token",
				}

				return nil, s.RevokeToken(ctx, repositoryGlobalID, &token)
			},
		},
	}

	for _, tc := range tests {
		s.Run(tc.operation, func() {
			s.router.SetResponses(
				tc.path,
				func(w http.ResponseWriter, r *http.Request) {
					w.Header().Set("Retry-After", "1")
					w.WriteHeader(http.StatusForbidden)
					w.Write([]byte(`{"message": "You have exceeded a secondary rate limit. Please wait a few minutes before you try again.", "documentation_url": "https://docs.github.com/en/free-pro-team@latest/rest/overview/resources-in-the-rest-api#secondary-rate-limits"}`))
				},
			)

			obs, log, stat := observability.NewMockedObservability()
			log.EXPECT().Debug(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return().Maybe()

			if tc.customerScoped {
				log.EXPECT().Error(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return()
			} else {
				log.EXPECT().Report(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return()
			}

			stat.EXPECT().Counter(mock.Anything, "site_scoped.token.create", mock.Anything, mock.Anything).Maybe()

			// This metrics counter is used to trigger a paging alert, so it's critical it be emitted.
			stat.EXPECT().Counter(mock.Anything, "github_rate_limit_exceeded", statter.Tags{
				"scoped_to_customer": strconv.FormatBool(tc.customerScoped),
				"operation":          tc.operation,
				"rate_limit_type":    "secondary",
			}, int64(1)).Return()

			service := s.newService()
			service.obs = obs

			ctx := context.Background()

			resp, err := tc.function(ctx, service)

			s.Nil(resp)
			s.Error(err)
			s.ErrorContains(err, "GitHub rate limit exceeded: You have exceeded a secondary rate limit. Please wait a few minutes before you try again.")
			s.True(terrors.IsRateLimitError(err))

			log.AssertExpectations(s.T())
			stat.AssertExpectations(s.T())
		})
	}
}

// Previously ExtendedPermissions was a property on the type InstallationPermissions
func (s *TokenTestSuite) TestUnmarshalPermissionSettingsBackCompat() {
	serialized := "{\"contents\":\"write\", \"metadata\":\"read\", \"extended_permissions\":{\"pull_request\":{\"number\": 4, \"permissions\":{\"sarifs\":\"write\"}}}}"
	perms := &PermissionSettings{}

	err := json.Unmarshal([]byte(serialized), perms)

	s.NoError(err)
	expected := &PermissionSettings{
		InstallationPermissions: InstallationPermissions{
			Contents: WriteAccess,
			Metadata: ReadAccess,
		},
		ExtendedPermissions: &ExtendedPermissions{
			PerPullRequestPermissions: &PerPullRequestPermissions{
				Number: 4,
				Permissions: PullRequestInstallationPermissions{
					Sarifs: WriteAccess,
				},
			},
		},
	}
	s.Equal(expected, perms)
}

func (s *TokenTestSuite) TestMergeMinimum() {
	cases := []struct {
		setScope           func(*InstallationPermissions, InstallationPermissionAccess)
		lhs, rhs, expected InstallationPermissionAccess
	}{
		// Actions, all permutations:
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, WriteAccess, WriteAccess, WriteAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, WriteAccess, NoneAccess, ""},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, WriteAccess, "", ""},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, ReadAccess, WriteAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, ReadAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, ReadAccess, NoneAccess, ""},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, ReadAccess, "", ""},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, NoneAccess, WriteAccess, ""},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, NoneAccess, ReadAccess, ""},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, NoneAccess, NoneAccess, ""},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, NoneAccess, "", ""},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, "", WriteAccess, ""},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, "", ReadAccess, ""},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, "", NoneAccess, ""},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Actions = y }, "", "", ""},
		// All other scopes:
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Checks = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Contents = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Deployments = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Issues = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Discussions = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Metadata = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Packages = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Pages = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.PullRequests = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.RepositoryProjects = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.Statuses = y }, WriteAccess, ReadAccess, ReadAccess},
		{func(x *InstallationPermissions, y InstallationPermissionAccess) { x.SecurityEvents = y }, WriteAccess, ReadAccess, ReadAccess},
	}
	for _, testCase := range cases {
		perms := &InstallationPermissions{}
		testCase.setScope(perms, testCase.lhs)
		base := &InstallationPermissions{}
		testCase.setScope(base, testCase.rhs)

		perms.MergeMinimum(base)

		expectedPerms := &InstallationPermissions{}
		testCase.setScope(expectedPerms, testCase.expected)
		s.Equal(expectedPerms, perms)
	}
}

type testRouter struct {
	routes map[string]*testRoute
}

func NewTestRouter() *testRouter {
	return &testRouter{routes: make(map[string]*testRoute)}
}

func (r *testRouter) SetResponses(path string, handlers ...func(w http.ResponseWriter, r *http.Request)) {
	r.routes[path] = &testRoute{path: path, handlers: handlers}
}

func (r *testRouter) Route(t *testing.T) http.HandlerFunc {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		for path, route := range r.routes {
			if path == req.RequestURI {
				route.handle(t, w, req)
				return
			}
		}
		t.Fatalf("unexpected URI: %q", req.RequestURI)
	})
}

func (r *testRouter) PathRequests(path string) int {
	return r.routes[path].reqCount
}

type testRoute struct {
	path     string
	handlers []func(w http.ResponseWriter, r *http.Request)
	reqCount int
}

func (r *testRoute) handle(t *testing.T, w http.ResponseWriter, req *http.Request) {
	if r.reqCount < len(r.handlers) {
		handler := r.handlers[r.reqCount]
		handler(w, req)
	} else {
		t.Fatalf("too many requests to %s, expected %d call, called %d times", r.path, len(r.handlers), r.reqCount+1)
	}
	r.reqCount++
}

func times(num int, handler func(w http.ResponseWriter, req *http.Request)) []func(w http.ResponseWriter, req *http.Request) {
	handlers := make([]func(w http.ResponseWriter, req *http.Request), 0, num)
	for i := 0; i < num; i++ {
		handlers = append(handlers, handler)
	}
	return handlers
}

func TestFractionOfDuration(t *testing.T) {
	tests := []struct {
		name   string
		inDur  time.Duration
		inFrac int64
		want   time.Duration
	}{
		{
			name:   "scale down",
			inDur:  time.Second,
			inFrac: 95,
			want:   950 * time.Millisecond,
		},
		{
			name:   "scale up",
			inDur:  time.Second,
			inFrac: 110,
			want:   1100 * time.Millisecond,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := fractionOfDuration(tt.inDur, tt.inFrac)
			require.Equal(t, tt.want, got)
		})
	}
}

func (s *TokenTestSuite) TestReadTokenForSiteScopedInstallation() {
	s.router.SetResponses(
		"/app/global/access_tokens",
		func(w http.ResponseWriter, r *http.Request) {
			_, _ = fmt.Fprintln(w, installationTokenJSON(s.readToken()))
		},
	)

	service := s.newService()
	ctx := context.Background()

	token, err := service.ReadTokenForSiteScopedInstallation(ctx, ownerID, []string{repoNWO.Name}, false)

	s.NoError(err)
	s.NotNil(token)
}

func (s *TokenTestSuite) TestReadTokenForSiteScopedInstallation_WithExistingValidAfter() {
	replicationLag := 5 * time.Millisecond
	validAfter := s.clock.Now().UTC().Add(replicationLag)

	s.router.SetResponses(
		"/app/global/access_tokens",
		func(w http.ResponseWriter, r *http.Request) {
			_, _ = fmt.Fprintln(w, installationTokenJSON(s.buildToken("read-token", defaultReadPermissions, 60, &validAfter)))
		},
	)

	service := s.newService()
	service.globalFFChecker = func(ctx context.Context, feature string) bool {
		return false
	}

	ctx := context.Background()

	token, err := service.ReadTokenForSiteScopedInstallation(ctx, ownerID, []string{repoNWO.Name}, false)

	s.NoError(err)
	s.NotNil(token)
	s.NotNil(token.ValidAfter)
}

func (s *TokenTestSuite) TestExtendedPermissionsStringer() {
	var nilPermission *ExtendedPermissions
	s.Equal("<nil>", fmt.Sprintf("%s", nilPermission))

	s.Equal("{PerPullRequestPermissions: <nil>, PerWorkflowRunPermissions: <nil>}", fmt.Sprintf("%s", &ExtendedPermissions{}))

	prPermissions := &ExtendedPermissions{
		PerPullRequestPermissions: &PerPullRequestPermissions{
			Number: 123,
			Permissions: PullRequestInstallationPermissions{
				Sarifs: WriteAccess,
			},
		},
	}
	s.Equal("{PerPullRequestPermissions: {Number: 123, Permissions: {Sarifs:write}}, PerWorkflowRunPermissions: <nil>}", fmt.Sprintf("%s", prPermissions))

	wrPermissions := &ExtendedPermissions{
		PerWorkflowRunPermissions: &PerWorkflowRunPermissions{
			ID: 123,
			Permissions: &WorkflowRunInstallationPermissions{
				CodespacesPrebuild: WriteAccess,
			},
		},
	}
	s.Equal("{PerPullRequestPermissions: <nil>, PerWorkflowRunPermissions: {ID: 123, Permissions: {CodespacesPrebuild:write}}}", fmt.Sprintf("%s", wrPermissions))

	bothPermissions := &ExtendedPermissions{
		PerPullRequestPermissions: &PerPullRequestPermissions{
			Number: 123,
			Permissions: PullRequestInstallationPermissions{
				Sarifs: WriteAccess,
			},
		},
		PerWorkflowRunPermissions: &PerWorkflowRunPermissions{
			ID: 123,
			Permissions: &WorkflowRunInstallationPermissions{
				CodespacesPrebuild: WriteAccess,
			},
		},
	}
	s.Equal("{PerPullRequestPermissions: {Number: 123, Permissions: {Sarifs:write}}, PerWorkflowRunPermissions: {ID: 123, Permissions: {CodespacesPrebuild:write}}}", fmt.Sprintf("%s", bothPermissions))
}

func (s *TokenTestSuite) TestCreateTokenForRepository_TimeoutAndRetriesWithBackoff() {
	writePermissions := NewInstallationPermissions(WritePermissions)
	testExtendedPerms := &ExtendedPermissions{
		PerPullRequestPermissions: &PerPullRequestPermissions{
			Number: 123,
			Permissions: PullRequestInstallationPermissions{
				Sarifs: WriteAccess,
			},
		},
		PerWorkflowRunPermissions: &PerWorkflowRunPermissions{
			ID: int64(567),
			Permissions: &WorkflowRunInstallationPermissions{
				CodespacesPrebuild: WriteAccess,
			},
		},
	}

	// Enable the feature flag
	fakeGlobalFFChecker := func(ctx context.Context, feature string) bool {
		return true
	}

	// We need this mock client to emulate client timeout errors
	mockHttpClient := &httpmock.Client{}
	s.ts = httptest.NewServer(s.router.Route(s.T()))
	url, err := url.Parse(s.ts.URL)
	s.NoError(err)
	service, err := newService(env,
		observability.NewNullObservability(),
		url,
		appID,
		appPrivateKey,
		s.clock,
		testutils.NewNoopBreaker(),
		httpclient.New(mockHttpClient),
		s.newLaunchCache(),
		s.fakeActorFFChecker,
		fakeGlobalFFChecker,
		s.fakeGetRepositoryOwnerID,
		httpclient.NewClientHooks(),
		false,
	)
	s.NoError(err)
	// This call will have a total of 3 attempts. Initial call + 2 retries. We should
	// succeed on the 3rd attempt.
	mockHttpClient.EXPECT().Do(mock.Anything).Return(nil, fmt.Errorf("net/http: timeout awaiting response headers")).Times(2)
	mockHttpClient.EXPECT().Do(mock.Anything).Return(&http.Response{
		StatusCode: 200,
		Body:       io.NopCloser(strings.NewReader(installationTokenJSON(s.writeToken()))),
	}, nil).Once()

	ctx := context.Background()
	token, err := service.SiteScopedTokenForRepository(ctx, repositoryGlobalID, ownerID, false, writePermissions, testExtendedPerms)

	s.NoError(err)
	s.NotNil(token)
}

func Test_service_buildURL(t *testing.T) {
	// Go's url.Parse will mangle URLs for our purposes if:
	// - the url being parsed already contains a path
	// - AND a path is appended to this path
	//
	// Demonstration of the problem: https://go.dev/play/p/5LCH7FHIGnk

	dotcomBase, err := url.Parse("https://api.github.com")
	require.NoError(t, err)
	enterpriseBase, err := url.Parse("https://localhost:9292/api/v3/")
	require.NoError(t, err)

	tests := []struct {
		name string
		base *url.URL
		path string
		want string
	}{
		{
			name: "dotcom scenario, not affected by bug since there is no path to append to",
			base: dotcomBase,
			path: "/drop/leading/slash/before/parsing",
			want: "https://api.github.com/drop/leading/slash/before/parsing",
		},
		{
			name: "dotcom scenario",
			base: dotcomBase,
			path: "app/global/access_token",
			want: "https://api.github.com/app/global/access_token",
		},
		{
			name: "enterprise scenario, with leading slash, previously resulted in mangled URLs",
			base: enterpriseBase,
			path: "/app/global/access_token",
			want: "https://localhost:9292/api/v3/app/global/access_token",
		},
		{
			name: "enterprise scenario, without leading slash",
			base: enterpriseBase,
			path: "app/global/access_token",
			want: "https://localhost:9292/api/v3/app/global/access_token",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := &service{
				base: tt.base,
			}
			got, err := s.appendURL(tt.path)
			require.NoError(t, err)
			if got != tt.want {
				t.Errorf("service.buildURL() = %v, want %v", got, tt.want)
			}
		})
	}
}

func Test_newService(t *testing.T) {
	badBaseURL, err := url.Parse("https://localhost:9292/api/v3")
	require.NoError(t, err)
	goodBaseURL, err := url.Parse("https://localhost:9292/api/v3/")
	require.NoError(t, err)

	tests := []struct {
		name    string
		baseURL *url.URL
		wantErr bool
	}{
		{
			name:    "badly formed base URL",
			baseURL: badBaseURL,
			wantErr: true,
		},
		{
			name:    "well formed base URL",
			baseURL: goodBaseURL,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := newService(
				env,
				observability.NewNullObservability(),
				tt.baseURL,
				appID,
				appPrivateKey,
				nil,
				nil,
				httpclient.New(nil),
				nil,
				func(ctx context.Context, s string, gi types.GlobalID) bool { return true },
				func(ctx context.Context, s string) bool { return true },
				func(ctx context.Context, repoID int64, useCache bool) (int64, error) { return 0, nil },
				nil,
				false,
			)
			if (err != nil) != tt.wantErr {
				t.Errorf("newService() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
		})
	}
}
