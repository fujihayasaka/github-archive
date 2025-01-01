package deploy

import (
	context "context"
	fmt "fmt"
	http "net/http"
	"net/http/httptest"
	"net/url"
	strconv "strconv"
	"strings"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/twitchtv/twirp"

	authzpb "github.com/github/authzd/pkg/proto"

	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/ghinternal"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/cache/cachemem"
	"github.com/github/launch/pkg/launchcache"
	ghactions "github.com/github/launch/proto/monolith/core/v1"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workerpool"
	"github.com/github/launch/workflowbuild"
)

func TestResolveActions(t *testing.T) {
	suite.Run(t, new(resolveActionsSuite))
}

type resolveActionsSuite struct {
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

var (
	metadataPermissions = &tokens.InstallationPermissions{
		Metadata: tokens.ReadAccess,
	}
)

func (s *resolveActionsSuite) SetupTest() {
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

type MockAuthzClientAllow struct{}

func (autzs *MockAuthzClientAllow) BatchAuthorize(_ context.Context, _ *authzpb.BatchRequest) (*authzpb.BatchDecision, error) {
	return &authzpb.BatchDecision{Decisions: []*authzpb.Decision{{Result: authzpb.Result(authzpb.Result_ALLOW)}}}, nil
}
func (autzs *MockAuthzClientAllow) Authorize(_ context.Context, _ *authzpb.Request) (*authzpb.Decision, error) {
	return &authzpb.Decision{Result: authzpb.Result(authzpb.Result_ALLOW)}, nil
}

type MockAuthzClientDeny struct{}

func (autzs *MockAuthzClientDeny) BatchAuthorize(_ context.Context, _ *authzpb.BatchRequest) (*authzpb.BatchDecision, error) {
	return &authzpb.BatchDecision{Decisions: []*authzpb.Decision{{Result: authzpb.Result(authzpb.Result_DENY)}}}, nil
}
func (autzs *MockAuthzClientDeny) Authorize(_ context.Context, _ *authzpb.Request) (*authzpb.Decision, error) {
	return nil, nil
}

type MockAuthzClientAllowDeny struct {
	allowList []bool
}

func (autzs *MockAuthzClientAllowDeny) BatchAuthorize(_ context.Context, _ *authzpb.BatchRequest) (*authzpb.BatchDecision, error) {
	resultList := []*authzpb.Decision{}
	for _, decision := range autzs.allowList {
		if decision {
			resultList = append(resultList, &authzpb.Decision{Result: authzpb.Result(authzpb.Result_ALLOW)})
		} else {
			resultList = append(resultList, &authzpb.Decision{Result: authzpb.Result(authzpb.Result_DENY)})
		}
	}
	return &authzpb.BatchDecision{Decisions: resultList}, nil
}
func (autzs *MockAuthzClientAllowDeny) Authorize(_ context.Context, _ *authzpb.Request) (*authzpb.Decision, error) {
	return nil, nil
}

type mockResolverTokenFactory struct {
	accessToken *tokens.AccessToken
	callCount   int
}

func (r *mockResolverTokenFactory) GetToken(ctx context.Context) (*tokens.AccessToken, error) {
	r.callCount++
	return r.accessToken, nil
}

func (s *resolveActionsSuite) TestReturns404WithExtraContextOnEnterpriseWithoutConnect() {
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

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	token := &tokens.AccessToken{}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wtf.On("NewToken", mock.Anything, types.GlobalID("R_kgAO"), metadataPermissions, mock.Anything).Return(token, nil)

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, true, false).Return(actionsPolicyInfo, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	s.svc.IsEnterprise = true

	srv, mux, teardown := newRemoteServer(s.T())
	defer teardown()

	numResolveCalls := 0
	mux.HandleFunc("/repos/actions/checkout/actions/resolve/v2", func(w http.ResponseWriter, req *http.Request) {
		s.Assert().Equal(req.URL.Query().Get("workflowRunId"), strconv.FormatInt(workflowRunID, 10))
		_, _ = w.Write([]byte(`
		{
			"name": "actions/checkout",
			"resolved_name": "actions/checkout",
			"resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
			"tar_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
			"version": "v2",
			"zip_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
			"visibility": "PUBLIC"
		}
		`))
	})

	mux.HandleFunc("/repos/invalid/repository/actions/resolve/action", func(w http.ResponseWriter, req *http.Request) {
		s.Assert().Equal(req.URL.Query().Get("workflowRunId"), strconv.FormatInt(workflowRunID, 10))
		w.WriteHeader(http.StatusNotFound)

		_, _ = w.Write([]byte(`
{ "message": "Not Found" }`))

		numResolveCalls++
	})

	numTokenCalls := 0
	mux.HandleFunc("/enterprise/actions-token", func(w http.ResponseWriter, req *http.Request) {
		w.WriteHeader(http.StatusNotFound)

		numTokenCalls++
	})
	url, err := url.Parse(srv.URL)
	s.NoError(err)

	s.svc.cfg.InternalClientFactory = ghinternal.NewTestFactory(url, observability.NewNullObservability(), testutils.NewNoopBreaker(), []byte("testsigningkey"))

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)

	s.Len(res.Actions, 0)
	s.Len(res.Errors, 1)

	s.Equal(numResolveCalls, 1, "expected resolver to be called once")
	s.Equal(numTokenCalls, 1, "expected enterprise token to be fetched once")
	s.Equal("invalid/repository", res.Errors[0].Action.GetName())
	s.Equal("action", res.Errors[0].Action.GetVersion())
	s.Equal("Unable to resolve action `invalid/repository@action`, repository not found on this server. If you want to use this action from GitHub.com, see the following documentation: https://docs.github.com/en/enterprise/admin/github-actions/managing-access-to-actions-from-githubcom", res.Errors[0].GetMessage())
	s.wfb.AssertExpectations(s.T())
	s.wtf.AssertExpectations(s.T())
}

func (s *resolveActionsSuite) TestThatActionsCanBeResolvedOnEnterprise() {
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
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, true, false).Return(actionsPolicyInfo, nil)

	actionRepos := &ghtwirp.RepositoriesInfo{
		Repositories: []*ghactions.Repository{
			{
				Id:            42,
				Name:          "checkout",
				GlobalRelayId: "MDQ6VXNlcjI=",
				OwnerLogin:    "actions",
				Visibility:    ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC,
			},
		},
		RepositoriesNotFoundErrorMessage: "",
	}
	mockTwirpClient.On("FindRepositoriesByName", mock.Anything, mock.Anything).Return(actionRepos, nil)

	s.svc.cfg.GithubTwirpClient = mockTwirpClient
	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())

	s.svc.IsEnterprise = true

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	token2 := &tokens.AccessToken{
		Token: "test-token-2",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wtf.On("NewToken", mock.Anything, mock.Anything, metadataPermissions, mock.Anything).Return(token2, nil)

	srv, mux, teardown := newRemoteServer(s.T())
	defer teardown()

	mux.HandleFunc("/repos/actions/checkout/actions/resolve/v2", func(w http.ResponseWriter, req *http.Request) {
		s.Assert().Equal(req.URL.Query().Get("workflowRunId"), strconv.FormatInt(workflowRunID, 10))
		_, _ = w.Write([]byte(`
		{
			"name": "actions/checkout",
			"resolved_name": "actions/checkout",
			"resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
			"tar_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
			"version": "v2",
			"zip_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
			"visibility": "PUBLIC"
		}
		`))
	})

	url, err := url.Parse(srv.URL)
	s.NoError(err)

	s.svc.cfg.InternalClientFactory = ghinternal.NewTestFactory(url, observability.NewNullObservability(), testutils.NewNoopBreaker(), []byte("testsigningkey"))

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 1)
	s.Equal(s.actionName, res.Actions[0].Action.GetName())
	s.NotNil(res.Actions[0].Authentication)
	s.Equal(token2.Token, res.Actions[0].Authentication.Token)
	s.Equal(s.actionName, res.Actions[0].GetResolvedName())
	s.Equal(s.actionSHA, res.Actions[0].GetResolvedSha())
	s.Equal(s.actionTag, res.Actions[0].Action.GetVersion())

	s.wfb.AssertExpectations(s.T())
	s.wtf.AssertExpectations(s.T())
}

func (s *resolveActionsSuite) TestThatPublicAndPrivateAndInternalActionsOfSameOrgCanBeResolvedOnEnterprise() {
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

	orgID := int64(16631042)
	orgGlobalID := types.GlobalID("O_kgDOAP3FAg")

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, true, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org1").Return(orgID, orgGlobalID, nil).Once()

	actionRepos := &ghtwirp.RepositoriesInfo{
		Repositories: []*ghactions.Repository{
			{
				Id:            42,
				Name:          "public1",
				GlobalRelayId: "MDQ6BXNlcjI=",
				OwnerLogin:    "org1",
				Visibility:    1,
			},
			{
				Id:            43,
				Name:          "internal1",
				GlobalRelayId: "KDQ6VXNlcjI=",
				OwnerLogin:    "org1",
				Visibility:    3,
			},
			{
				Id:            44,
				Name:          "private1",
				GlobalRelayId: "MDQ6VVNlcjI=",
				OwnerLogin:    "org1",
				Visibility:    2,
			},
		},
		RepositoriesNotFoundErrorMessage: "",
	}

	mockTwirpClient.On("FindRepositoriesByName", mock.Anything, mock.Anything).Return(actionRepos, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient
	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())
	s.svc.IsEnterprise = true
	s.svc.cfg.AppEnv = "production"

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	token := &tokens.AccessToken{
		Token: "test-token",
	}
	token2 := &tokens.AccessToken{
		Token: "test-token-2",
	}

	// We won't scope the token to the public repository
	reposForTokenScope := []string{"internal1", "private1"}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wtf.On("NewToken", mock.Anything, dftr.RepositoryID, metadataPermissions, mock.Anything).Return(token, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, reposForTokenScope, false, mock.Anything).Return(token2, nil).Once()

	action1 := &ghinternal.ResolvedAction{ResolvedName: "org1/public1", Visibility: "PUBLIC"}
	action2 := &ghinternal.ResolvedAction{ResolvedName: "org1/internal1", Visibility: "INTERNAL"}
	action3 := &ghinternal.ResolvedAction{ResolvedName: "org1/private1", Visibility: "PRIVATE"}
	mockInternalClient := &ghinternal.MockClient{}
	mockInternalClient.On("ResolveAction", mock.Anything, "org1/public1", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(action1, nil).Once()
	mockInternalClient.On("ResolveAction", mock.Anything, "org1/internal1", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(action2, nil).Once()
	mockInternalClient.On("ResolveAction", mock.Anything, "org1/private1", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(action3, nil).Once()
	mockInternalClientFactory := &ghinternal.MockFactory{}
	mockInternalClientFactory.On("CreateWithAccessToken", mock.Anything).Return(mockInternalClient, nil)
	s.svc.cfg.InternalClientFactory = mockInternalClientFactory

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 3)
	for _, action := range res.Actions {
		s.NotNil(action.Authentication)
		if action.Action.Name == "org1/public1" {
			s.Equal(token.Token, action.Authentication.Token)
		} else {
			s.Equal(token2.Token, action.Authentication.Token)
		}
	}
	s.Len(res.Errors, 0)
	s.wfb.AssertExpectations(s.T())
	s.wtf.AssertExpectations(s.T())
	s.wts.AssertExpectations(s.T())
	mockTwirpClient.AssertExpectations(s.T())
}

func (s *resolveActionsSuite) TestThatPublicAndPrivateAndInternalActionsOfAnotherOrgCanBeResolvedOnEnterprise() {
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

	orgID := int64(9919)
	orgGlobalID := types.GlobalID("O_kgDNJr8")

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
		ArePrivateActionsAllowed:  true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, true, false).Return(actionsPolicyInfo, nil)
	mockTwirpClient.On("GetUserByLogin", mock.Anything, "org2").Return(orgID, orgGlobalID, nil).Once()

	actionRepos := &ghtwirp.RepositoriesInfo{
		Repositories: []*ghactions.Repository{
			{
				Id:            42,
				Name:          "public1",
				GlobalRelayId: "MDQ6BXNlcjI=",
				OwnerLogin:    "org2",
				Visibility:    1,
			},
			{
				Id:            43,
				Name:          "internal1",
				GlobalRelayId: "KDQ6VXNlcjI=",
				OwnerLogin:    "org2",
				Visibility:    3,
			},
			{
				Id:            44,
				Name:          "private1",
				GlobalRelayId: "MDQ6VVNlcjI=",
				OwnerLogin:    "org2",
				Visibility:    2,
			},
		},
		RepositoriesNotFoundErrorMessage: "",
	}

	mockTwirpClient.On("FindRepositoriesByName", mock.Anything, mock.Anything).Return(actionRepos, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient
	s.svc.AuthzClient = authzd.NewTestClient(&MockAuthzClientAllow{}, observability.NewTestObservability())
	s.svc.IsEnterprise = true
	s.svc.cfg.AppEnv = "production"

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("MDEwOlJlcG9zaXRvcnkxMDQ3OTM4MzM="),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	token := &tokens.AccessToken{
		Token: "test-token",
	}
	token2 := &tokens.AccessToken{
		Token: "test-token-2",
	}

	// We won't scope the token to the public repository
	reposForTokenScope := []string{"internal1", "private1"}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wtf.On("NewToken", mock.Anything, dftr.RepositoryID, metadataPermissions, mock.Anything).Return(token, nil)
	s.wts.On("ReadTokenForSiteScopedInstallation", mock.Anything, orgID, reposForTokenScope, false, mock.Anything).Return(token2, nil).Once()

	action1 := &ghinternal.ResolvedAction{ResolvedName: "org2/public1", Visibility: "PUBLIC"}
	action2 := &ghinternal.ResolvedAction{ResolvedName: "org2/internal1", Visibility: "INTERNAL"}
	action3 := &ghinternal.ResolvedAction{ResolvedName: "org2/private1", Visibility: "PRIVATE"}
	mockInternalClient := &ghinternal.MockClient{}
	mockInternalClient.On("ResolveAction", mock.Anything, "org2/public1", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(action1, nil).Once()
	mockInternalClient.On("ResolveAction", mock.Anything, "org2/internal1", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(action2, nil).Once()
	mockInternalClient.On("ResolveAction", mock.Anything, "org2/private1", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(action3, nil).Once()
	mockInternalClientFactory := &ghinternal.MockFactory{}
	mockInternalClientFactory.On("CreateWithAccessToken", mock.Anything).Return(mockInternalClient, nil)
	s.svc.cfg.InternalClientFactory = mockInternalClientFactory

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 3)
	for _, action := range res.Actions {
		s.NotNil(action.Authentication)
		if action.Action.Name == "org2/public1" {
			s.Equal(token.Token, action.Authentication.Token)
		} else {
			s.Equal(token2.Token, action.Authentication.Token)
		}
	}
	s.Len(res.Errors, 0)
	s.wfb.AssertExpectations(s.T())
	s.wtf.AssertExpectations(s.T())
	s.wts.AssertExpectations(s.T())
	mockTwirpClient.AssertExpectations(s.T())
}

func (s *resolveActionsSuite) TestThatActionsCanBeResolvedOnEnterpriseWithConnect() {
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

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	token := &tokens.AccessToken{
		Token: "test-token",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wtf.On("NewToken", mock.Anything, types.GlobalID("R_kgAO"), metadataPermissions, mock.Anything).Return(token, nil)

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed:        true,
		AreInternalActionsAllowed: true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, true, false).Return(actionsPolicyInfo, nil)

	actionRepos := &ghtwirp.RepositoriesInfo{
		Repositories:                     []*ghactions.Repository{},
		RepositoriesNotFoundErrorMessage: "",
	}
	actionRepoNames := []string{strings.ToLower(s.actionName)}
	mockTwirpClient.On("FindRepositoriesByName", mock.Anything, actionRepoNames).Return(actionRepos, nil)
	mockTwirpClient.On("RetireNamespace", mock.Anything, s.actionName).Return(nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	s.svc.IsEnterprise = true

	srv, mux, teardown := newRemoteServer(s.T())
	defer teardown()

	numResolveCalls := 0
	mux.HandleFunc("/repos/actions/checkout/actions/resolve/v2", func(w http.ResponseWriter, req *http.Request) {
		// For the first call, return a 404 response, so we can try the Connect fallback logic
		// fallback logic.
		if numResolveCalls == 0 {
			s.Assert().Equal(req.Header.Get("Authorization"), "Bearer test-token")
			s.Assert().Equal(req.URL.Query().Get("workflowRunId"), strconv.FormatInt(workflowRunID, 10))
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`
			{
				"message": "Unable to resolve action"
			}`))
		} else {
			s.Assert().Equal(req.Header.Get("Authorization"), "Bearer test-connect-token")
			s.Assert().Equal(req.URL.Query().Get("workflowRunId"), "0") // Workflow Run ID should not be passed for Connect requests
			_, _ = w.Write([]byte(`
			{
				"name": "actions/checkout",
				"resolved_name": "actions/checkout",
				"resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				"tar_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				"version": "v2",
				"zip_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
				"visibility": "PUBLIC"
			}
		`))
			w.WriteHeader(http.StatusOK)
		}

		numResolveCalls++
	})

	numTokenCalls := 0
	mux.HandleFunc("/enterprise/actions-token", func(w http.ResponseWriter, req *http.Request) {
		_, _ = w.Write([]byte(`
		{
			"token": "test-connect-token",
			"expires_at": "2020-06-12T16:44:50Z",
			"permissions": {},
			"repository_selection": "selected"
		}
		`))

		numTokenCalls++
	})

	url, err := url.Parse(srv.URL)
	s.NoError(err)

	s.svc.cfg.InternalClientFactory = ghinternal.NewTestFactory(url, observability.NewNullObservability(), testutils.NewNoopBreaker(), []byte("testsigningkey"))

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 1)
	s.Len(res.Errors, 0)

	s.Equal(numResolveCalls, 2, "expected resolver to be called twice")
	s.Equal(numTokenCalls, 1, "expected enterprise token to be fetched once")
	s.Equal(s.actionName, res.Actions[0].Action.GetName())
	s.Equal(s.actionName, res.Actions[0].GetResolvedName())
	s.Equal(s.actionSHA, res.Actions[0].GetResolvedSha())
	s.Equal(s.actionTag, res.Actions[0].Action.GetVersion())

	s.wfb.AssertExpectations(s.T())
	s.wtf.AssertExpectations(s.T())
	mockTwirpClient.AssertExpectations(s.T())
}

func (s *resolveActionsSuite) TestThatActionsOnEnterpriseDoesNotFallbackFor422s() {
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

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	token := &tokens.AccessToken{
		Token: "test-token",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wtf.On("NewToken", mock.Anything, types.GlobalID("R_kgAO"), metadataPermissions, mock.Anything).Return(token, nil)

	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
	}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, true, false).Return(actionsPolicyInfo, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	s.svc.IsEnterprise = true

	srv, mux, teardown := newRemoteServer(s.T())
	defer teardown()

	numResolveCalls := 0
	mux.HandleFunc("/repos/actions/checkout/actions/resolve/v2", func(w http.ResponseWriter, req *http.Request) {
		// Return a 422 to make sure that this is only called once
		if numResolveCalls == 0 {
			s.Assert().Equal(req.Header.Get("Authorization"), "Bearer test-token")
			s.Assert().Equal(req.URL.Query().Get("workflowRunId"), strconv.FormatInt(workflowRunID, 10))
		} else {
			s.Assert().Equal(req.Header.Get("Authorization"), "Bearer test-connect-token")
			s.Assert().Equal(req.URL.Query().Get("workflowRunId"), "0") // Workflow Run ID should not be passed for Connect requests
		}

		w.WriteHeader(http.StatusUnprocessableEntity)
		_, _ = w.Write([]byte(`
			{
				"message": "unable to resolve action, invalid ref"
			}`))
		numResolveCalls++
	})

	numTokenCalls := 0
	mux.HandleFunc("/enterprise/actions-token", func(w http.ResponseWriter, req *http.Request) {
		_, _ = w.Write([]byte(`
		{
			"token": "test-connect-token",
			"expires_at": "2020-06-12T16:44:50Z",
			"permissions": {},
			"repository_selection": "selected"
		}
		`))

		numTokenCalls++
	})

	url, err := url.Parse(srv.URL)
	s.NoError(err)

	s.svc.cfg.InternalClientFactory = ghinternal.NewTestFactory(url, observability.NewNullObservability(), testutils.NewNoopBreaker(), []byte("testsigningkey"))

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 0)
	s.Len(res.Errors, 1)

	s.Equal(numResolveCalls, 1, "expected resolver to be called once")
	s.Equal(numTokenCalls, 0, "expected enterprise token to be not be fetched")

	s.wfb.AssertExpectations(s.T())
	s.wtf.AssertExpectations(s.T())
}

func (s *resolveActionsSuite) TestThatActionsOnEnterpriseDoesNotFallbackForLocalOnlyActions() {
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

	repositoryId := types.GlobalID("R_kgAO")

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     repositoryId,
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}
	token := &tokens.AccessToken{
		Token: "test-token",
	}
	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)
	s.wtf.On("NewToken", mock.Anything, repositoryId, metadataPermissions, mock.Anything).Return(token, nil)

	action := fmt.Sprintf("%s@%s", req.Actions[0].Name, req.Actions[0].Version)
	mockTwirpClient := &ghtwirp.MockClient{}
	actionsPolicyInfo := &ghtwirp.ActionsPolicyInfo{
		IsExecutionAllowed: true,
		LocalOnlyActions:   []string{action},
	}
	mockTwirpClient.On("IsFeatureEnabledForActor", mock.Anything, mock.Anything, mock.Anything).Return(true)
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, repositoryId, []string{action}, true, false).Return(actionsPolicyInfo, nil)
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	s.svc.IsEnterprise = true

	srv, mux, teardown := newRemoteServer(s.T())
	defer teardown()

	numResolveCalls := 0
	mux.HandleFunc("/repos/actions/checkout/actions/resolve/v2", func(w http.ResponseWriter, req *http.Request) {
		// Only return 404 to reach Connect fallback logic
		s.Assert().Equal(req.Header.Get("Authorization"), "Bearer test-token")
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`
		{
			"message": "Unable to resolve action"
		}`))

		if numResolveCalls == 0 {
			s.Assert().Equal(req.URL.Query().Get("workflowRunId"), strconv.FormatInt(workflowRunID, 10))
		} else {
			s.Assert().Equal(req.URL.Query().Get("workflowRunId"), "0") // Workflow Run ID should not be passed for Connect requests
		}

		numResolveCalls++
	})

	numTokenCalls := 0
	mux.HandleFunc("/enterprise/actions-token", func(w http.ResponseWriter, req *http.Request) {
		_, _ = w.Write([]byte(`
		{
			"token": "test-connect-token",
			"expires_at": "2020-06-12T16:44:50Z",
			"permissions": {},
			"repository_selection": "selected"
		}
		`))

		numTokenCalls++
	})

	url, err := url.Parse(srv.URL)
	s.NoError(err)

	s.svc.cfg.InternalClientFactory = ghinternal.NewTestFactory(url, observability.NewNullObservability(), testutils.NewNoopBreaker(), []byte("testsigningkey"))

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().NoError(err)
	s.Len(res.Actions, 0)
	s.Len(res.Errors, 1)

	s.Equal(numResolveCalls, 1, "expected resolver to be called once")
	s.Equal(numTokenCalls, 0, "expected enterprise token to be not be fetched")
	s.wfb.AssertExpectations(s.T())
	s.wtf.AssertExpectations(s.T())
}

func (s *resolveActionsSuite) TestReturns404WhenPolicyCheckReturns404() {
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

	workflowRunID := int64(128)
	dftr := &deployer.DataForTokenRequest{
		RepositoryID:     types.GlobalID("R_kgAO"),
		WorkflowRunID:    workflowRunID,
		WorkflowFilePath: ".github/workflows/test.yml",
	}

	s.wfb.On("GetDataForTokenRequest", mock.Anything, s.workflowID).Return(dftr, true, nil)

	mockTwirpClient := &ghtwirp.MockClient{}
	mockTwirpClient.On("CheckActionsAllowedByPolicy", mock.Anything, mock.Anything, mock.Anything, false, false).Return(nil, twirp.NotFoundError("repository not found"))
	s.svc.cfg.GithubTwirpClient = mockTwirpClient

	res, err := s.svc.ResolveActions(context.Background(), req)
	s.Require().Nil(res)
	s.Require().Error(err)
	s.Require().Equal(err, svcerr.NewNotFoundError("Failed to retrieve Actions policy because the repository could not be found"))

	s.wfb.AssertExpectations(s.T())
	mockTwirpClient.AssertExpectations(s.T())
}

func newRemoteServer(t *testing.T) (*httptest.Server, *http.ServeMux, func()) {
	t.Helper()
	mux := http.NewServeMux()
	server := httptest.NewServer(mux)
	return server, mux, func() {
		server.Close()
	}
}
