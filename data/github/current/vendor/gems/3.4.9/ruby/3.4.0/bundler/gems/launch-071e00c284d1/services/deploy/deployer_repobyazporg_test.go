package deploy

import (
	"context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/launchconfig"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

type RepoByAZPTenantTestSuite struct {
	suite.Suite

	svc               *service
	ghTwirp           *ghtwirp.MockClient
	azpResourceLoader *deployer.MockAzpResourcesLoader
	ghFactory         *github.MockFactory
	tokenService      *tokens.MockService
	ghClient          *github.MockClient

	fixtures struct {
		repoDatabaseID  int64
		repoGlobalID    types.GlobalID
		ownerDatabaseID int64
		ownerGlobalID   types.GlobalID
		installationID  int64
		tenantName      string
		tenantID        string
		environment     string
		nwo             types.RepositoryFullName
	}
}

func TestRepoByAZPTenantTestSuite(t *testing.T) {
	suite.Run(t, new(RepoByAZPTenantTestSuite))
}

func (suite *RepoByAZPTenantTestSuite) SetupTest() {
	suite.ghTwirp = ghtwirp.NewMockClient(suite.T())
	suite.azpResourceLoader = deployer.NewMockAzpResourcesLoader(suite.T())
	suite.ghFactory = github.NewMockFactory(suite.T())
	suite.tokenService = tokens.NewMockService(suite.T())
	suite.ghClient = github.NewMockClient(suite.T())

	suite.svc = &service{
		cfg: config{
			AppEnv:             launchconfig.TestAppEnv,
			Obs:                observability.NewNullObservability(),
			Log:                logger.TestLogger(),
			GithubTwirpClient:  suite.ghTwirp,
			AZPResourcesLoader: suite.azpResourceLoader,
			ClientFactory:      suite.ghFactory,
			TokenService:       suite.tokenService,
		},
	}

	suite.fixtures.repoDatabaseID = 123
	suite.fixtures.repoGlobalID = types.GlobalID(testutils.EncodeGlobalID("Repository", suite.fixtures.repoDatabaseID))
	suite.fixtures.ownerDatabaseID = 456
	suite.fixtures.ownerGlobalID = types.GlobalID(testutils.EncodeGlobalID("User", suite.fixtures.ownerDatabaseID))
	suite.fixtures.installationID = 789
	suite.fixtures.tenantName = "test-tenant-name"
	suite.fixtures.tenantID = "test-tenant-id"
	suite.fixtures.environment = "test-environment"
	suite.fixtures.nwo = types.RepositoryFullName{Owner: "test-owner", Name: "test-repo"}
}

func (suite *RepoByAZPTenantTestSuite) TestRepoByAZPTenant_Production() {
	suite.svc.cfg.AppEnv = launchconfig.ProductionAppEnv
	suite.azpResourceLoader.On("GetByTenantName", mock.Anything, suite.fixtures.tenantName).Return(&deployer.AzpResourceByName{
		EntityID:    suite.fixtures.repoGlobalID,
		TenantID:    suite.fixtures.tenantID,
		Environment: suite.fixtures.environment,
	}, true, nil)
	suite.ghClient.On("RepositoryNWO", mock.Anything, suite.fixtures.repoGlobalID).Return(types.RepositoryFullName(suite.fixtures.nwo), nil)
	suite.ghTwirp.On("GetRepositoryOwners", mock.Anything, suite.fixtures.repoDatabaseID).Return(&ghtwirp.RepositoryOwners{
		Owner: ghtwirp.Entity{
			ID:       suite.fixtures.ownerDatabaseID,
			GlobalID: suite.fixtures.ownerGlobalID,
		},
	}, nil)
	suite.ghFactory.On("NewClientForRepositoryOwner", mock.Anything, suite.fixtures.repoGlobalID, suite.fixtures.ownerGlobalID).Return(suite.ghClient, nil)

	ctx := context.Background()

	res, err := suite.svc.RepoByAZPTenant(ctx, &pb.RepoByAZPTenantRequest{
		Name: suite.fixtures.tenantName,
	})
	suite.NoError(err)
	suite.Equal(suite.fixtures.repoGlobalID.String(), res.RepositoryId)
	suite.Equal(suite.fixtures.environment, res.Env)
	suite.Equal(suite.fixtures.nwo.String(), res.Nwo)
}

func (suite *RepoByAZPTenantTestSuite) TestRepoByAZPTenant_Lab() {
	suite.svc.cfg.AppEnv = launchconfig.LabAppEnv
	suite.azpResourceLoader.On("GetByTenantName", mock.Anything, suite.fixtures.tenantName).Return(&deployer.AzpResourceByName{
		EntityID:    suite.fixtures.repoGlobalID,
		TenantID:    suite.fixtures.tenantID,
		Environment: suite.fixtures.environment,
	}, true, nil)
	suite.ghClient.On("RepositoryNWO", mock.Anything, suite.fixtures.repoGlobalID).Return(types.RepositoryFullName(suite.fixtures.nwo), nil)
	suite.ghTwirp.On("GetRepositoryOwners", mock.Anything, suite.fixtures.repoDatabaseID).Return(&ghtwirp.RepositoryOwners{
		Owner: ghtwirp.Entity{
			ID:       suite.fixtures.ownerDatabaseID,
			GlobalID: suite.fixtures.ownerGlobalID,
		},
	}, nil)
	suite.ghFactory.On("NewClientForRepositoryOwner", mock.Anything, suite.fixtures.repoGlobalID, suite.fixtures.ownerGlobalID).Return(suite.ghClient, nil)

	ctx := context.Background()

	res, err := suite.svc.RepoByAZPTenant(ctx, &pb.RepoByAZPTenantRequest{
		Name: suite.fixtures.tenantName,
	})
	suite.NoError(err)
	suite.Equal(suite.fixtures.repoGlobalID.String(), res.RepositoryId)
	suite.Equal(suite.fixtures.environment, res.Env)
	suite.Equal(suite.fixtures.nwo.String(), res.Nwo)
}

func (suite *RepoByAZPTenantTestSuite) TestRepoByAZPTenant_NotFound() {
	missingTenant := "i-dont-exist"

	suite.azpResourceLoader.On("GetByTenantName", mock.Anything, missingTenant).Return(nil, false, nil)

	ctx := context.Background()
	res, err := suite.svc.RepoByAZPTenant(ctx, &pb.RepoByAZPTenantRequest{
		Name: missingTenant,
	})
	suite.Require().Error(err)
	suite.Nil(res)
}
