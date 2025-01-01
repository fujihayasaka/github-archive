package environment

import (
	"context"
	"testing"

	errs "github.com/pkg/errors"

	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ghtenant"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

const (
	testGateID           types.GlobalID = "MDQ6R2F0ZTI="
	testGateNextID       types.GlobalID = "GA_kwDOElg-9gI"
	testPlanID                          = "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
	testExternalJobID                   = "00000000-0000-0000-0000-000000000000"
	testToken                           = "Token"
	testRepositoryID                    = "RepoID"
	testIsOpen                          = true
	testCheckSuiteID                    = "CheckSuiteID"
	testNextRepositoryID types.GlobalID = "R_kgAD="
	testNextOwnerID      types.GlobalID = "O_kgDNJr8"
)

func TestDeployer_EnvironmentGates(t *testing.T) {
	suite.Run(t, new(EnvironmentGateSuite))
}

type EnvironmentGateSuite struct {
	suite.Suite
	svc                      *service
	githubClient             *github.MockClient
	ghtwirpClient            *ghtwirp.MockClient
	ghClientFactory          *github.MockFactory
	repositoryClient         *azp.MockRepositoryClient
	workflowBuildsRepository *deployer.MockWorkflowBuildsRepository
}

func (s *EnvironmentGateSuite) SetupTest() {
	azpResourcesRepository := &deployer.MockAzpResourcesRepository{}
	azpResourcesRepository.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.repositoryClient = &azp.MockRepositoryClient{}
	repositoryClientFactory := &azp.MockRepositoryClientFactory{}
	repositoryClientFactory.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.repositoryClient)

	s.githubClient = &github.MockClient{}
	s.ghtwirpClient = &ghtwirp.MockClient{}
	s.ghClientFactory = &github.MockFactory{}

	s.workflowBuildsRepository = &deployer.MockWorkflowBuildsRepository{}

	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		buildRepo:            s.workflowBuildsRepository,
		azpRepoClientFactory: repositoryClientFactory,
		azpResourceRepo:      azpResourcesRepository,
		ghClientFactory:      s.ghClientFactory,
		ghtwirpClient:        s.ghtwirpClient,
	}

	s.T().Setenv("LAUNCH_ENV", launchconfig.TestAppEnv.String())
	_ = launchconfig.LoadGlobalConfig()
}

func (s *EnvironmentGateSuite) TestGetOrCreateEnvironment() {

	validGitHubTenant := int64(4)
	invalidGitHubTenant := int64(-1)

	testGates := []*github.Gate{
		{
			GateID:           types.GlobalID("MDA0OkdhdGUyMw=="),
			DatabaseID:       23,
			GateType:         "TIMEOUT",
			TimeoutInMinutes: 0,
		},
	}

	cases := []struct {
		description        string
		tokenAccess        tokens.InstallationPermissionAccess
		useProdLaunchEnv   bool
		getOrCreateFnName  string
		getOrCreateFnError error
		gates              []*github.Gate
		requestedEnvName   string
		expectedEnvName    string
		isMultiTenant      bool
		ghTenantID         *int64
		expectedError      error
	}{
		{
			description:       "with-non-write-actions-permissions",
			tokenAccess:       tokens.ReadAccess,
			getOrCreateFnName: "GetEnvironment",
			gates:             testGates,
			requestedEnvName:  "production",
			expectedEnvName:   "production",
		},
		{
			description:       "zero-wait",
			tokenAccess:       tokens.WriteAccess,
			getOrCreateFnName: "CreateEnvironment",
			gates:             testGates,
			requestedEnvName:  "production",
			expectedEnvName:   "production",
		},
		{
			description:       "parsing",
			tokenAccess:       tokens.WriteAccess,
			getOrCreateFnName: "CreateEnvironment",
			gates:             []*github.Gate{},
			requestedEnvName:  "foo/bar=#hello",
			expectedEnvName:   "foo%2Fbar%3D%23hello",
		},
		{
			description:        "error/graphql-not-found",
			tokenAccess:        tokens.WriteAccess,
			getOrCreateFnName:  "CreateEnvironment",
			getOrCreateFnError: errors.NewGraphQLError(errors.NewNotFoundError(errs.New("Not Found"))),
			requestedEnvName:   "production",
			expectedEnvName:    "production",
			expectedError:      svcerr.NewNotFoundError("Environment or repository not found"),
		},
		{
			description:       "multi-tenant/valid-id",
			tokenAccess:       tokens.ReadAccess,
			getOrCreateFnName: "GetEnvironment",
			gates:             testGates,
			requestedEnvName:  "production",
			expectedEnvName:   "production",
			isMultiTenant:     true,
			ghTenantID:        &validGitHubTenant,
		},
		{
			description:       "multi-tenant/invalid-id",
			tokenAccess:       tokens.ReadAccess,
			getOrCreateFnName: "GetEnvironment",
			gates:             testGates,
			requestedEnvName:  "production",
			expectedEnvName:   "production",
			isMultiTenant:     true,
			ghTenantID:        &invalidGitHubTenant,
			expectedError:     svcerr.NewInternalError("Could not get environment"),
		},
		{
			description:       "multi-tenant/nil-id",
			tokenAccess:       tokens.ReadAccess,
			getOrCreateFnName: "GetEnvironment",
			gates:             testGates,
			requestedEnvName:  "production",
			expectedEnvName:   "production",
			isMultiTenant:     true,
			ghTenantID:        nil,
			expectedError:     svcerr.NewInternalError("Could not get environment"),
		},
	}

	for _, c := range cases {
		s.Run(c.description, func() {
			s.SetupTest()

			if c.useProdLaunchEnv {
				s.T().Setenv("LAUNCH_ENV", launchconfig.ProductionAppEnv.String())
				_ = launchconfig.LoadGlobalConfig()
			}

			var githubTenantID *int64
			if c.isMultiTenant {
				s.svc.isMultitenant = true
				githubTenantID = c.ghTenantID
			}

			s.ghClientFactory.On("NewClientForRepositoryOwner", mock.Anything, testNextRepositoryID, testNextOwnerID).Return(s.githubClient, nil).Once()

			ctx := context.Background()

			var envResponse *github.EnvironmentResponse

			if c.getOrCreateFnError == nil {
				envResponse = &github.EnvironmentResponse{
					Name:  c.requestedEnvName,
					Gates: c.gates,
				}
			}

			s.githubClient.On(
				c.getOrCreateFnName,
				mock.Anything,
				testNextRepositoryID,
				c.requestedEnvName,
			).Return(
				envResponse,
				c.getOrCreateFnError,
			).Run(func(args mock.Arguments) {
				ctx := args.Get(0).(context.Context)
				tenantID, err := ghtenant.TenantIDFromContext(ctx, c.isMultiTenant)
				s.NoError(err)

				if c.isMultiTenant {
					s.Equal(*c.ghTenantID, tenantID)
				}
			})

			s.useToken(c.tokenAccess, githubTenantID)

			res, err := s.svc.GetOrCreateEnvironment(ctx, &GetOrCreateEnvironmentRequest{
				EnvironmentName: c.expectedEnvName,
				WorkflowID:      "wfid",
			})

			if c.expectedError != nil {
				s.Equal(c.expectedError, err)
				return
			}

			s.Assert().NoError(err)

			if len(c.gates) > 0 {
				s.Equal("wait", res.Gates[0].Type)
				s.Equal(int32(15), res.Gates[0].TimeoutInMinutes)
			}
		})
	}
}

func (s *EnvironmentGateSuite) TestNotifyGate() {
	ctx := context.Background()

	s.ghtwirpClient.Mock.On("GetNextGlobalID", mock.Anything, testGateID.String()).Return(testGateNextID, nil)

	s.repositoryClient.On("UpdateGateConclusion", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)

	_, err := s.svc.NotifyGate(ctx, &NotifyGateRequest{
		RepositoryId:  types.IdentityFromGlobalID(testRepositoryID),
		ExternalId:    testPlanID,
		ExternalJobId: testExternalJobID,
		GateId:        types.IdentityFromGlobalID(testGateID),
		Token:         testToken,
		IsOpen:        testIsOpen,
	})

	s.Assert().NoError(err)
	s.repositoryClient.AssertCalled(s.T(), "UpdateGateConclusion", mock.Anything, testGateNextID.String(), testPlanID, testExternalJobID, testToken, testIsOpen)
}

func (s *EnvironmentGateSuite) useToken(p tokens.InstallationPermissionAccess, githubTenant *int64) {
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:   testNextRepositoryID,
		InstallationID: 1337,
		WorkflowMetadata: &metadata.WorkflowMetadata{
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				GlobalRelayID: testNextOwnerID.String(),
			},
		},
		GitHubTenantID: githubTenant,
	}
	switch p {
	case tokens.ReadAccess:
		dftr.TokenPermissions = &tokens.PermissionSettings{
			InstallationPermissions: tokens.InstallationPermissions{
				Deployments: tokens.ReadAccess,
			},
		}
	case tokens.WriteAccess:
		dftr.TokenPermissions = &tokens.PermissionSettings{
			InstallationPermissions: tokens.InstallationPermissions{
				Deployments: tokens.WriteAccess,
			},
		}
	default:
		panic("unknown permission")
	}

	s.workflowBuildsRepository.On("GetDataForTokenRequest", mock.Anything, mock.Anything).Return(dftr, true, nil)
}
