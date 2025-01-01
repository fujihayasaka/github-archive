package deploy

import (
	"context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
)

const (
	testEnvironment      = "test-environment"
	testRepoGlobalID     = types.GlobalID("test-repo-global-id")
	testRepoNextGlobalID = types.GlobalID("R_test-repo-global-id")
	testTenantName       = "test-tenant-name"
	testTenantID         = "test-tenant-id"
)

func TestDeployer_GetAzForChatops(t *testing.T) {
	suite.Run(t, new(GetAZForChatopsSuite))
}

type GetAZForChatopsSuite struct {
	suite.Suite
	ghClient           *github.MockClient
	mockTwirpClient    *ghtwirp.MockClient
	svc                *service
	azpResourcesLoader *deployer.MockAzpResourcesLoader
}

func (s *GetAZForChatopsSuite) SetupSuite() {
	s.ghClient = &github.MockClient{}
	s.mockTwirpClient = &ghtwirp.MockClient{}
	s.azpResourcesLoader = &deployer.MockAzpResourcesLoader{}
	s.azpResourcesLoader.On("GetByGlobalID", mock.Anything, testRepoGlobalID, testEnvironment).Return(&deployer.TenantInfo{
		TenantName: testTenantName,
		TenantID:   testTenantID,
	}, true, nil)

	s.svc = &service{
		cfg: config{
			ClientFactory:      &github.MockFactory{},
			GithubTwirpClient:  s.mockTwirpClient,
			Obs:                observability.NewNullObservability(),
			AZPResourcesLoader: s.azpResourcesLoader,
		},
	}
}

func (s *GetAZForChatopsSuite) Test_GetAZForGlobalIDChatops() {
	s.mockTwirpClient.On("GetNextGlobalID", mock.Anything, testRepoGlobalID.String()).Return(testRepoNextGlobalID, nil)
	s.azpResourcesLoader.On("GetByGlobalID", mock.Anything, testRepoNextGlobalID, testEnvironment).Return(&deployer.TenantInfo{
		TenantName: testTenantName,
		TenantID:   testTenantID,
	}, true, nil)

	migrator := deployer.NewGlobalIDMigrator(s.mockTwirpClient)
	s.svc.gidMigrator = migrator

	result, err := s.svc.GetAZForGlobalIDChatops(
		context.Background(),
		&pb.GetAZForGlobalIDChatopsRequest{
			GlobalRelayId: string(testRepoGlobalID),
			Env:           testEnvironment,
		},
	)

	s.Assert().NoError(err)
	s.Assert().Equal(testRepoNextGlobalID.String(), result.GlobalID)
	s.Assert().Equal(testTenantName, result.AzTenantName)
	s.Assert().Equal(testTenantID, result.AzTenantID)
}
