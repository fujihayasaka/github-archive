package deploy

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/observability"
	ghactions "github.com/github/launch/proto/monolith/core/v1"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/services/deploy/adminevents"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
)

const (
	repoGlobalID = "global-repo-1"
	repoName     = "test-repo"
	ownerName    = "test-owner"
	reason       = "test-spammy"
)

func TestDeployer_ReportAdminEventsForOwnerRepos(t *testing.T) {
	suite.Run(t, new(ReportAdminEventsForOwnerReposSuite))
}

type ReportAdminEventsForOwnerReposSuite struct {
	suite.Suite
	svc           *service
	db            *deployer.MockWorkflowBuildsRepository
	reporter      *adminevents.MockReporter
	ghClient      *github.MockClient
	ghtwirpClient *ghtwirp.MockClient
}

func (s *ReportAdminEventsForOwnerReposSuite) SetupTest() {
	log := logger.TestLogger()
	s.ghtwirpClient = &ghtwirp.MockClient{}
	s.reporter = &adminevents.MockReporter{}

	s.svc = &service{
		cfg: config{
			Log:                 log,
			Obs:                 observability.NewNullObservability(),
			AdminEventsReporter: s.reporter,
			GithubTwirpClient:   s.ghtwirpClient,
		},
		gidMigrator: deployer.NewGlobalIDMigrator(s.ghtwirpClient),
	}
}

func (s *ReportAdminEventsForOwnerReposSuite) Test_ReportRepoAdminEvents_Success() {
	ctx := context.Background()

	repos := []*ghactions.Repository{
		{
			Name:          repoName,
			GlobalRelayId: repoGlobalID,
			Id:            10,
		},
	}

	s.ghtwirpClient.On("GetRepositories", mock.Anything, int64(1234)).
		Return(repos, nil)

	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.NewGlobalID(ctx, repoGlobalID),
		adminevents.OwnerMarkedAsSpammy, map[string]string{"owner": ownerName, "repo": repoName, "reason": reason}).
		Return(nil)

	_, err := s.svc.ReportAdminEventForOwnerRepos(ctx, &pb.ReportAdminEventForOwnerReposRequest{
		OwnerName:     ownerName,
		OwnerId:       1234,
		OwnerGlobalId: repoGlobalID,
		AdminEvent:    adminevents.OwnerMarkedAsSpammy,
		Data:          reason,
	})

	s.NoError(err)
	s.ghtwirpClient.AssertExpectations(s.T())
	s.reporter.AssertExpectations(s.T())
}

func (s *ReportAdminEventsForOwnerReposSuite) Test_ReportRepoAdminEvents_ErrorGetRepos() {
	ctx := context.Background()

	s.ghtwirpClient.On("GetRepositories", mock.Anything, int64(1234)).
		Return(nil, errors.New("can't get repo"))

	_, err := s.svc.ReportAdminEventForOwnerRepos(ctx, &pb.ReportAdminEventForOwnerReposRequest{
		OwnerName:     ownerName,
		OwnerId:       1234,
		OwnerGlobalId: "global-1234",
		AdminEvent:    adminevents.OwnerMarkedAsSpammy,
		Data:          reason,
	})

	s.Error(err)
	s.ghtwirpClient.AssertExpectations(s.T())
	s.reporter.AssertExpectations(s.T())

}

func (s *ReportAdminEventsForOwnerReposSuite) Test_ReportRepoAdminEvents_Success_TwoRepos() {
	ctx := context.Background()

	repos := []*ghactions.Repository{
		{
			Name:          repoName,
			GlobalRelayId: repoGlobalID,
			Id:            10,
		},
		{
			Name:          "test-2",
			GlobalRelayId: "global-repo-2",
			Id:            11,
		},
	}

	s.ghtwirpClient.On("GetRepositories", mock.Anything, int64(1234)).Return(repos, nil)

	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID(repoGlobalID),
		adminevents.OwnerMarkedAsSpammy, map[string]string{"owner": ownerName, "repo": repoName, "reason": reason}).
		Return(nil)

	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID("global-repo-2"),
		adminevents.OwnerMarkedAsSpammy, map[string]string{"owner": ownerName, "repo": "test-2", "reason": reason}).
		Return(nil)

	_, err := s.svc.ReportAdminEventForOwnerRepos(ctx, &pb.ReportAdminEventForOwnerReposRequest{
		OwnerName:     ownerName,
		OwnerId:       1234,
		OwnerGlobalId: "global-1234",
		AdminEvent:    adminevents.OwnerMarkedAsSpammy,
		Data:          reason,
	})

	s.NoError(err)
	s.ghtwirpClient.AssertExpectations(s.T())
	s.reporter.AssertExpectations(s.T())
}

func (s *ReportAdminEventsForOwnerReposSuite) Test_ReportRepoAdminEvents_OneSuccess_OneFailed_TwoRepos() {
	ctx := context.Background()

	repos := []*ghactions.Repository{
		{
			Name:          repoName,
			GlobalRelayId: repoGlobalID,
			Id:            10,
		},
		{
			Name:          "test-2",
			GlobalRelayId: "global-repo-2",
			Id:            11,
		},
	}

	s.ghtwirpClient.On("GetRepositories", mock.Anything, int64(1234)).Return(repos, nil)
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID(repoGlobalID),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   repoName,
			"reason": reason,
		}).Return(nil)
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID("global-repo-2"),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   "test-2",
			"reason": reason,
		}).Return(errors.New("fail to report admin event"))
	_, err := s.svc.ReportAdminEventForOwnerRepos(ctx, &pb.ReportAdminEventForOwnerReposRequest{
		OwnerName:     ownerName,
		OwnerId:       1234,
		OwnerGlobalId: "global-1234",
		AdminEvent:    adminevents.OwnerMarkedAsSpammy,
		Data:          reason,
	})

	s.Error(err)
	s.ghtwirpClient.AssertExpectations(s.T())
	s.reporter.AssertExpectations(s.T())
}

func (s *ReportAdminEventsForOwnerReposSuite) Test_ReportRepoAdminEvents_Repos() {
	ctx := context.Background()

	repos := []*ghactions.Repository{
		{
			Name:          repoName,
			GlobalRelayId: repoGlobalID,
			Id:            11,
		},
		{
			Name:          "test-2",
			GlobalRelayId: "global-repo-2",
			Id:            12,
		},
		{
			Name:          "test-3",
			GlobalRelayId: "global-repo-3",
			Id:            13,
		},
		{
			Name:          "test-4",
			GlobalRelayId: "global-repo-4",
			Id:            14,
		},
		{
			Name:          "test-5",
			GlobalRelayId: "global-repo-5",
			Id:            15,
		},
		{
			Name:          "test-6",
			GlobalRelayId: "global-repo-6",
			Id:            16,
		},
		{
			Name:          "test-7",
			GlobalRelayId: "global-repo-7",
			Id:            17,
		},
		{
			Name:          "test-8",
			GlobalRelayId: "global-repo-8",
			Id:            18,
		},
		{
			Name:          "test-9",
			GlobalRelayId: "global-repo-9",
			Id:            19,
		},
		{
			Name:          "test-10",
			GlobalRelayId: "global-repo-10",
			Id:            20,
		},
	}

	s.ghtwirpClient.On("GetRepositories", mock.Anything, int64(1234)).Return(repos, nil)
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID(repoGlobalID),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   repoName,
			"reason": reason,
		}).Return(nil)
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID("global-repo-2"),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   "test-2",
			"reason": reason,
		}).Return(nil)
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID("global-repo-3"),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   "test-3",
			"reason": reason,
		}).Return(nil)
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID("global-repo-4"),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   "test-4",
			"reason": reason,
		}).Return(nil)
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID("global-repo-5"),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   "test-5",
			"reason": reason,
		}).Return(nil)
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID("global-repo-6"),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   "test-6",
			"reason": reason,
		}).Return(errors.New("fail to report admin event"))
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID("global-repo-7"),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   "test-7",
			"reason": reason,
		}).Return(errors.New("fail to report admin event"))
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID("global-repo-8"),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   "test-8",
			"reason": reason,
		}).Return(errors.New("fail to report admin event"))
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID("global-repo-9"),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   "test-9",
			"reason": reason,
		}).Return(errors.New("fail to report admin event"))
	s.reporter.On("ReportRepoAdminEvent", mock.Anything, types.GlobalID("global-repo-10"),
		adminevents.OwnerMarkedAsSpammy, map[string]string{
			"owner":  ownerName,
			"repo":   "test-10",
			"reason": reason,
		}).Return(errors.New("fail to report admin event"))
	_, err := s.svc.ReportAdminEventForOwnerRepos(ctx, &pb.ReportAdminEventForOwnerReposRequest{
		OwnerName:     ownerName,
		OwnerId:       1234,
		OwnerGlobalId: "global-1234",
		AdminEvent:    adminevents.OwnerMarkedAsSpammy,
		Data:          reason,
	})

	s.Error(err)
	s.ghtwirpClient.AssertExpectations(s.T())
	s.reporter.AssertExpectations(s.T())
}

func (s *ReportAdminEventsForOwnerReposSuite) Test_ReportBillingOwnerAdminEvents_Success() {
	ctx := context.Background()

	s.reporter.On("ReportBillingOwnerAdminEvent", mock.Anything, types.GlobalID("global-1234"), ownerName,
		adminevents.BillingOwnerDeleted, "").Return(nil)

	_, err := s.svc.ReportAdminEventForBillingOwner(ctx, &pb.ReportAdminEventForBillingOwnerRequest{
		OwnerName:     ownerName,
		OwnerId:       1234,
		OwnerGlobalId: "global-1234",
		AdminEvent:    adminevents.BillingOwnerDeleted,
		Data:          "",
	})

	s.NoError(err)
	s.ghtwirpClient.AssertExpectations(s.T())
	s.reporter.AssertExpectations(s.T())
}

func (s *ReportAdminEventsForOwnerReposSuite) Test_ReportBillingOwnerAdminEvents_Failed() {
	ctx := context.Background()

	s.reporter.On("ReportBillingOwnerAdminEvent", mock.Anything, types.GlobalID("global-1234"), ownerName,
		adminevents.BillingOwnerDeleted, "").Return(errors.New("fail to report admin event"))

	_, err := s.svc.ReportAdminEventForBillingOwner(ctx, &pb.ReportAdminEventForBillingOwnerRequest{
		OwnerName:     ownerName,
		OwnerId:       1234,
		OwnerGlobalId: "global-1234",
		AdminEvent:    adminevents.BillingOwnerDeleted,
		Data:          "",
	})

	s.Error(err)
	s.ghtwirpClient.AssertExpectations(s.T())
	s.reporter.AssertExpectations(s.T())
}
