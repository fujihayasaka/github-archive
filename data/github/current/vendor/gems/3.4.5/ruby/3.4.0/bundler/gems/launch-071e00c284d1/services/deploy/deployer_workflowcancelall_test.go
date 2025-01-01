package deploy

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/pkg/launchconfig"
	v1 "github.com/github/launch/proto/monolith/core/v1"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/services/deploy/adminevents"
	"github.com/github/launch/services/deploy/workflowcanceler"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/utils"
)

const (
	testRepoName  = "my-repo"
	testRepoOwner = "the-owner"

	testRepoID          = types.GlobalID("R_kgDNA-c") // [0, 999]
	testRepoOwnerID     = types.GlobalID("O_kgDNA-o") // [0, 1002]
	testRepoPlanOwnerID = types.GlobalID("O_kgDNA-o") // [0, 1002]
	testDatabaseID      = int64(999)
)

func TestDeployer_WorkflowCancelAll(t *testing.T) {
	suite.Run(t, new(WorkflowCancelAllSuite))
}

type WorkflowCancelAllSuite struct {
	suite.Suite
	svc           *service
	db            *deployer.MockWorkflowBuildsRepository
	canceler      *workflowcanceler.MockCanceler
	ghClient      *github.MockClient
	ghTwirpClient *ghtwirp.MockClient
	reporter      *adminevents.MockReporter
}

func (s *WorkflowCancelAllSuite) SetupSubTest() {
	s.SetupTest()
}

func (s *WorkflowCancelAllSuite) SetupTest() {
	log := logger.TestLogger()
	nullStatter := statter.NullStatter()
	publisher := &events.MockPublisher{}
	emitter, err := events.NewEmitter(
		events.WithPublisher(publisher),
		events.WithLogger(log),
		events.WithStatter(nullStatter),
	)
	s.Require().NoError(err)

	s.canceler = workflowcanceler.NewMockCanceler(s.T())
	s.db = deployer.NewMockWorkflowBuildsRepository(s.T())
	s.ghClient = github.NewMockClient(s.T())
	s.ghTwirpClient = ghtwirp.NewMockClient(s.T())

	s.ghTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(
		func(ctx context.Context, globalID string) types.GlobalID {
			if globalID == "" {
				return types.NilGlobalID
			}
			s.Assert().True(types.IsNextGlobalID(globalID), "%s is not a global next ID", globalID)
			return types.GlobalID(globalID)
		}, nil).Maybe()

	s.reporter = adminevents.NewMockReporter(s.T())

	s.svc = &service{
		cfg: config{
			Log:                 log,
			Obs:                 observability.NewTestObservability(),
			Stats:               nullStatter,
			Events:              emitter,
			ClientFactory:       github.NewMockFactory(s.T()),
			WorkflowCanceler:    s.canceler,
			WorkflowBuilds:      s.db,
			WorkflowFilePath:    utils.DefaultWorkflowFilePath,
			GithubTwirpClient:   s.ghTwirpClient,
			AdminEventsReporter: s.reporter,
		},
	}
	migrator := deployer.NewGlobalIDMigrator(s.ghTwirpClient)
	s.svc.gidMigrator = migrator
}

func (s *WorkflowCancelAllSuite) Test_MissingArgs() {
	ctx := context.Background()
	_, err := s.svc.WorkflowCancelAll(ctx, &pb.WorkflowCancelAllRequest{})
	s.Error(err)
}

func (s *WorkflowCancelAllSuite) Test_GhClientError() {
	ctx := context.Background()
	_, err := s.svc.WorkflowCancelAll(ctx, &pb.WorkflowCancelAllRequest{Name: testRepoName, Owner: testRepoOwner})
	s.Error(err)
}

func (s *WorkflowCancelAllSuite) Test_SuccessForNonOwnerRepos() {
	ctx := context.Background()
	s.ghTwirpClient.ExpectedCalls = nil
	s.ghTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		s.Assert().True(types.IsNextGlobalID(globalID))
		return types.GlobalID(globalID)
	}, nil)
	excludeRepoIDs := []types.GlobalID{"R_kQo=", "R_kQs="}
	repos := []*v1.Repository{
		{
			Name:          "test-1",
			GlobalRelayId: "R_kQo=",
			Id:            10,
		},
		{
			Name:          "test-2",
			GlobalRelayId: "R_kQs=",
			Id:            11,
		},
	}

	actorID := int64(12)
	actorGlobalID := &pbtypes.Identity{GlobalId: "U_kQw="}
	canceledWorkflows := int64(5)
	s.ghTwirpClient.On("GetRepositories", mock.Anything, actorID).Return(repos, nil)
	s.canceler.On("CancelAllWorkflowsForActorIDExludeRepoIDs", mock.Anything,
		types.IdentityToGlobalID(ctx, actorGlobalID), excludeRepoIDs).
		Return(canceledWorkflows, nil)

	res, err := s.svc.WorkflowCancelAllForNonOwnerRepos(ctx,
		&pb.WorkflowCancelAllForNonOwnerReposRequest{ActorId: actorID, ActorName: "", ActorGlobalId: actorGlobalID})

	s.NoError(err)
	s.Equal(int64(5), res.WorkflowCount)
}

func (s *WorkflowCancelAllSuite) Test_FailureForNonOwnerRepos_UserNotFound() {
	ctx := context.Background()
	actorID := int64(12)
	actorGlobalID := &pbtypes.Identity{GlobalId: "U_kQw="}
	s.ghTwirpClient.On("GetRepositories", mock.Anything, actorID).Return(nil, twirp.NotFoundError("user not found"))

	res, err := s.svc.WorkflowCancelAllForNonOwnerRepos(ctx,
		&pb.WorkflowCancelAllForNonOwnerReposRequest{ActorId: actorID, ActorName: "", ActorGlobalId: actorGlobalID})

	s.Nil(res)
	s.Equal(err, svcerr.NewNotFoundError("error loading repositories for actor, twirp error not_found: user not found"))
}

func (s *WorkflowCancelAllSuite) Test_SuccessByNWO_AdminEvent_RepositoryDeleted() {
	ctx := context.Background()

	// "RepositoryDeleted" admin event won't contain repo owner
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, testRepoID, adminevents.RepositoryDeleted,
		map[string]string{"repo_global_id": testRepoID.String()}).
		Return(nil).Once()

	res, err := s.svc.WorkflowCancelAll(ctx,
		&pb.WorkflowCancelAllRequest{
			RepositoryId: &pbtypes.Identity{GlobalId: testRepoID.String()},
			Name:         testRepoName,
			Owner:        testRepoOwner,
			EventType:    adminevents.RepositoryDeleted})

	s.NoError(err)
	s.Empty(res)
}

func (s *WorkflowCancelAllSuite) Test_SuccessByNWO_AdminEvent_RepositoryTransferred() {
	ctx := context.Background()

	// "RepositoryTransferred" admin event will contain repo owner
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, testRepoID, adminevents.RepositoryTransferred,
		map[string]string{"repo_global_id": testRepoID.String(), "repo_owner_global_id": testRepoOwnerID.String()}).
		Return(nil).Once()

	s.ghTwirpClient.On("GetRepositoryOwners", mock.Anything, testDatabaseID).Return(
		&ghtwirp.RepositoryOwners{
			Repository: ghtwirp.Entity{GlobalID: testRepoID, Name: testRepoName},
			Owner:      ghtwirp.Entity{GlobalID: testRepoOwnerID},
			Business:   &ghtwirp.Entity{GlobalID: testRepoPlanOwnerID},
		}, nil).Once()

	res, err := s.svc.WorkflowCancelAll(ctx,
		&pb.WorkflowCancelAllRequest{
			RepositoryId: &pbtypes.Identity{GlobalId: testRepoID.String()},
			Name:         testRepoName,
			Owner:        testRepoOwner,
			EventType:    adminevents.RepositoryTransferred})

	s.NoError(err)
	s.Empty(res)
}

func (s *WorkflowCancelAllSuite) Test_SuccessByAdminEvent_RepositoryDeleted() {
	ctx := context.Background()

	// "RepositoryDeleted" admin event won't contain repo owner
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, testRepoID, adminevents.RepositoryDeleted,
		map[string]string{"repo_global_id": testRepoID.String()}).
		Return(nil).Once()

	res, err := s.svc.WorkflowCancelAll(ctx, &pb.WorkflowCancelAllRequest{
		Name: testRepoName, Owner: testRepoOwner, EventType: adminevents.RepositoryDeleted,
		RepositoryId: &pbtypes.Identity{GlobalId: testRepoID.String()},
	})

	s.NoError(err)
	s.Empty(res)
	s.ghClient.AssertNotCalled(s.T(), "RepositoryInfoFromID")
}

func (s *WorkflowCancelAllSuite) Test_SuccessByAdminEvent_RepositoryTransferred() {
	testCases := []struct {
		name             string
		RepoOwner        string
		RepoName         string
		RepoGID          types.GlobalID
		RepoOwnerGID     types.GlobalID
		RepoPlanOwnerGID types.GlobalID
		RepoDatabseID    uint64
		AppEnv           launchconfig.AppEnv
	}{
		{
			name:             "RepositoryTransferred",
			RepoOwner:        testRepoOwner,
			RepoName:         testRepoName,
			RepoGID:          types.GlobalID("R_kgDNA3g"),
			RepoOwnerGID:     types.GlobalID("U_kgDOAP3FAg"),
			RepoPlanOwnerGID: types.GlobalID("U_kgDOAP3FAg"),
			RepoDatabseID:    uint64(888),
			AppEnv:           launchconfig.ProductionAppEnv,
		},
	}

	for _, tc := range testCases {
		s.Run(tc.name, func() {
			ctx := context.Background()
			s.svc.cfg.AppEnv = tc.AppEnv

			// "RepositoryTransferred" admin event will contain repo owner
			s.reporter.EXPECT().ReportRepoAdminEvent(mock.Anything, tc.RepoGID, adminevents.RepositoryTransferred,
				map[string]string{
					"repo_global_id":       tc.RepoGID.String(),
					"repo_owner_global_id": tc.RepoOwnerGID.String(),
				}).Return(nil)

			s.ghTwirpClient.EXPECT().GetRepositoryOwners(mock.Anything, int64(tc.RepoDatabseID)).Return(
				&ghtwirp.RepositoryOwners{
					Repository: ghtwirp.Entity{GlobalID: tc.RepoGID, Name: tc.RepoName},
					Owner:      ghtwirp.Entity{GlobalID: tc.RepoOwnerGID},
					Business:   &ghtwirp.Entity{GlobalID: tc.RepoOwnerGID},
				}, nil)

			res, err := s.svc.WorkflowCancelAll(ctx, &pb.WorkflowCancelAllRequest{
				Name: tc.RepoOwner, Owner: tc.RepoName, EventType: adminevents.RepositoryTransferred,
				RepositoryId: &pbtypes.Identity{GlobalId: tc.RepoGID.String()},
			})

			s.NoError(err)
			s.Empty(res)
		})
	}
}

func (s *WorkflowCancelAllSuite) Test_FailureByAdminEvent() {
	ctx := context.Background()

	s.reporter.On("ReportRepoAdminEvent", mock.Anything, testRepoID, adminevents.RepositoryDeleted,
		map[string]string{"repo_global_id": testRepoID.String()}).
		Return(errors.New("test error")).Once()

	res, err := s.svc.WorkflowCancelAll(ctx, &pb.WorkflowCancelAllRequest{
		RepositoryId: &pbtypes.Identity{GlobalId: testRepoID.String()},
		Name:         testRepoName,
		Owner:        testRepoOwner,
		EventType:    adminevents.RepositoryDeleted})

	s.Equal(err, svcerr.NewInternalError("attempting to cancel all workflows for repository, test error"))
	s.Nil(res)
}
