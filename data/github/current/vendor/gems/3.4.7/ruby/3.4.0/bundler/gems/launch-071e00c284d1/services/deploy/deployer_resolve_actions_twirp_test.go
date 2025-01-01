package deploy

import (
	"context"
	http "net/http"
	"net/url"
	"testing"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/ghinternal"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/ratelimit"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/cache/cachemem"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	ghactions "github.com/github/launch/proto/monolith/core/v1"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workerpool"
	"github.com/github/launch/workflowbuild"
)

func TestResolveActionsWithTwirp(t *testing.T) {
	suite.Run(t, new(resolveActionsWithTwirpSuite))
}

type resolveActionsWithTwirpSuite struct {
	suite.Suite

	svc *service

	wfb *deployer.MockWorkflowBuildsRepository
	wtf *workflowbuild.MockTokenFactory
	wts *tokens.MockService

	gif ghinternal.Factory

	workflowID   string
	jobID        string
	repositoryID string
	actionName   string
	actionBranch string
	actionSHA    string
	actionTag    string
}

const (
	// "org1"
	orgID       = int64(16631042)
	orgGlobalID = types.GlobalID("O_kgDOAP3FAg")

	// "org2"
	org2ID       = int64(67336198)
	org2GlobalID = types.GlobalID("O_kgDOBAN4Bg")
)

func (s *resolveActionsWithTwirpSuite) SetupTest() {
	log := logger.TestLogger()
	statter := statter.NullStatter()
	s.wfb = &deployer.MockWorkflowBuildsRepository{}
	s.wtf = &workflowbuild.MockTokenFactory{}
	s.wts = &tokens.MockService{}
	ghTwirpCache := launchcache.NewNamespacedCache(cachemem.NewExpiringCache(1<<20), observability.NewTestObservability()).GitHubTwirp()

	s.svc = &service{
		cfg: config{
			Log:                   log,
			Stats:                 statter,
			Obs:                   observability.New(log, statter),
			Workers:               workerpool.NewSimple(log, statter),
			WorkflowBuilds:        s.wfb,
			TokenFactory:          s.wtf,
			TokenService:          s.wts,
			InternalClientFactory: s.gif,
		},
		IsEnterprise: false,
		TwirpCache:   ghTwirpCache,
	}

	s.workflowID = "1942a726-e8ac-4959-a613-e61ea7bb573a"
	s.jobID = "75d03135-8a97-47e6-a0e3-b732fbe96921"
	s.repositoryID = "14"
	s.actionName = "actions/checkout"
	s.actionBranch = "develop"
	s.actionSHA = "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3"
	s.actionTag = "v2"
}

func (s *resolveActionsWithTwirpSuite) assertExpectations(mockTwirpClient *ghtwirp.MockClient) {
	s.T().Helper()
	s.wfb.AssertExpectations(s.T())
	s.wtf.AssertExpectations(s.T())
	s.wts.AssertExpectations(s.T())
	mockTwirpClient.AssertExpectations(s.T())
}

func (s *resolveActionsWithTwirpSuite) TestThatActionsCanBeResolved() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    s.actionName,
				Version: s.actionTag,
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: s.actionName,
				Ref: s.actionTag,
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              100,
				Name:            "actions/checkout",
				ResolvedName:    "actions/checkout",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "v2",
				ZipUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 1)
	s.Equal(s.actionName, res.Actions[0].Action.GetName())
	s.Nil(res.Actions[0].Authentication)
	s.Nil(res.Actions[0].PackageDetails)
	s.Equal(s.actionName, res.Actions[0].GetResolvedName())
	s.Equal(s.actionSHA, res.Actions[0].GetResolvedSha())
	s.Equal(s.actionTag, res.Actions[0].Action.GetVersion())

	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatRepoPolicyChecksGetOverriddenForActionsInRequiredWorkflows() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    s.actionName,
				Version: s.actionTag,
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, true).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: s.actionName,
				Ref: s.actionTag,
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{

		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              200,
				Name:            "actions/checkout",
				ResolvedName:    "actions/checkout",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "v2",
				ZipUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	mockClientFactory := github.NewMockClientFactory()
	s.svc.cfg.ClientFactory = mockClientFactory

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: "required/1234/test.yml",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 1)
	s.Equal(s.actionName, res.Actions[0].Action.GetName())
	s.Nil(res.Actions[0].Authentication)
	s.Equal(s.actionName, res.Actions[0].GetResolvedName())
	s.Equal(s.actionSHA, res.Actions[0].GetResolvedSha())
	s.Equal(s.actionTag, res.Actions[0].Action.GetVersion())

	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatPrivateAndPublicActionsCanBeResolved() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action",
			},
			{
				Name:    "org1/private1",
				Version: "action",
			},
			{
				Name:    "org1/private2",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:       true,
		ArePrivateActionsAllowed: true,
	}

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action",
			},
			{
				Nwo: "org1/private1",
				Ref: "action",
			},
			{
				Nwo: "org1/private2",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/private2",
				ResolvedName:    "org1/private2",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient
	s.svc.cfg.AppEnv = launchconfig.ProductionAppEnv

	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, []string{"private1", "private2"}, false).Return(token3, nil).Once()

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 3)
	s.Len(res.Errors, 0)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatPrivateActionsWithSharePolicyDisabledCanBeResolvedWhenUsedFromTheSameRepo() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/private1",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:       true,
		ArePrivateActionsAllowed: true,
	}

	repositoryID, _ := globalIDToRepositoryID(types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="))

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/private1",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              int64(repositoryID),
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 1)
	s.Len(res.Errors, 0)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatActionsCanBeResolvedOnGHEC() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    s.actionName,
				Version: s.actionTag,
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: s.actionName,
				Ref: s.actionTag,
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              100,
				Name:            "actions/checkout",
				ResolvedName:    "actions/checkout",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "v2",
				ZipUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 1)
	s.Equal(s.actionName, res.Actions[0].Action.GetName())
	s.Nil(res.Actions[0].Authentication)
	s.Nil(res.Actions[0].PackageDetails)
	s.Equal(s.actionName, res.Actions[0].GetResolvedName())
	s.Equal(s.actionSHA, res.Actions[0].GetResolvedSha())
	s.Equal(s.actionTag, res.Actions[0].Action.GetVersion())

	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatPublicAndPrivateAndInternalActionsOfSameOrgCanBeResolvedOnGHEC() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action",
			},
			{
				Name:    "org1/internal1",
				Version: "action",
			},
			{
				Name:    "org1/private1",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action",
			},
			{
				Nwo: "org1/internal1",
				Ref: "action",
			},
			{
				Nwo: "org1/private1",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/internal1",
				ResolvedName:    "org1/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, []string{"internal1", "private1"}, false).Return(token3, nil).Once()

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 3)
	for _, action := range res.Actions {
		if action.Action.Name != "org1/public1" {
			s.NotNil(action.Authentication)
			s.Equal(token3.Token, action.Authentication.Token)
		} else {
			s.Nil(action.Authentication)
		}
	}
	s.Len(res.Errors, 0)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatInternalWorkflowCannotAccessPrivateActionsOfSameOrgOnGHEC() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/private1",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/private1",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientDeny{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 0)
	s.Len(res.Errors, 1)
	s.Equal("Unable to resolve action `org1/private1`, not found", res.Errors[0].GetMessage())
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatPrivateActionsWithSharePolicyDisabledCannotBeResolved() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/private1",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:       true,
		ArePrivateActionsAllowed: true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/private1",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientDeny{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 0)
	s.Len(res.Errors, 1)
	s.Equal("Unable to resolve action `org1/private1`, repository not found", res.Errors[0].GetMessage())
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatPublicWorkflowCannotAccessPrivateAndInternalActionsOfSameOrg() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/internal1",
				Version: "action",
			},
			{
				Name:    "org1/private1",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/internal1",
				Ref: "action",
			},
			{
				Nwo: "org1/private1",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/internal1",
				ResolvedName:    "org1/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	mockClientFactory := github.NewMockClientFactory()
	s.svc.cfg.ClientFactory = mockClientFactory

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientDeny{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 0)
	s.Len(res.Errors, 2)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatPublicWorkflowCannotAccessPrivateAndInternalActionsOfAnotherOrg() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org2/internal1",
				Version: "action",
			},
			{
				Name:    "org2/private1",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org2/internal1",
				Ref: "action",
			},
			{
				Nwo: "org2/private1",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org2/internal1",
				ResolvedName:    "org2/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org2/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org2/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org2/private1",
				ResolvedName:    "org2/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org2/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org2/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientDeny{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 0)
	s.Len(res.Errors, 2)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatInternalWorkflowCannotAccessPrivateActionsOfAnotherOrgOnGHEC() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/private1",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/private1",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)

	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientDeny{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 0)
	s.Len(res.Errors, 1)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatPublicAndPrivateAndInternalActionsOfAnotherOrgCanBeResolvedOnGHEC() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org2/public1",
				Version: "action",
			},
			{
				Name:    "org2/internal1",
				Version: "action",
			},
			{
				Name:    "org2/private1",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org2").Return(org2ID, org2GlobalID, nil).Once()

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org2/public1",
				Ref: "action",
			},
			{
				Nwo: "org2/internal1",
				Ref: "action",
			},
			{
				Nwo: "org2/private1",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org2/public1",
				ResolvedName:    "org2/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org2/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org2/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org2/internal1",
				ResolvedName:    "org2/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org2/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org2/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org2/private1",
				ResolvedName:    "org2/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org2/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org2/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, org2ID, []string{"internal1", "private1"}, false).Return(token3, nil).Once()

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 3)
	for _, action := range res.Actions {
		if action.Action.Name != "org2/public1" {
			s.NotNil(action.Authentication)
			s.Equal(token3.Token, action.Authentication.Token)
		} else {
			s.Nil(action.Authentication)
		}
	}
	s.Len(res.Errors, 0)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatSameActionWithDifferentVersionsCanBeResolved() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action",
			},
			{
				Name:    "org1/internal1",
				Version: "action1",
			},
			{
				Name:    "org1/internal1",
				Version: "action2",
			},
			{
				Name:    "org1/private1",
				Version: "action1",
			},
			{
				Name:    "org1/private1",
				Version: "action2",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action",
			},
			{
				Nwo: "org1/internal1",
				Ref: "action1",
			},
			{
				Nwo: "org1/internal1",
				Ref: "action2",
			},
			{
				Nwo: "org1/private1",
				Ref: "action1",
			},
			{
				Nwo: "org1/private1",
				Ref: "action2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/internal1",
				ResolvedName:    "org1/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action1",
				ZipUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/internal1",
				ResolvedName:    "org1/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action2",
				ZipUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action1",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action2",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, []string{"internal1", "private1"}, false).Return(token3, nil).Once()

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 5)
	s.Len(res.Errors, 0)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatActionsWithDifferentCapitalisationCanBeResolved() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "Org1/public1",
				Version: "action",
			},
			{
				Name:    "org1/Internal1",
				Version: "action",
			},
			{
				Name:    "org1/internal2",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "Org1/public1",
				Ref: "action",
			},
			{
				Nwo: "org1/Internal1",
				Ref: "action",
			},
			{
				Nwo: "org1/internal2",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "Org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/Internal1",
				ResolvedName:    "org1/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/internal2",
				ResolvedName:    "org1/internal2",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/internal2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, mock.Anything, false).Return(token3, nil).Once()

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 3)
	s.Len(res.Errors, 0)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatOneOfInternalActionsPermissionFailsOnGHEC() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action",
			},
			{
				Name:    "org1/internal1",
				Version: "action",
			},
			{
				Name:    "org1/internal2",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action",
			},
			{
				Nwo: "org1/internal1",
				Ref: "action",
			},
			{
				Nwo: "org1/internal2",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/internal1",
				ResolvedName:    "org1/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/internal2",
				ResolvedName:    "org1/internal2",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/internal2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllowDeny{
		allowList: []bool{true, false},
	}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 0)
	s.Len(res.Errors, 1)
	s.Equal("Unable to resolve actions. Cannot access repositories 'org1/internal2'. Enable access using Settings in the Action repository. See https://docs.github.com/enterprise-cloud@latest/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#allowing-access-to-components-in-an-internal-repository for more information.", res.Errors[0].GetMessage())
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatOneOfPrivateActionsPermissionFails() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action",
			},
			{
				Name:    "org1/private1",
				Version: "action",
			},
			{
				Name:    "org1/private2",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:       true,
		ArePrivateActionsAllowed: true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action",
			},
			{
				Nwo: "org1/private1",
				Ref: "action",
			},
			{
				Nwo: "org1/private2",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/private2",
				ResolvedName:    "org1/private2",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllowDeny{
		allowList: []bool{true, false},
	}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Errors, 1)
	s.Equal("Unable to resolve action `org1/private2`, repository not found", res.Errors[0].GetMessage())
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestForNotFoundRepository() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			Error: &ghtwirp.ResolveActionsErr{
				Action: &ghtwirp.Action{
					Nwo: "org1/public1",
					Ref: "action",
				},
				Err: errors.New("Unable to resolve actions. Repository not found: org1/public1"),
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 0)
	s.Len(res.Errors, 1)
	s.Equal(res.Errors[0].GetMessage(), "Unable to resolve actions. Repository not found: org1/public1")
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatOneOfTheRepositoriesNotFound() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action",
			},
			{
				Name:    "org1/internal1",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action",
			},
			{
				Nwo: "org1/internal1",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/internal1",
				ResolvedName:    "org1/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			Error: &ghtwirp.ResolveActionsErr{
				Action: &ghtwirp.Action{
					Nwo: "org1/public1",
					Ref: "action",
				},
				Err: errors.New("Unable to resolve actions. Repository not found: org1/public1"),
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Errors, 1)
	s.Equal(res.Errors[0].GetMessage(), "Unable to resolve actions. Repository not found: org1/public1")
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatInternalAndPrivateActionsWithSharePolicyDisabledCannotBeResolved() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/inaccessible_internal_repo",
				Version: "action",
			},
			{
				Name:    "org1/inaccessible_private_repo",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/inaccessible_internal_repo",
				Ref: "action",
			},
			{
				Nwo: "org1/inaccessible_private_repo",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/inaccessible_internal_repo",
				ResolvedName:    "org1/inaccessible_internal_repo",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/inaccessible_internal_repo/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/inaccessible_internal_repo/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/inaccessible_private_repo",
				ResolvedName:    "org1/inaccessible_private_repo",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/inaccessible_private_repo/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/inaccessible_private_repo/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientDeny{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 0)
	s.Len(res.Errors, 1)
	s.Equal("Unable to resolve actions. Cannot access repositories 'org1/inaccessible_internal_repo'. Enable access using Settings in the Action repository. See https://docs.github.com/enterprise-cloud@latest/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#allowing-access-to-components-in-an-internal-repository for more information.", res.Errors[0].GetMessage())
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestReturns404WhenActionIsMissing() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "invalid/repository",
				Version: "action",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "invalid/repository",
				Ref: "action",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			Error: &ghtwirp.ResolveActionsErr{
				Action: &ghtwirp.Action{
					Nwo: "invalid/repository",
					Ref: "action",
				},
				Err: errors.New("Unable to resolve action `invalid/repository@action`, repository not found"),
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)

	s.Len(res.Actions, 0)
	s.Len(res.Errors, 1)
	s.Equal("invalid/repository", res.Errors[0].Action.GetName())
	s.Equal("action", res.Errors[0].Action.GetVersion())
	s.Equal("Unable to resolve action `invalid/repository@action`, repository not found", res.Errors[0].GetMessage())
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatActionRedirectWorksForNonEnterprisePublicRepos() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "v2",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:       true,
		ArePrivateActionsAllowed: true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "v2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              100,
				Name:            "org1/public1",
				ResolvedName:    "org1/public2",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "v2",
				ZipUrl:          "https://ghes/org1/public2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 1)
	s.Len(res.Errors, 0)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatActionRedirectDoesNotWorkForNonEnterprisePrivateRepos() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/private1",
				Version: "v2",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:       true,
		ArePrivateActionsAllowed: true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/private1",
				Ref: "v2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              100,
				Name:            "org1/private1",
				ResolvedName:    "org1/private2",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "v2",
				ZipUrl:          "https://ghes/org1/private2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	mockClientFactory := github.NewMockClientFactory()
	s.svc.cfg.ClientFactory = mockClientFactory

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 0)
	s.Len(res.Errors, 1)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatActionsWithPathCanBeResolved() { // Non-enterprise flow
	actionPath := ".github/actions/test-action"
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    s.actionName,
				Version: s.actionTag,
				Path:    actionPath,
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo:  s.actionName,
				Ref:  s.actionTag,
				Path: actionPath,
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              100,
				Name:            "actions/checkout",
				ResolvedName:    "actions/checkout",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "v2",
				ZipUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 1)
	s.Equal(s.actionName, res.Actions[0].Action.GetName())
	s.Nil(res.Actions[0].Authentication)
	s.Nil(res.Actions[0].PackageDetails)
	s.Equal(s.actionName, res.Actions[0].GetResolvedName())
	s.Equal(s.actionSHA, res.Actions[0].GetResolvedSha())
	s.Equal(s.actionTag, res.Actions[0].Action.GetVersion())

	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatPrivateAndPublicActionsWithPathCanBeResolved() { // Non-enterprise flow
	actionPath := ".github/action/test-action"
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action",
				Path:    actionPath,
			},
			{
				Name:    "org1/private1",
				Version: "action",
				Path:    actionPath,
			},
			{
				Name:    "org1/private2",
				Version: "action",
				Path:    actionPath,
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:       true,
		ArePrivateActionsAllowed: true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo:  "org1/public1",
				Ref:  "action",
				Path: actionPath,
			},
			{
				Nwo:  "org1/private1",
				Ref:  "action",
				Path: actionPath,
			},
			{
				Nwo:  "org1/private2",
				Ref:  "action",
				Path: actionPath,
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/private2",
				ResolvedName:    "org1/private2",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	mockClientFactory := github.NewMockClientFactory()
	s.svc.cfg.ClientFactory = mockClientFactory

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, []string{"private1", "private2"}, false).Return(token3, nil).Once()

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 3)
	s.Len(res.Errors, 0)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatPublicAndPrivateAndInternalActionsOfSameOrgWithPathCanBeResolvedOnGHEC() {
	actionPath := ".github/actions/test-action"
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action",
				Path:    actionPath,
			},
			{
				Name:    "org1/internal1",
				Version: "action",
				Path:    actionPath,
			},
			{
				Name:    "org1/private1",
				Version: "action",
				Path:    actionPath,
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo:  "org1/public1",
				Ref:  "action",
				Path: actionPath,
			},
			{
				Nwo:  "org1/internal1",
				Ref:  "action",
				Path: actionPath,
			},
			{
				Nwo:  "org1/private1",
				Ref:  "action",
				Path: actionPath,
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/internal1",
				ResolvedName:    "org1/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/internal1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, []string{"internal1", "private1"}, false).Return(token3, nil).Once()

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 3)
	for _, action := range res.Actions {
		if action.Action.Name != "org1/public1" {
			s.NotNil(action.Authentication)
			s.Equal(token3.Token, action.Authentication.Token)
		} else {
			s.Nil(action.Authentication)
		}
	}
	s.Len(res.Errors, 0)
	s.assertExpectations(mockTwirpClient)
}

func TestParseActionNameWithVersion(t *testing.T) {
	tests := []struct {
		desc                  string
		actionNameWithVersion string
		wantErr               bool
		wantNwo               string
		wantPath              string
		wantRef               string
	}{
		{
			desc:                  "test-1",
			actionNameWithVersion: "test-org-1/test-repo-1@main",
			wantNwo:               "test-org-1/test-repo-1",
			wantRef:               "main",
		},
		{
			desc:                  "test-2",
			actionNameWithVersion: "test-org-1/test-repo-1/.github/a/b/c/d/e/g@ashfowurf",
			wantNwo:               "test-org-1/test-repo-1",
			wantPath:              ".github/a/b/c/d/e/g",
			wantRef:               "ashfowurf",
		},
		{
			desc:                  "test-3",
			actionNameWithVersion: "test-org-1/test-repo-1/d@ashfowurf",
			wantNwo:               "test-org-1/test-repo-1",
			wantPath:              "d",
			wantRef:               "ashfowurf",
		},
		{
			desc:                  "test-4",
			actionNameWithVersion: "test-org-1@ashfowurf",
			wantErr:               true,
		},
		{
			desc:                  "test-5",
			actionNameWithVersion: "test-org-1ashfowurf",
			wantErr:               true,
		},
		{
			desc:                  "test-6",
			actionNameWithVersion: "test-org-1@v1@v2",
			wantErr:               true,
		},
		{
			desc:                  "test-7",
			actionNameWithVersion: "test-org-1/dqad@v1@v2",
			wantErr:               true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			nwo, path, ref, err := parseNameWithVersion(tt.actionNameWithVersion)
			if tt.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.wantNwo, nwo)
				assert.Equal(t, tt.wantPath, path)
				assert.Equal(t, tt.wantRef, ref)
			}
		})
	}
}

// Tests resolution of immutable actions
func (s *resolveActionsWithTwirpSuite) TestThatActionsCanBeResolvedWithPackages() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action1",
			},
			{
				Name:    "org1/public2",
				Version: "action2",
			},
			{
				Name:    "org1/internal",
				Version: "action",
			},
			{
				Name:    "org1/private1",
				Version: "action1",
			},
			{
				Name:    "org1/private1",
				Version: "action2",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)

	mockResolveActionsResponse := []*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:                    42,
				Name:                  "org1/public1",
				ResolvedName:          "org1/public1",
				ResolvedSha:           "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:                "https://ghcr.io/v2/org1/public1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:                   "action1",
				ZipUrl:                "https://ghcr.io/v2/org1/public1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:            "PUBLIC",
				ResolveStrategy:       ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE,
				PackageVersion:        "1.0.0",
				PackageManifestDigest: "sha256:1234",
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:                    43,
				Name:                  "org1/public2",
				ResolvedName:          "org1/public2",
				ResolvedSha:           "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:                "https://ghcr.io/v2/org1/public2/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:                   "action2",
				ZipUrl:                "https://ghcr.io/v2/org1/public2/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:            "PUBLIC",
				ResolveStrategy:       ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE,
				PackageVersion:        "1.0.0",
				PackageManifestDigest: "sha256:1234",
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:                    44,
				Name:                  "org1/internal",
				ResolvedName:          "org1/internal",
				ResolvedSha:           "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:                "https://ghcr.io/v2/org1/internal/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:                   "action",
				ZipUrl:                "https://ghcr.io/v2/org1/internal/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:            "INTERNAL",
				ResolveStrategy:       ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE,
				PackageVersion:        "1.0.0",
				PackageManifestDigest: "sha256:1234",
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:                    45,
				Name:                  "org1/private1",
				ResolvedName:          "org1/private1",
				ResolvedSha:           "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:                "https://ghcr.io/v2/org1/private1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:                   "action1",
				ZipUrl:                "https://ghcr.io/v2/org1/private1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:            "PRIVATE",
				ResolveStrategy:       ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE,
				PackageVersion:        "1.0.0",
				PackageManifestDigest: "sha256:1234",
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:                    45,
				Name:                  "org1/private1",
				ResolvedName:          "org1/private1",
				ResolvedSha:           "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:                "https://ghcr.io/v2/org1/private1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc5",
				Ref:                   "action2",
				ZipUrl:                "https://ghcr.io/v2/org1/private1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc6",
				Visibility:            "PRIVATE",
				ResolveStrategy:       ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE,
				PackageVersion:        "1.0.0",
				PackageManifestDigest: "sha256:1234",
			},
		},
	}

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action1",
			},
			{
				Nwo: "org1/public2",
				Ref: "action2",
			},
			{
				Nwo: "org1/internal",
				Ref: "action",
			},
			{
				Nwo: "org1/private1",
				Ref: "action1",
			},
			{
				Nwo: "org1/private1",
				Ref: "action2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return(mockResolveActionsResponse, nil)

	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	mockClientFactory := github.NewMockClientFactory()
	s.svc.cfg.ClientFactory = mockClientFactory

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
		WorkflowMetadata: &metadata.WorkflowMetadata{
			Repository: &metadata.WorkflowRepositoryMetadata{
				ID:            3,
				GlobalRelayID: "R_kgAD",
			},
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				Login: "sourceOwner",
			},
		},
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	// No token generation should be performed for packages, since they use presigned URLs for downloads
	s.wts.AssertNotCalled(s.T(), "ReadTokenForSiteScopedInstallation", mock.Anything)

	// No authz check should be performed for packages, since authzd is performed by Packages before returning to Launch
	// if any auth is called in this test, fail it so the test fails
	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientDeny{}, observability.NewTestObservability())

	expectedActionsMap := make(map[string]*ghactions.ResolvedAction)
	for _, expected := range mockResolveActionsResponse {
		expectedActionsMap[expected.ResolvedAction.ResolvedName+"@"+expected.ResolvedAction.Ref] = expected.ResolvedAction
	}

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 5)
	s.Len(res.Errors, 0)
	// Verify that the resolved actions match the expected actions
	for _, action := range res.Actions {
		expectedAction := expectedActionsMap[action.Action.Name+"@"+action.Action.Version]
		s.Equal(expectedAction.ResolvedName, action.ResolvedName)
		s.Equal(expectedAction.ResolvedSha, action.ResolvedSha)
		s.Equal(expectedAction.TarUrl, action.TarUrl)
		s.Equal(expectedAction.ZipUrl, action.ZipUrl)
		s.Nil(action.Authentication) // it shouldn't return a token for packages
		s.NotNil(action.PackageDetails)
		s.Equal(expectedAction.PackageVersion, action.PackageDetails.Version)
		s.Equal(expectedAction.PackageManifestDigest, action.PackageDetails.ManifestDigest)
	}

	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatActionsCanBeResolvedwithNoPackages() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action1",
			},
			{
				Name:    "org1/public2",
				Version: "action2",
			},
			{
				Name:    "org1/internal",
				Version: "action",
			},
			{
				Name:    "org1/private1",
				Version: "action1",
			},
			{
				Name:    "org1/private1",
				Version: "action2",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action1",
			},
			{
				Nwo: "org1/public2",
				Ref: "action2",
			},
			{
				Nwo: "org1/internal",
				Ref: "action",
			},
			{
				Nwo: "org1/private1",
				Ref: "action1",
			},
			{
				Nwo: "org1/private1",
				Ref: "action2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action1",
				ZipUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/public2",
				ResolvedName:    "org1/public2",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action2",
				ZipUrl:          "https://ghes/org1/public2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/internal",
				ResolvedName:    "org1/internal",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/internal/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              45,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action1",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              45,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action2",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action1",
			},
			{
				Nwo: "org1/public2",
				Ref: "action2",
			},
			{
				Nwo: "org1/internal",
				Ref: "action",
			},
			{
				Nwo: "org1/private1",
				Ref: "action1",
			},
			{
				Nwo: "org1/private1",
				Ref: "action2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{}, nil)

	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	mockClientFactory := github.NewMockClientFactory()
	s.svc.cfg.ClientFactory = mockClientFactory

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, []string{"internal", "private1"}, false).Return(token3, nil).Once()

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 5)
	s.Len(res.Errors, 0)
	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestThatActionsWithResolveStrategyInvalidAreTreatedAsRepositoryResolved() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action1",
			},
			{
				Name:    "org1/public2",
				Version: "action2",
			},
			{
				Name:    "org1/internal",
				Version: "action",
			},
			{
				Name:    "org1/private1",
				Version: "action1",
			},
			{
				Name:    "org1/private1",
				Version: "action2",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action1",
			},
			{
				Nwo: "org1/public2",
				Ref: "action2",
			},
			{
				Nwo: "org1/internal",
				Ref: "action",
			},
			{
				Nwo: "org1/private1",
				Ref: "action1",
			},
			{
				Nwo: "org1/private1",
				Ref: "action2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action1",
				ZipUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_INVALID,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/public2",
				ResolvedName:    "org1/public2",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/public2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action2",
				ZipUrl:          "https://ghes/org1/public2/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_INVALID,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:           44,
				Name:         "org1/internal",
				ResolvedName: "org1/internal",
				ResolvedSha:  "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:       "https://ghes/org1/internal/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:          "action",
				ZipUrl:       "https://ghes/org1/internal/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:   "INTERNAL",
				// No resolve strategy set
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:           45,
				Name:         "org1/private1",
				ResolvedName: "org1/private1",
				ResolvedSha:  "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:       "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:          "action1",
				ZipUrl:       "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:   "PRIVATE",
				// No resolve strategy set
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:           45,
				Name:         "org1/private1",
				ResolvedName: "org1/private1",
				ResolvedSha:  "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:       "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:          "action2",
				ZipUrl:       "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:   "PRIVATE",
			},
		},
	}, nil)

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action1",
			},
			{
				Nwo: "org1/public2",
				Ref: "action2",
			},
			{
				Nwo: "org1/internal",
				Ref: "action",
			},
			{
				Nwo: "org1/private1",
				Ref: "action1",
			},
			{
				Nwo: "org1/private1",
				Ref: "action2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{}, nil)

	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	mockClientFactory := github.NewMockClientFactory()
	s.svc.cfg.ClientFactory = mockClientFactory

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, []string{"internal", "private1"}, false).Return(token3, nil).Once()

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 5)
	s.Len(res.Errors, 0)
	s.assertExpectations(mockTwirpClient)
}

// Tests resolution of both immutable and non-immutable actions at once
func (s *resolveActionsWithTwirpSuite) TestThatActionsCanBeResolvedwithPackagesAndRepos() { // Non-enterprise flow
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "org1/public1",
				Version: "action1",
			},
			{
				Name:    "org1/public2",
				Version: "action2",
			},
			{
				Name:    "org1/internal",
				Version: "action",
			},
			{
				Name:    "org1/private1",
				Version: "action1",
			},
			{
				Name:    "org1/private1",
				Version: "action2",
			},
		},
	}

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}

	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()

	mockResolveActionsResponse := []*ghtwirp.ResolveActionsResponse{
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:                    42,
				Name:                  "org1/public1",
				ResolvedName:          "org1/public1",
				ResolvedSha:           "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:                "https://ghcr.io/v2/org1/public1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:                   "action1",
				ZipUrl:                "https://ghcr.io/v2/org1/public1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:            "PUBLIC",
				ResolveStrategy:       ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE,
				PackageVersion:        "1.0.0",
				PackageManifestDigest: "sha256:1234",
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:                    43,
				Name:                  "org1/public2",
				ResolvedName:          "org1/public2",
				ResolvedSha:           "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:                "https://ghcr.io/v2/org1/public2/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:                   "action2",
				ZipUrl:                "https://ghcr.io/v2/org1/public2/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:            "PUBLIC",
				ResolveStrategy:       ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE,
				PackageVersion:        "1.0.0",
				PackageManifestDigest: "sha256:1234",
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              44,
				Name:            "org1/internal",
				ResolvedName:    "org1/internal",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/internal/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action",
				ZipUrl:          "https://ghes/org1/internal/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4,zip",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              45,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action1",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              45,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				Ref:             "action2",
				ZipUrl:          "https://ghes/org1/private1/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "org1/public1",
				Ref: "action1",
			},
			{
				Nwo: "org1/public2",
				Ref: "action2",
			},
			{
				Nwo: "org1/internal",
				Ref: "action",
			},
			{
				Nwo: "org1/private1",
				Ref: "action1",
			},
			{
				Nwo: "org1/private1",
				Ref: "action2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return(mockResolveActionsResponse, nil)

	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	mockClientFactory := github.NewMockClientFactory()
	s.svc.cfg.ClientFactory = mockClientFactory

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
		WorkflowMetadata: &metadata.WorkflowMetadata{
			Repository: &metadata.WorkflowRepositoryMetadata{
				ID:            3,
				GlobalRelayID: "R_kgAD",
			},
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				Login: "sourceOwner",
			},
		},
	}
	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, []string{"internal", "private1"}, false).Return(token3, nil).Once()

	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	expectedActionsMap := make(map[string]*ghactions.ResolvedAction)
	for _, expected := range mockResolveActionsResponse {
		expectedActionsMap[expected.ResolvedAction.ResolvedName+"@"+expected.ResolvedAction.Ref] = expected.ResolvedAction
	}

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 5)
	s.Len(res.Errors, 0)
	// Verify that the resolved actions match the expected actions
	for _, action := range res.Actions {
		expectedAction := expectedActionsMap[action.Action.Name+"@"+action.Action.Version]
		s.Equal(expectedAction.ResolvedName, action.ResolvedName)
		s.Equal(expectedAction.ResolvedSha, action.ResolvedSha)
		s.Equal(expectedAction.TarUrl, action.TarUrl)
		s.Equal(expectedAction.ZipUrl, action.ZipUrl)

		if expectedAction.ResolveStrategy == ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY && expectedAction.Visibility != "PUBLIC" {
			s.NotNil(action.Authentication)
		} else {
			s.Nil(action.Authentication)
		}

		if expectedAction.ResolveStrategy == ghactions.ResolveStrategy_RESOLVE_STRATEGY_PACKAGE {
			s.NotNil(action.PackageDetails)
			s.Equal(expectedAction.PackageVersion, action.PackageDetails.Version)
			s.Equal(expectedAction.PackageManifestDigest, action.PackageDetails.ManifestDigest)
		} else {
			s.Nil(action.PackageDetails)
		}

	}

	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestProximaResolveActionsWithDotcomFallbackForPublicRepos() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "actions/checkout",
				Version: "v1",
			},
			{
				Name:    "actions/setup-go",
				Version: "v1",
			},
			{
				Name:    "actions/non-existing-action",
				Version: "v1",
			},
			{
				Name:    "org1/action1",
				Version: "v2",
			},
		},
	}
	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	connectToken := &tokens.AccessToken{
		Token: "test-connect-token",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("RetireNamespace", mock.Anything, "actions/checkout").Return(nil)
	mockTwirpClient.On("RetireNamespace", mock.Anything, "actions/setup-go").Return(nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "actions/checkout",
				Ref: "v1",
			},
			{
				Nwo: "actions/setup-go",
				Ref: "v1",
			},
			{
				Nwo: "actions/non-existing-action",
				Ref: "v1",
			},
			{
				Nwo: "org1/action1",
				Ref: "v2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			Error: &ghtwirp.ResolveActionsErr{
				Err: errors.New("action not found"),
				Action: &ghtwirp.Action{
					Nwo: "actions/checkout",
					Ref: "v1",
				},
				ErrorCode: 404,
			},
		},
		{
			Error: &ghtwirp.ResolveActionsErr{
				Err: errors.New("action not found"),
				Action: &ghtwirp.Action{
					Nwo: "actions/setup-go",
					Ref: "v1",
				},
				ErrorCode: 404,
			},
		},
		{
			Error: &ghtwirp.ResolveActionsErr{
				Err: errors.New("action not found"),
				Action: &ghtwirp.Action{
					Nwo: "actions/non-existing-action",
					Ref: "v1",
				},
				ErrorCode: 404,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:           42,
				Name:         "org1/action1",
				ResolvedName: "org1/action1",
				ResolvedSha:  "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:       "https://ghcr.io/v2/org1/action1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:          "v2",
				ZipUrl:       "https://ghcr.io/v2/org1/action1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:   "PUBLIC",
			},
		},
	}, nil)

	mockResolverTokenFactory := &mockResolverTokenFactory{accessToken: connectToken}
	s.svc.cfg.ResolverTokenFactory = mockResolverTokenFactory

	srv, mux, teardown := newRemoteServer(s.T())
	defer teardown()

	mux.HandleFunc("/repos/actions/checkout/actions/resolve/v1", func(w http.ResponseWriter, req *http.Request) {
		s.Assert().Equal(req.Header.Get("Authorization"), "Bearer test-connect-token")
		s.Assert().Equal(req.URL.Query().Get("workflowRunId"), "0") // Workflow Run ID should not be passed for Connect requests
		_, _ = w.Write([]byte(`
			{
				"name": "actions/checkout",
				"resolved_name": "actions/checkout",
				"resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				"tar_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				"version": "v1",
				"zip_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip"
			}
		`))
	})

	mux.HandleFunc("/repos/actions/setup-go/actions/resolve/v1", func(w http.ResponseWriter, req *http.Request) {
		s.Assert().Equal(req.Header.Get("Authorization"), "Bearer test-connect-token")
		s.Assert().Equal(req.URL.Query().Get("workflowRunId"), "0") // Workflow Run ID should not be passed for Connect requests
		_, _ = w.Write([]byte(`
			{
				"name": "actions/setup-go",
				"resolved_name": "actions/setup-go",
				"resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				"tar_url": "https://ghes/actions/setup-go/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				"version": "v1",
				"zip_url": "https://ghes/actions/setup-go/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip"
			}
		`))
	})

	mux.HandleFunc("/repos/actions/non-existing-action/actions/resolve/v1", func(w http.ResponseWriter, req *http.Request) {
		s.Assert().Equal(req.Header.Get("Authorization"), "Bearer test-connect-token")
		s.Assert().Equal(req.URL.Query().Get("workflowRunId"), "0") // Workflow Run ID should not be passed for Connect requests
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`
		{
			"message": "Unable to resolve action"
		}`))
	})

	url, err := url.Parse(srv.URL)
	s.NoError(err)

	s.svc.cfg.InternalClientFactory = ghinternal.NewTestFactory(url, observability.NewNullObservability(), testutils.NewNoopBreaker(), []byte("testsigningkey"))

	res, _ := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 3)
	s.Len(res.Errors, 1)

	s.Equal(mockResolverTokenFactory.callCount, 1, "expected resolver token factory to be called twice")
	var expectedResolvedAction *pb.ResolvedAction
	for _, action := range res.Actions {
		if action.Action.Name == "actions/checkout" {
			expectedResolvedAction = action
			break
		}
	}
	s.NotNil(expectedResolvedAction)
	s.Equal("actions/checkout", expectedResolvedAction.GetResolvedName())
	s.Equal("2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3", expectedResolvedAction.GetResolvedSha())
	s.Equal("v1", expectedResolvedAction.Action.GetVersion())
	s.Equal(connectToken.Token, expectedResolvedAction.GetAuthentication().GetToken())

	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestProximaResolveActionsWithDotcomFallbackForInternalRepos() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "actions/checkout",
				Version: "v1",
			},
			{
				Name:    "org1/public1",
				Version: "v2",
			},
			{
				Name:    "org1/internal1",
				Version: "v2",
			},
		},
	}
	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	connectToken := &tokens.AccessToken{
		Token: "test-connect-token",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("RetireNamespace", mock.Anything, "actions/checkout").Return(nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "actions/checkout",
				Ref: "v1",
			},
			{
				Nwo: "org1/public1",
				Ref: "v2",
			},
			{
				Nwo: "org1/internal1",
				Ref: "v2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			Error: &ghtwirp.ResolveActionsErr{
				Err: errors.New("action not found"),
				Action: &ghtwirp.Action{
					Nwo: "actions/checkout",
					Ref: "v1",
				},
				ErrorCode: 404,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghcr.io/v2/org1/public1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:             "v2",
				ZipUrl:          "https://ghcr.io/v2/org1/public1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/internal1",
				ResolvedName:    "org1/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghcr.io/v2/org1/internal1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:             "v2",
				ZipUrl:          "https://ghcr.io/v2/org1/internal1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)

	mockResolverTokenFactory := &mockResolverTokenFactory{accessToken: connectToken}
	s.svc.cfg.ResolverTokenFactory = mockResolverTokenFactory

	srv, mux, teardown := newRemoteServer(s.T())
	defer teardown()

	mux.HandleFunc("/repos/actions/checkout/actions/resolve/v1", func(w http.ResponseWriter, req *http.Request) {
		s.Assert().Equal(req.Header.Get("Authorization"), "Bearer test-connect-token")
		s.Assert().Equal(req.URL.Query().Get("workflowRunId"), "0") // Workflow Run ID should not be passed for Connect requests
		_, _ = w.Write([]byte(`
			{
				"name": "actions/checkout",
				"resolved_name": "actions/checkout",
				"resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				"tar_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				"version": "v1",
				"zip_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip"
			}
		`))
	})

	url, err := url.Parse(srv.URL)
	s.NoError(err)

	s.svc.cfg.InternalClientFactory = ghinternal.NewTestFactory(url, observability.NewNullObservability(), testutils.NewNoopBreaker(), []byte("testsigningkey"))

	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, []string{"internal1"}, false).Return(token3, nil).Once()
	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, _ := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 3)
	s.Len(res.Errors, 0)

	s.Equal(mockResolverTokenFactory.callCount, 1, "expected resolver token factory to be called once")
	var expectedResolvedAction *pb.ResolvedAction
	for _, action := range res.Actions {
		if action.Action.Name == "actions/checkout" {
			expectedResolvedAction = action
			break
		}
	}
	s.NotNil(expectedResolvedAction)
	s.Equal("actions/checkout", expectedResolvedAction.GetResolvedName())
	s.Equal("2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3", expectedResolvedAction.GetResolvedSha())
	s.Equal("v1", expectedResolvedAction.Action.GetVersion())
	s.Equal(connectToken.Token, expectedResolvedAction.GetAuthentication().GetToken())

	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestProximaResolveActionsWithDotcomFallbackForPrivateRepos() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "actions/checkout",
				Version: "v1",
			},
			{
				Name:    "org1/public1",
				Version: "v2",
			},
			{
				Name:    "org1/internal1",
				Version: "v2",
			},
			{
				Name:    "org1/private1",
				Version: "v2",
			},
		},
	}
	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	connectToken := &tokens.AccessToken{
		Token: "test-connect-token",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("RetireNamespace", mock.Anything, "actions/checkout").Return(nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "actions/checkout",
				Ref: "v1",
			},
			{
				Nwo: "org1/public1",
				Ref: "v2",
			},
			{
				Nwo: "org1/internal1",
				Ref: "v2",
			},
			{
				Nwo: "org1/private1",
				Ref: "v2",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			Error: &ghtwirp.ResolveActionsErr{
				Err: errors.New("action not found"),
				Action: &ghtwirp.Action{
					Nwo: "actions/checkout",
					Ref: "v1",
				},
				ErrorCode: 404,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/public1",
				ResolvedName:    "org1/public1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghcr.io/v2/org1/public1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:             "v2",
				ZipUrl:          "https://ghcr.io/v2/org1/public1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:      "PUBLIC",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              42,
				Name:            "org1/internal1",
				ResolvedName:    "org1/internal1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghcr.io/v2/org1/internal1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:             "v2",
				ZipUrl:          "https://ghcr.io/v2/org1/internal1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:      "INTERNAL",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
		{
			ResolvedAction: &ghactions.ResolvedAction{
				Id:              43,
				Name:            "org1/private1",
				ResolvedName:    "org1/private1",
				ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:          "https://ghcr.io/v2/org1/private1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				Ref:             "v2",
				ZipUrl:          "https://ghcr.io/v2/org1/private1/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc4",
				Visibility:      "PRIVATE",
				ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
			},
		},
	}, nil)

	mockResolverTokenFactory := &mockResolverTokenFactory{accessToken: connectToken}
	s.svc.cfg.ResolverTokenFactory = mockResolverTokenFactory

	srv, mux, teardown := newRemoteServer(s.T())
	defer teardown()

	mux.HandleFunc("/repos/actions/checkout/actions/resolve/v1", func(w http.ResponseWriter, req *http.Request) {
		s.Assert().Equal(req.Header.Get("Authorization"), "Bearer test-connect-token")
		s.Assert().Equal(req.URL.Query().Get("workflowRunId"), "0") // Workflow Run ID should not be passed for Connect requests
		_, _ = w.Write([]byte(`
			{
				"name": "actions/checkout",
				"resolved_name": "actions/checkout",
				"resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				"tar_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				"version": "v1",
				"zip_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip"
			}
		`))
	})

	url, err := url.Parse(srv.URL)
	s.NoError(err)

	s.svc.cfg.InternalClientFactory = ghinternal.NewTestFactory(url, observability.NewNullObservability(), testutils.NewNoopBreaker(), []byte("testsigningkey"))

	token3 := &tokens.AccessToken{
		Token: "test-token-3",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, []string{"internal1", "private1"}, false).Return(token3, nil).Once()
	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	res, _ := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 4)
	s.Len(res.Errors, 0)

	s.Equal(mockResolverTokenFactory.callCount, 1, "expected resolver token factory to be called once")
	var expectedResolvedAction *pb.ResolvedAction
	for _, action := range res.Actions {
		if action.Action.Name == "actions/checkout" {
			expectedResolvedAction = action
			break
		}
	}
	s.NotNil(expectedResolvedAction)
	s.Equal("actions/checkout", expectedResolvedAction.GetResolvedName())
	s.Equal("2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3", expectedResolvedAction.GetResolvedSha())
	s.Equal("v1", expectedResolvedAction.Action.GetVersion())
	s.Equal(connectToken.Token, expectedResolvedAction.GetAuthentication().GetToken())

	s.assertExpectations(mockTwirpClient)
}

// Immutable actions Proxima fallback
func (s *resolveActionsWithTwirpSuite) TestProximaResolveActionsWithDotcomFallbackWithPackages() {
	req := &pb.ResolveActionsRequest{
		WorkflowId: s.workflowID,
		JobId:      s.jobID,
		Actions: []*pb.ActionReference{
			{
				Name:    "actions/checkout",
				Version: "v1",
			},
		},
	}
	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	connectToken := &tokens.AccessToken{
		Token: "test-connect-token",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("RetireNamespace", mock.Anything, "actions/checkout").Return(nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	mockTwirpClient.On("ResolveActions",
		mock.Anything,
		[]*ghtwirp.Action{
			{
				Nwo: "actions/checkout",
				Ref: "v1",
			},
		},
		mock.Anything,
		mock.Anything,
		mock.Anything,
		true,
		mock.Anything).Return([]*ghtwirp.ResolveActionsResponse{
		{
			Error: &ghtwirp.ResolveActionsErr{
				Err: errors.New("action not found"),
				Action: &ghtwirp.Action{
					Nwo: "actions/checkout",
					Ref: "v1",
				},
				ErrorCode: 404,
			},
		},
	}, nil)

	mockResolverTokenFactory := &mockResolverTokenFactory{accessToken: connectToken}
	s.svc.cfg.ResolverTokenFactory = mockResolverTokenFactory

	srv, mux, teardown := newRemoteServer(s.T())
	defer teardown()

	mux.HandleFunc("/repos/actions/checkout/actions/resolve/v1", func(w http.ResponseWriter, req *http.Request) {
		s.Assert().Equal(req.Header.Get("Authorization"), "Bearer test-connect-token")
		s.Assert().Equal(req.URL.Query().Get("workflowRunId"), "0") // Workflow Run ID should not be passed for Connect requests
		_, _ = w.Write([]byte(`
			{
				"name": "actions/checkout",
				"resolved_name": "actions/checkout",
				"resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				"tar_url": "https://ghcr.io/v2/actions/checkout/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				"version": "v1",
				"zip_url": "https://ghcr.io/v2/actions/checkout/blobs/sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				"package_version": "v1.0.0",
				"package_manifest_digest": "sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3"
			}
		`))
	})

	url, err := url.Parse(srv.URL)
	s.NoError(err)

	s.svc.cfg.InternalClientFactory = ghinternal.NewTestFactory(url, observability.NewNullObservability(), testutils.NewNoopBreaker(), []byte("testsigningkey"))

	res, _ := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 1)
	s.Len(res.Errors, 0)

	s.Equal(mockResolverTokenFactory.callCount, 1, "expected resolver token factory to be called twice")

	expectedResolvedAction := res.Actions[0]
	s.NotNil(expectedResolvedAction)
	s.Equal("actions/checkout", expectedResolvedAction.ResolvedName)
	s.Equal("2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3", expectedResolvedAction.ResolvedSha)
	s.Equal("v1", expectedResolvedAction.Action.Version)
	s.Equal(connectToken.Token, expectedResolvedAction.Authentication.Token)
	s.Equal("v1.0.0", expectedResolvedAction.PackageDetails.Version)
	s.Equal("sha256:2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3", expectedResolvedAction.PackageDetails.ManifestDigest)

	s.assertExpectations(mockTwirpClient)
}

func (s *resolveActionsWithTwirpSuite) TestIsHostedRunnerIsIncludedInTwirpCall() {
	testCases := []struct {
		name           string
		isHostedRunner bool
	}{
		{
			name:           "hosted runner",
			isHostedRunner: true,
		},
		{
			name:           "self-hosted or larger runner",
			isHostedRunner: false,
		},
	}

	for _, tc := range testCases {
		req := &pb.ResolveActionsRequest{
			WorkflowId: s.workflowID,
			JobId:      s.jobID,
			Actions: []*pb.ActionReference{
				{
					Name:    s.actionName,
					Version: s.actionTag,
				},
			},
			IsHostedRunner: tc.isHostedRunner,
		}

		mockTwirpClient := &ghtwirp.MockClient{}
		actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
			IsExecutionAllowed: true,
		}
		mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(actionsPolicyInfo, nil)
		mockTwirpClient.On("ResolveActions",
			mock.Anything,
			[]*ghtwirp.Action{
				{
					Nwo: s.actionName,
					Ref: s.actionTag,
				},
			},
			mock.Anything,
			mock.Anything,
			mock.Anything,
			true,
			tc.isHostedRunner).Return([]*ghtwirp.ResolveActionsResponse{
			{
				ResolvedAction: &ghactions.ResolvedAction{
					Id:              100,
					Name:            "actions/checkout",
					ResolvedName:    "actions/checkout",
					ResolvedSha:     "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
					TarUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
					Ref:             "v2",
					ZipUrl:          "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
					Visibility:      "PUBLIC",
					ResolveStrategy: ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY,
				},
			},
		}, nil)
		s.svc.cfg.GithubTwirpClient = mockTwirpClient

		workflowRunID := int64(128)
		dftr := &deployer.DataForTokenRequest{
			RepositoryID:     types.GlobalID("R_kgAO"),
			WorkflowRunID:    workflowRunID,
			WorkflowFilePath: ".github/workflows/test.yml",
		}
		s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

		res, err := s.svc.ResolveActions(context.Background(), req)
		s.Require().NoError(err)
		s.Len(res.Actions, 1)
		s.assertExpectations(mockTwirpClient)
	}
}

func (s *resolveActionsWithTwirpSuite) TestBuildTwirpErrorResponseTreatsUserErrorAsUserError() {
	resp, err := s.svc.buildTwirpErrorResponse(context.Background(), []*pb.ActionReference{
		{
			Name:    s.actionName,
			Version: s.actionTag,
		},
	}, errors.New("action not found"))

	s.Require().NoError(err)
	s.Require().NotNil(resp)
	s.Len(resp.Errors, 1) // user errors are returned in `resp.Errors`
}

func (s *resolveActionsWithTwirpSuite) TestBuildTwirpErrorResponseDoesNotTreatTwirpRateLimitErrorAsUserError() {
	resp, err := s.svc.buildTwirpErrorResponse(context.Background(), []*pb.ActionReference{
		{
			Name:    s.actionName,
			Version: s.actionTag,
		},
	}, ratelimit.NewMockRateLimitError("internal twirp api rate limited", 403))

	s.Require().Error(err)
	s.Require().Nil(resp)
}
