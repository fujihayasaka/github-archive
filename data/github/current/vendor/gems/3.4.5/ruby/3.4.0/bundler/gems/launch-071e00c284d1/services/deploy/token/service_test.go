package token

import (
	"context"
	"net/http"
	"net/url"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy/token"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/workflowbuild"
)

const (
	workflowID = "workflow-123"
	jobID      = "job-123"
)

var (
	repositoryID = types.GlobalID("repo-123")
	perms        = &tokens.PermissionSettings{
		InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
		ExtendedPermissions: &tokens.ExtendedPermissions{
			PerPullRequestPermissions: &tokens.PerPullRequestPermissions{
				Number: 4,
				Permissions: tokens.PullRequestInstallationPermissions{
					Sarifs: tokens.WriteAccess,
				},
			},
		},
		DefaultPermissions: tokens.LimitedReadPermissions,
	}
	permsMap = map[string]string{
		"Actions":            "none",
		"Attestations":       "none",
		"Checks":             "none",
		"Contents":           "read",
		"Deployments":        "none",
		"Issues":             "none",
		"Discussions":        "none",
		"Metadata":           "read",
		"Packages":           "read",
		"Pages":              "none",
		"PullRequests":       "none",
		"RepositoryProjects": "none",
		"Statuses":           "none",
		"SecurityEvents":     "none",
	}
	workflowBuild = deployer.DataForTokenRequest{
		RepositoryID:     repositoryID,
		TokenPermissions: perms,
	}
	token = tokens.AccessToken{
		Token:       "token-123",
		Permissions: *tokens.NewInstallationPermissions(perms.DefaultPermissions),
	}
)

func TestTokenService(t *testing.T) {
	suite.Run(t, new(tokenServiceSuite))
}

type tokenServiceSuite struct {
	suite.Suite

	tokenFactory *workflowbuild.MockTokenFactory
	wfbRepo      *deployer.MockWorkflowBuildsRepositoryReadOnly
	svc          *service
}

func (s *tokenServiceSuite) SetupTest() {
	s.tokenFactory = &workflowbuild.MockTokenFactory{}
	s.wfbRepo = &deployer.MockWorkflowBuildsRepositoryReadOnly{}
	s.svc = New(logger.TestLogger(), statter.NullStatter(), s.wfbRepo, s.tokenFactory, false)
}

func (s *tokenServiceSuite) TearDownTest() {
	s.wfbRepo.AssertExpectations(s.T())
	s.tokenFactory.AssertExpectations(s.T())
}

func (s *tokenServiceSuite) Test_GetToken() {

	validGitHubTenantID := int64(4)
	invalidGitHubTenantID := int64(-1)

	cases := []struct {
		description               string
		dftr                      *deployer.DataForTokenRequest
		requestedPerms            map[string]string
		requestedWorkflowRunPerms map[string]string
		calculatedPerms           *tokens.InstallationPermissions
		expectedCalculatedPerms   map[string]string
		calculatedPermsContents   tokens.InstallationPermissionAccess
		calculatedPermsIssues     tokens.InstallationPermissionAccess
		extendedPerms             *tokens.ExtendedPermissions
		PerWorkflowRunPermissions *tokens.PerWorkflowRunPermissions
		isMultiTenant             bool
		ghTenantID                *int64
		getDataForTokenError      error
		getDataForTokenHasToken   bool
		newTokenError             error
		newTokenNotFound          bool
		shouldErrorOnTokenData    bool
		expectedError             string
		expectTwirpError          bool
	}{
		{
			description:               "happy-path",
			dftr:                      &workflowBuild,
			getDataForTokenHasToken:   true,
			requestedPerms:            map[string]string(nil),
			requestedWorkflowRunPerms: map[string]string(nil),
			calculatedPerms:           tokens.NewInstallationPermissions(perms.DefaultPermissions),
			extendedPerms:             perms.ExtendedPermissions,
			expectedCalculatedPerms:   permsMap,
		},
		{
			description: "happy-path/requested-permissions",
			dftr: &deployer.DataForTokenRequest{
				RepositoryID: repositoryID,
				TokenPermissions: &tokens.PermissionSettings{
					InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
					DefaultPermissions:      tokens.LimitedReadPermissions,
				},
			},
			getDataForTokenHasToken: true,
			requestedPerms: map[string]string{
				"contents": "read",
				"issues":   "write",
			},
			requestedWorkflowRunPerms: map[string]string(nil),
			calculatedPerms:           tokens.NewInstallationPermissions("none"),
			calculatedPermsContents:   tokens.ReadAccess,
			calculatedPermsIssues:     tokens.WriteAccess,
			expectedCalculatedPerms: map[string]string{
				"Actions":            "none",
				"Attestations":       "none",
				"Checks":             "none",
				"Contents":           "read",
				"Deployments":        "none",
				"Issues":             "write",
				"Discussions":        "none",
				"Metadata":           "read",
				"Packages":           "none",
				"Pages":              "none",
				"PullRequests":       "none",
				"RepositoryProjects": "none",
				"SecurityEvents":     "none",
				"Statuses":           "none",
			},
		},
		{
			description: "happy-path/workflow-run-permission",
			dftr: &deployer.DataForTokenRequest{
				RepositoryID:  repositoryID,
				WorkflowRunID: int64(124),
				TokenPermissions: &tokens.PermissionSettings{
					InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
					DefaultPermissions:      tokens.LimitedReadPermissions,
				},
			},
			getDataForTokenHasToken: true,
			requestedPerms: map[string]string{
				"contents": "read",
				"issues":   "write",
			},
			requestedWorkflowRunPerms: map[string]string{
				"codespaces_prebuilds": string(tokens.WriteAccess),
			},
			calculatedPerms:         tokens.NewInstallationPermissions("none"),
			calculatedPermsContents: tokens.ReadAccess,
			calculatedPermsIssues:   tokens.ReadAccess,
			extendedPerms:           perms.ExtendedPermissions,
			PerWorkflowRunPermissions: &tokens.PerWorkflowRunPermissions{
				ID: int64(124),
				Permissions: &tokens.WorkflowRunInstallationPermissions{
					CodespacesPrebuild: tokens.WriteAccess,
				},
			},
			expectedCalculatedPerms: map[string]string{
				"Actions":            "none",
				"Attestations":       "none",
				"Checks":             "none",
				"Contents":           "read",
				"Deployments":        "none",
				"Issues":             "read",
				"Discussions":        "none",
				"Metadata":           "read",
				"Packages":           "none",
				"Pages":              "none",
				"PullRequests":       "none",
				"RepositoryProjects": "none",
				"SecurityEvents":     "none",
				"Statuses":           "none",
			},
		},
		{
			description:            "error/db-error",
			getDataForTokenError:   errors.New("This is an error"),
			shouldErrorOnTokenData: true,
			expectedError:          "twirp error internal: Could not get token",
		},
		{
			description:            "error/db-empty",
			shouldErrorOnTokenData: true,
			expectedError:          "twirp error internal: Could not get token",
		},
		{
			description: "error/db-perms-not-saved",
			dftr: &deployer.DataForTokenRequest{
				RepositoryID:     repositoryID,
				TokenPermissions: nil,
			},
			getDataForTokenHasToken: true,
			shouldErrorOnTokenData:  true,
			expectedError:           "twirp error internal: Could not get token",
		},
		{
			description:               "error/fetch-token-error",
			dftr:                      &workflowBuild,
			getDataForTokenHasToken:   true,
			requestedPerms:            map[string]string(nil),
			requestedWorkflowRunPerms: map[string]string(nil),
			calculatedPerms:           tokens.NewInstallationPermissions(perms.DefaultPermissions),
			extendedPerms:             perms.ExtendedPermissions,
			newTokenError:             errors.New("Token fetch error"),
			expectedError:             "twirp error internal: Could not get token",
		},
		{
			description:               "error/new-token-not-found-error",
			dftr:                      &workflowBuild,
			getDataForTokenHasToken:   true,
			requestedPerms:            map[string]string(nil),
			requestedWorkflowRunPerms: map[string]string(nil),
			calculatedPerms:           tokens.NewInstallationPermissions(perms.DefaultPermissions),
			extendedPerms:             perms.ExtendedPermissions,
			newTokenNotFound:          true,
			expectedError:             "twirp error not_found: Error generating token with permissions: bad news: oh no: unexpected response `404` from `https://github.net/repositories/***/installation`",
			expectTwirpError:          true,
		},
		{
			description:               "multitenant/valid-id",
			dftr:                      &workflowBuild,
			getDataForTokenHasToken:   true,
			isMultiTenant:             true,
			ghTenantID:                &validGitHubTenantID,
			requestedPerms:            map[string]string(nil),
			requestedWorkflowRunPerms: map[string]string(nil),
			calculatedPerms:           tokens.NewInstallationPermissions(perms.DefaultPermissions),
			extendedPerms:             perms.ExtendedPermissions,
			expectedCalculatedPerms:   permsMap,
		},
		{
			description:             "multitenant/invalid-id",
			dftr:                    &workflowBuild,
			getDataForTokenHasToken: true,
			isMultiTenant:           true,
			ghTenantID:              &invalidGitHubTenantID,
			shouldErrorOnTokenData:  true,
			expectedError:           "twirp error internal: Could not get token",
		},
		{
			description:             "multitenant/nil-id",
			dftr:                    &workflowBuild,
			getDataForTokenHasToken: true,
			isMultiTenant:           true,
			ghTenantID:              &invalidGitHubTenantID,
			shouldErrorOnTokenData:  true,
			expectedError:           "twirp error internal: Could not get token",
		},
	}

	for _, c := range cases {
		s.Run(c.description, func() {
			s.SetupTest()

			if c.calculatedPermsContents != "" {
				c.calculatedPerms.Contents = c.calculatedPermsContents
			}

			if c.calculatedPermsIssues != "" {
				c.calculatedPerms.Issues = c.calculatedPermsIssues
			}

			if c.extendedPerms != nil {
				c.extendedPerms.PerWorkflowRunPermissions = c.PerWorkflowRunPermissions
			}

			if c.isMultiTenant {
				s.svc.isMultitenant = true
				c.dftr.GitHubTenantID = c.ghTenantID
			}

			s.wfbRepo.
				On("GetDataForTokenRequest",
					mock.Anything,
					mock.MatchedBy(func(wfid string) bool {
						return s.Equal(workflowID, wfid)
					}),
				).
				Return(c.dftr, c.getDataForTokenHasToken, c.getDataForTokenError)

			// Don't mock the other calls if the data for the token request is no good.
			if !c.shouldErrorOnTokenData {
				s.tokenFactory.On(
					"CalculateJobPermissions",
					mock.Anything,
					mock.Anything,
					c.dftr.TokenPermissions,
					c.requestedPerms,
					c.dftr.WorkflowRunID,
					c.requestedWorkflowRunPerms,
				).Return(
					c.calculatedPerms,
					c.extendedPerms,
					nil,
				).Run(func(args mock.Arguments) {
					ctx, ok := args.Get(0).(context.Context)
					s.Require().True(ok)
					tenantID, err := ghtenant.TenantIDFromContext(ctx, c.isMultiTenant)
					s.Require().NoError(err)

					if c.isMultiTenant {
						s.Assert().Equal(*c.ghTenantID, tenantID)
					}
				})

				var newToken *tokens.AccessToken
				newTokenErr := c.newTokenError

				if c.newTokenError == nil && !c.newTokenNotFound {
					newToken = &tokens.AccessToken{
						Token:       "token-123",
						Permissions: *c.calculatedPerms,
					}
				}

				if c.newTokenNotFound {
					tokenURL, _ := url.Parse("https://github.net/repositories/42/installation")
					httpResp := &http.Response{StatusCode: http.StatusNotFound, Request: &http.Request{URL: tokenURL}}
					httpNotFoundErr := terrors.NewHTTPError(httpResp)

					// wrap the error to ensure we're checking the error chain
					newTokenErr = errors.Wrap(errors.Wrap(httpNotFoundErr, "oh no"), "bad news")
				}

				s.tokenFactory.On(
					"NewToken",
					mock.Anything,
					c.dftr.RepositoryID,
					c.calculatedPerms,
					c.extendedPerms,
				).Return(
					newToken,
					newTokenErr,
				)
			}

			resp, err := s.svc.GetToken(context.Background(), &pb.GetTokenRequest{
				WorkflowId:             workflowID,
				JobId:                  jobID,
				Permissions:            c.requestedPerms,
				WorkflowRunPermissions: c.requestedWorkflowRunPerms,
			})

			if c.expectedError != "" {

				if c.expectTwirpError {
					// Verify a 404 returned by GitHub installation or token APIs is marshalled as a twirp NotFound error.
					twerr, ok := err.(twirp.Error)
					s.Assert().True(ok)
					s.Assert().Equal(twirp.NotFound, twerr.Code())
					s.EqualError(err, c.expectedError)
					return
				}

				s.Nil(resp)
				s.EqualError(err, c.expectedError)
				return
			}

			s.NoError(err)
			s.Equal(token.Token, resp.Token)
			s.Equal(c.expectedCalculatedPerms, resp.Permissions)
		})
	}
}

func (s *tokenServiceSuite) Test_RefreshToken() {

	validGitHubTenantID := int64(4)
	invalidGitHubTenantID := int64(-1)

	cases := []struct {
		description                string
		shouldSkipRefreshTokenCall bool
		refreshTokenResp           interface{}
		refreshTokenErr            error
		isMultiTenant              bool
		ghTenantID                 *int64
		expectedError              string
	}{
		{
			description: "happy-path",
			refreshTokenResp: &tokens.AccessToken{
				Token:  "token-123",
				Expiry: time.Now().Add(time.Hour * 1),
			},
		},
		{
			description:      "update-token/regular-error",
			refreshTokenResp: nil,
			refreshTokenErr:  errors.New("Token refresh error"),
			expectedError:    svcerr.NewInternalError("Could not refresh token").Error(),
		},
		{
			description:      "update-token/invalid-token-error",
			refreshTokenResp: nil,
			refreshTokenErr:  errors.New("invalid installation token"),
			expectedError:    svcerr.NewInternalError("Could not refresh token: invalid installation token").Error(),
		},
		{
			description: "multi-tenant/valid-id",
			refreshTokenResp: &tokens.AccessToken{
				Token:  "token-123",
				Expiry: time.Now().Add(time.Hour * 1),
			},
			isMultiTenant: true,
			ghTenantID:    &validGitHubTenantID,
		},
		{
			description:                "multi-tenant/invalid-id",
			shouldSkipRefreshTokenCall: true,
			refreshTokenResp: &tokens.AccessToken{
				Token:  "token-123",
				Expiry: time.Now().Add(time.Hour * 1),
			},
			isMultiTenant: true,
			ghTenantID:    &invalidGitHubTenantID,
			expectedError: svcerr.NewInternalError("Could not refresh token").Error(),
		},
		{
			description:                "multi-tenant/nil-id",
			shouldSkipRefreshTokenCall: true,
			refreshTokenResp: &tokens.AccessToken{
				Token:  "token-123",
				Expiry: time.Now().Add(time.Hour * 1),
			},
			isMultiTenant: true,
			ghTenantID:    nil,
			expectedError: svcerr.NewInternalError("Could not refresh token").Error(),
		},
	}

	for _, c := range cases {
		s.Run(c.description, func() {
			s.SetupTest()

			dftr := deployer.DataForTokenRequest{
				RepositoryID:     repositoryID,
				TokenPermissions: perms,
			}

			s.svc.isMultitenant = c.isMultiTenant

			if c.isMultiTenant {
				dftr.GitHubTenantID = c.ghTenantID
			}

			s.wfbRepo.On(
				"GetDataForTokenRequest",
				mock.Anything,
				mock.MatchedBy(func(wfid string) bool {
					return s.Equal(workflowID, wfid)
				}),
			).Return(
				&dftr,
				true,
				nil,
			)

			if !c.shouldSkipRefreshTokenCall {
				s.tokenFactory.On(
					"RefreshToken",
					mock.Anything,
					mock.MatchedBy(func(token *tokens.AccessToken) bool {
						return s.Equal(token.Token, "token-123")
					}),
				).Return(
					c.refreshTokenResp,
					c.refreshTokenErr,
				).Run(
					func(args mock.Arguments) {
						ctx, ok := args.Get(0).(context.Context)
						s.Require().True(ok)
						tenantID, err := ghtenant.TenantIDFromContext(ctx, c.isMultiTenant)
						s.Require().NoError(err)

						if c.isMultiTenant {
							s.Assert().Equal(*c.ghTenantID, tenantID)
						}
					})
			}

			resp, err := s.svc.RefreshToken(context.Background(), &pb.RefreshTokenRequest{
				WorkflowId: workflowID,
				Token:      "token-123",
			})

			if c.expectedError != "" {
				s.Nil(resp)
				s.EqualError(err, c.expectedError)
				return
			}

			s.NoError(err)
			s.Equal("token-123", resp.Token)
		})
	}
}

func (s *tokenServiceSuite) Test_RevokeToken() {

	validGitHubTenantID := int64(4)
	invalidGitHubTenantID := int64(-1)

	cases := []struct {
		description               string
		revokeRetVal              interface{}
		isMultiTenant             bool
		ghTenantID                *int64
		shouldSkipRevokeTokenCall bool
		expectError               bool
	}{
		{
			description: "revoke-success",
		},
		{
			description:  "revoke-error",
			revokeRetVal: errors.New("Token revoke error"),
			expectError:  true,
		},
		{
			description:   "multi-tenant/valid-id",
			isMultiTenant: true,
			ghTenantID:    &validGitHubTenantID,
		},
		{
			description:               "multi-tenant/invalid-id",
			isMultiTenant:             true,
			ghTenantID:                &invalidGitHubTenantID,
			shouldSkipRevokeTokenCall: true,
			expectError:               true,
		},
		{
			description:               "multi-tenant/nil-id",
			isMultiTenant:             true,
			ghTenantID:                nil,
			shouldSkipRevokeTokenCall: true,
			expectError:               true,
		},
	}

	for _, c := range cases {
		s.Run(c.description, func() {
			s.SetupTest()

			dftr := deployer.DataForTokenRequest{
				RepositoryID:     repositoryID,
				TokenPermissions: perms,
			}

			s.svc.isMultitenant = c.isMultiTenant

			if c.isMultiTenant {
				dftr.GitHubTenantID = c.ghTenantID
			}

			s.wfbRepo.On(
				"GetDataForTokenRequest",
				mock.Anything,
				mock.MatchedBy(func(wfid string) bool {
					return s.Equal(workflowID, wfid)
				}),
			).Return(&dftr, true, nil)

			if !c.shouldSkipRevokeTokenCall {
				s.tokenFactory.On(
					"RevokeToken",
					mock.Anything,
					repositoryID,
					mock.MatchedBy(func(token *tokens.AccessToken) bool {
						return s.Equal(token.Token, "token-123")
					}),
				).Return(c.revokeRetVal).Run(
					func(args mock.Arguments) {
						ctx, ok := args.Get(0).(context.Context)
						s.Require().True(ok)
						tenantID, err := ghtenant.TenantIDFromContext(ctx, c.isMultiTenant)
						s.Require().NoError(err)

						if c.isMultiTenant {
							s.Assert().Equal(*c.ghTenantID, tenantID)
						}
					})
			}

			resp, err := s.svc.RevokeToken(context.Background(), &pb.RevokeTokenRequest{
				WorkflowId: workflowID,
				Token:      "token-123",
			})

			if c.expectError {
				s.EqualError(err, svcerr.NewInternalError("Could not revoke token").Error())
				s.Nil(resp)
				return
			}

			s.NoError(err)
			s.NotNil(resp)
		})
	}
}

func (s *tokenServiceSuite) Test_GetJobPermissions() {

	validGitHubTenantID := int64(4)
	invalidGitHubTenantID := int64(-1)

	cases := []struct {
		description               string
		dftr                      *deployer.DataForTokenRequest
		requestedPerms            map[string]string
		requestedWorkflowRunPerms map[string]string
		calculatedPerms           *tokens.InstallationPermissions
		expectedCalculatedPerms   map[string]string
		calculatedPermsContents   tokens.InstallationPermissionAccess
		calculatedPermsIssues     tokens.InstallationPermissionAccess
		extendedPerms             *tokens.ExtendedPermissions
		isMultiTenant             bool
		ghTenantID                *int64
		getDataForTokenHasToken   bool
		getDataForTokenError      error
		shouldErrorOnTokenData    bool
		expectedError             string
	}{
		{
			description:               "happy-path",
			dftr:                      &workflowBuild,
			getDataForTokenHasToken:   true,
			requestedPerms:            map[string]string(nil),
			requestedWorkflowRunPerms: map[string]string(nil),
			calculatedPerms:           tokens.NewInstallationPermissions(perms.DefaultPermissions),
			extendedPerms:             perms.ExtendedPermissions,
			expectedCalculatedPerms:   permsMap,
		},
		{
			description: "happy-path/requested-permissions",
			dftr: &deployer.DataForTokenRequest{
				RepositoryID: repositoryID,
				TokenPermissions: &tokens.PermissionSettings{
					InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
					DefaultPermissions:      tokens.LimitedReadPermissions,
				},
			},
			getDataForTokenHasToken: true,
			requestedPerms: map[string]string{
				"contents": "read",
				"issues":   "write",
			},
			calculatedPerms:         tokens.NewInstallationPermissions("none"),
			calculatedPermsContents: tokens.ReadAccess,
			calculatedPermsIssues:   tokens.WriteAccess,
			expectedCalculatedPerms: map[string]string{
				"Actions":            "none",
				"Attestations":       "none",
				"Checks":             "none",
				"Contents":           "read",
				"Deployments":        "none",
				"Issues":             "write",
				"Discussions":        "none",
				"Metadata":           "read",
				"Packages":           "none",
				"Pages":              "none",
				"PullRequests":       "none",
				"RepositoryProjects": "none",
				"SecurityEvents":     "none",
				"Statuses":           "none",
			},
		},
		{
			description:            "error/db-error",
			getDataForTokenError:   errors.New("This is an error"),
			shouldErrorOnTokenData: true,
			expectedError:          svcerr.NewInternalError("Could not get job permissions").Error(),
		},
		{
			description:            "error/db-empty",
			shouldErrorOnTokenData: true,
			expectedError:          svcerr.NewInternalError("Could not get job permissions").Error(),
		},
		{
			description: "error/db-perms-not-saved",
			dftr: &deployer.DataForTokenRequest{
				RepositoryID:     repositoryID,
				TokenPermissions: nil,
			},
			getDataForTokenHasToken: true,
			shouldErrorOnTokenData:  true,
			expectedError:           svcerr.NewInternalError("Could not get job permissions").Error(),
		},
		{
			description:               "multi-tenant/valid-id",
			dftr:                      &workflowBuild,
			getDataForTokenHasToken:   true,
			requestedPerms:            map[string]string(nil),
			requestedWorkflowRunPerms: map[string]string(nil),
			calculatedPerms:           tokens.NewInstallationPermissions(perms.DefaultPermissions),
			extendedPerms:             perms.ExtendedPermissions,
			expectedCalculatedPerms:   permsMap,
			isMultiTenant:             true,
			ghTenantID:                &validGitHubTenantID,
		},
		{
			description:             "multi-tenant/invalid-id",
			dftr:                    &workflowBuild,
			getDataForTokenHasToken: true,
			isMultiTenant:           true,
			ghTenantID:              &invalidGitHubTenantID,
			shouldErrorOnTokenData:  true,
			expectedError:           svcerr.NewInternalError("Could not get job permissions").Error(),
		},
		{
			description:             "multi-tenant/nil-id",
			dftr:                    &workflowBuild,
			getDataForTokenHasToken: true,
			isMultiTenant:           true,
			ghTenantID:              nil,
			shouldErrorOnTokenData:  true,
			expectedError:           svcerr.NewInternalError("Could not get job permissions").Error(),
		},
	}

	for _, c := range cases {
		s.Run(c.description, func() {
			s.SetupTest()

			if c.calculatedPermsContents != "" {
				c.calculatedPerms.Contents = c.calculatedPermsContents
			}

			if c.calculatedPermsIssues != "" {
				c.calculatedPerms.Issues = c.calculatedPermsIssues
			}

			if c.isMultiTenant {
				s.svc.isMultitenant = true
				c.dftr.GitHubTenantID = c.ghTenantID
			}

			s.wfbRepo.
				On("GetDataForTokenRequest",
					mock.Anything,
					mock.MatchedBy(func(wfid string) bool {
						return s.Equal(workflowID, wfid)
					}),
				).
				Return(c.dftr, c.getDataForTokenHasToken, c.getDataForTokenError)

			// Don't mock the other call if the data for the token request is no good.
			if !c.shouldErrorOnTokenData {
				s.tokenFactory.On(
					"CalculateJobPermissions",
					mock.Anything,
					mock.Anything,
					c.dftr.TokenPermissions,
					c.requestedPerms,
					c.dftr.WorkflowRunID,
					c.requestedWorkflowRunPerms,
				).Return(
					c.calculatedPerms,
					c.extendedPerms,
					nil,
				).Run(func(args mock.Arguments) {
					ctx, ok := args.Get(0).(context.Context)
					s.Require().True(ok)
					tenantID, err := ghtenant.TenantIDFromContext(ctx, c.isMultiTenant)
					s.Require().NoError(err)

					if c.isMultiTenant {
						s.Assert().Equal(*c.ghTenantID, tenantID)
					}
				})
			}

			resp, err := s.svc.GetJobPermissions(context.Background(), &pb.GetJobPermissionsRequest{
				PlanId:               workflowID,
				RequestedPermissions: c.requestedPerms,
			})

			if c.expectedError != "" {
				s.Nil(resp)
				s.EqualError(err, c.expectedError)
				return
			}

			s.NoError(err)
			s.Equal(c.expectedCalculatedPerms, resp.EffectivePermissions)
		})
	}
}
