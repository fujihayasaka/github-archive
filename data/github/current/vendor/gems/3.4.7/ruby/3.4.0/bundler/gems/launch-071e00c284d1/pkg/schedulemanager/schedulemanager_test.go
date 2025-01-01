package schedulemanager

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/facebookgo/clock"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/db/stores/schedules"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services/deploy/scheduled/config"
	"github.com/github/launch/services/deploy/scheduled/model"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/testutils"
)

const (
	validCronPipline = `on:
  push:
    branches: master
  schedule:
  - cron: "* * * 2 *"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`

	invalidCronPipeline = `on:
  $push:
    branches: master
  schedule:
  # invalid - '*' needs quoting
  - cron: * * * 1 *`

	nextIDPrefix = "next-"

	ownerID = int64(16631042)
)

func TestScheduleService(t *testing.T) {
	suite.Run(t, new(serviceSuite))
}

type serviceSuite struct {
	suite.Suite
	conn  *sql.DB
	store schedules.Store

	isUserSpammy  bool
	ghTwirpClient *ghtwirp.MockClient
}

func (s *serviceSuite) SetupSuite() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)

	s.conn = conn
	s.isUserSpammy = false
	p := model.NewScheduleParser()
	s.ghTwirpClient = &ghtwirp.MockClient{}

	globalIDMigrator := deployer.NewGlobalIDMigrator(s.ghTwirpClient)
	s.store = schedules.New(
		asql.New(conn, logger.NullLogger(), statter.NullStatter(), testutils.NewNoopBreaker(), asql.LaunchCluster),
		logger.TestLogger(),
		p,
		config.ScheduledConfig{},
		clock.New(),
		statter.NullStatter(),
		globalIDMigrator,
		s.ghTwirpClient.IsFeatureEnabledForActor,
	)

	s.Require().NoError(s.store.StartTests())
}

func (s *serviceSuite) SetupMultiTenantSuite() {

}

func (s *serviceSuite) SetupTest() {
	s.Require().NoError(s.store.EmptyForTests())
}

func (s *serviceSuite) TearDownSuite() {
	s.Require().NoError(s.store.EndTests())
	s.Require().NoError(s.conn.Close())
}

func (s *serviceSuite) TestOnPush() {
	sched := model.MockSchedule{}
	sched.EXPECT().Next(mock.AnythingOfType("time.Time")).
		Return(time.Now())

	client := &github.MockClient{}
	s.ghTwirpClient.On("IsUserSpammy", mock.Anything, mock.Anything).Return(func(ctx context.Context, id types.GlobalID) bool {
		return s.isUserSpammy
	}, nil)

	s.ghTwirpClient.EXPECT().GetTrustTier(mock.Anything, mock.Anything).Return(types.RepositoryTier2, nil)
	s.ghTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		if strings.HasPrefix(globalID, nextIDPrefix) {
			// already a next id, return original argument
			return types.GlobalID(globalID)
		}
		return nextIDFromGlobalID(types.GlobalID(globalID))
	}, nil)

	ctx := context.Background()
	repoID := nextIDFromGlobalID("foo")
	actorID := nextIDFromGlobalID("bar")

	srv := service{
		cfg: &Config{
			Environment:  launchconfig.TestAppEnv,
			IsEnterprise: false,
		},
		obs:               observability.New(logger.TestLogger(), statter.NullStatter()),
		store:             s.store,
		githubTwirpClient: s.ghTwirpClient,
		clientFactory: &github.MockClientFactory{
			ByRepositoryOwnerDatabaseID: map[int64]github.Client{
				ownerID: client,
			},
		},
		workflowSrcFactory: workflowinvoker.NullWorkflowSourceFactory{},
	}

	rs := github.RepositoryScheduleData{
		DefaultBranchFullRef: "refs/head/master",
		ActorLogin:           "mona",
		ActorGID:             actorID,
		RepositoryScheduleState: github.RepositoryScheduleState{
			CurrentHeadSHA: "aaa",
			PipelineFiles: []types.ResolvedFile{
				{
					Path: ".github/workflows/main.yml",
					Text: `on:
  push:
    branches: master
  schedule:
  - cron: "* * * 1 *"
  - cron: "* * * 2 *"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
					SHA: "aabbff",
				},
			},
		},
	}
	client.EXPECT().GetRepositoryScheduleData(mock.Anything, mock.Anything, mock.Anything,
		mock.Anything, mock.Anything).
		Return(&rs, nil)

	s.Run("should sync", func() {
		s.Require().NoError(s.store.EmptyForTests())
		s.isUserSpammy = false

		srv.SyncOnPush(ctx,
			repoID,
			"refs/head/master",
			actorID,
			ownerID,
		)

		c, err := s.store.CountForTests(repoID)
		s.Require().NoError(err)
		s.Equal(2, c)

		c, err = s.store.CountForTestsNextColumn(repoID)
		s.Require().NoError(err)
		s.Equal(2, c)
	})

	s.Run("should not sync for spammy user", func() {
		s.Require().NoError(s.store.EmptyForTests())
		s.isUserSpammy = true

		srv.SyncOnPush(ctx,
			repoID,
			"refs/head/master",
			actorID,
			ownerID,
		)

		c, err := s.store.CountForTests(repoID)
		s.Require().NoError(err)
		s.Equal(0, c)

		c, err = s.store.CountForTestsNextColumn(repoID)
		s.Require().NoError(err)
		s.Equal(0, c)
	})

	s.Run("should not sync on non-default branch", func() {
		s.Require().NoError(s.store.EmptyForTests())
		s.isUserSpammy = false

		srv.SyncOnPush(ctx,
			repoID,
			"refs/head/other",
			actorID,
			ownerID,
		)

		c, err := s.store.CountForTests(repoID)
		s.Require().NoError(err)
		s.Equal(0, c)

		c, err = s.store.CountForTestsNextColumn(repoID)
		s.Require().NoError(err)
		s.Equal(0, c)
	})

	s.Run("reusable workflows", func() {
		rs.RepositoryScheduleState.PipelineFiles = []types.ResolvedFile{
			{
				Path: ".github/workflows/main.yml",
				Text: `on:
  push:
    branches: master
  schedule:
  - cron: "* * * 1 *"
  - cron: "* * * 2 *"
jobs:
  test:
    uses: ./.github/workflows/called.yml
  thing:
    steps:
    - uses: owner/repo@master`,
				SHA: "aabbff",
			},
		}

		s.Run("should sync for non-enterprise", func() {
			s.Require().NoError(s.store.EmptyForTests())
			s.isUserSpammy = false

			srv.SyncOnPush(ctx,
				repoID,
				"refs/head/master",
				actorID,
				ownerID,
			)

			c, err := s.store.CountForTests(repoID)
			s.Require().NoError(err)
			s.Equal(2, c)

			c, err = s.store.CountForTestsNextColumn(repoID)
			s.Require().NoError(err)
			s.Equal(2, c)
		})

		s.Run("should sync for GHES", func() {
			s.Require().NoError(s.store.EmptyForTests())
			s.isUserSpammy = false
			srv.cfg.IsEnterprise = true
			rs.RepositoryScheduleState.WorkflowFeatureFlags = types.WorkflowFeatureFlags{}

			srv.SyncOnPush(ctx,
				repoID,
				"refs/head/master",
				actorID,
				ownerID,
			)

			c, err := s.store.CountForTests(repoID)
			s.Require().NoError(err)
			s.Equal(2, c)

			c, err = s.store.CountForTestsNextColumn(repoID)
			s.Require().NoError(err)
			s.Equal(2, c)
		})
	})
}

func (s *serviceSuite) TestOnPush_Lab() {
	sched := model.MockSchedule{}
	sched.EXPECT().Next(mock.AnythingOfType("time.Time")).
		Return(time.Now())

	client := &github.MockClient{}

	s.ghTwirpClient.ExpectedCalls = []*mock.Call{}
	client.ExpectedCalls = []*mock.Call{}

	s.ghTwirpClient.On("IsUserSpammy", mock.Anything, mock.Anything).Return(func(ctx context.Context, id types.GlobalID) bool {
		return s.isUserSpammy
	}, nil)

	s.ghTwirpClient.EXPECT().GetTrustTier(mock.Anything, mock.Anything).Return(types.RepositoryTier2, nil)
	s.ghTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		if strings.HasPrefix(globalID, nextIDPrefix) {
			// already a next id, return original argument
			return types.GlobalID(globalID)
		}
		return nextIDFromGlobalID(types.GlobalID(globalID))
	}, nil)

	ctx := context.Background()
	repoID := nextIDFromGlobalID("foo-global-app")
	actorID := nextIDFromGlobalID("bar-global-app")

	srv := service{
		cfg: &Config{
			Environment:  launchconfig.LabAppEnv,
			IsEnterprise: false,
		},
		obs:               observability.New(logger.TestLogger(), statter.NullStatter()),
		store:             s.store,
		githubTwirpClient: s.ghTwirpClient,
		clientFactory: &github.MockClientFactory{
			ByRepositoryOwnerDatabaseID: map[int64]github.Client{
				ownerID: client,
			},
		},
		workflowSrcFactory: workflowinvoker.NullWorkflowSourceFactory{},
	}

	rs := github.RepositoryScheduleData{
		DefaultBranchFullRef: "refs/head/master",
		ActorLogin:           "mona",
		ActorGID:             actorID,
		RepositoryScheduleState: github.RepositoryScheduleState{
			CurrentHeadSHA: "aaa",
			PipelineFiles: []types.ResolvedFile{
				{
					Path: ".github/workflows/main.yml",
					Text: `on:
  push:
    branches: master
  schedule:
  - cron: "* * * 1 *"
  - cron: "* * * 2 *"
jobs:
  thing:
    steps:
    - uses: owner/repo@master`,
					SHA: "aabbff",
				},
			},
		},
	}
	client.EXPECT().GetRepositoryScheduleData(mock.Anything, mock.Anything, mock.Anything,
		mock.Anything, mock.Anything).
		Return(&rs, nil)

	s.Run("should sync", func() {
		s.Require().NoError(s.store.EmptyForTests())
		s.isUserSpammy = false

		srv.SyncOnPush(ctx,
			repoID,
			"refs/head/master",
			actorID,
			ownerID,
		)

		c, err := s.store.CountForTests(repoID)
		s.Require().NoError(err)
		s.Equal(2, c)

		c, err = s.store.CountForTestsNextColumn(repoID)
		s.Require().NoError(err)
		s.Equal(2, c)
	})

	s.Run("should not sync for spammy user", func() {
		s.Require().NoError(s.store.EmptyForTests())
		s.isUserSpammy = true

		srv.SyncOnPush(ctx,
			repoID,
			"refs/head/master",
			actorID,
			ownerID,
		)

		c, err := s.store.CountForTests(repoID)
		s.Require().NoError(err)
		s.Equal(0, c)

		c, err = s.store.CountForTestsNextColumn(repoID)
		s.Require().NoError(err)
		s.Equal(0, c)
	})

	s.Run("should not sync on non-default branch", func() {
		s.Require().NoError(s.store.EmptyForTests())
		s.isUserSpammy = false

		srv.SyncOnPush(ctx,
			repoID,
			"refs/head/other",
			actorID,
			ownerID,
		)

		c, err := s.store.CountForTests(repoID)
		s.Require().NoError(err)
		s.Equal(0, c)

		c, err = s.store.CountForTestsNextColumn(repoID)
		s.Require().NoError(err)
		s.Equal(0, c)
	})

	s.Run("reusable workflows", func() {
		rs.RepositoryScheduleState.PipelineFiles = []types.ResolvedFile{
			{
				Path: ".github/workflows/main.yml",
				Text: `on:
  push:
    branches: master
  schedule:
  - cron: "* * * 1 *"
  - cron: "* * * 2 *"
jobs:
  test:
    uses: ./.github/workflows/called.yml
  thing:
    steps:
    - uses: owner/repo@master`,
				SHA: "aabbff",
			},
		}

		s.Run("should sync for non-enterprise", func() {
			s.Require().NoError(s.store.EmptyForTests())
			s.isUserSpammy = false

			srv.SyncOnPush(ctx,
				repoID,
				"refs/head/master",
				actorID,
				ownerID,
			)

			c, err := s.store.CountForTests(repoID)
			s.Require().NoError(err)
			s.Equal(2, c)

			c, err = s.store.CountForTestsNextColumn(repoID)
			s.Require().NoError(err)
			s.Equal(2, c)
		})

		s.Run("should sync for GHES", func() {
			s.Require().NoError(s.store.EmptyForTests())
			s.isUserSpammy = false
			srv.cfg.IsEnterprise = true
			rs.RepositoryScheduleState.WorkflowFeatureFlags = types.WorkflowFeatureFlags{}

			srv.SyncOnPush(ctx,
				repoID,
				"refs/head/master",
				actorID,
				ownerID,
			)

			c, err := s.store.CountForTests(repoID)
			s.Require().NoError(err)
			s.Equal(2, c)

			c, err = s.store.CountForTestsNextColumn(repoID)
			s.Require().NoError(err)
			s.Equal(2, c)
		})
	})
}

func (s *serviceSuite) TestOnPush_MarksInvalidFilesForScheduleDelete() {
	sched := model.MockSchedule{}
	sched.EXPECT().Next(mock.AnythingOfType("time.Time")).
		Return(time.Now())

	ctx := context.Background()
	repoID := nextIDFromGlobalID("foo")
	actorID := nextIDFromGlobalID("bar")

	client := &github.MockClient{}

	srv := service{
		cfg: &Config{
			Environment:  launchconfig.TestAppEnv,
			IsEnterprise: false,
		},
		obs:               observability.New(logger.TestLogger(), statter.NullStatter()),
		githubTwirpClient: s.ghTwirpClient,
		store:             s.store,
		clientFactory: &github.MockClientFactory{
			ByRepositoryOwnerDatabaseID: map[int64]github.Client{
				ownerID: client,
			},
		},
		workflowSrcFactory: workflowinvoker.NullWorkflowSourceFactory{},
	}

	s.ghTwirpClient.EXPECT().GetTrustTier(mock.Anything, mock.Anything).Return(types.RepositoryTier3, nil)
	s.ghTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, mock.Anything).Return(types.GlobalID("id_next"), nil)

	mainPath := ".github/workflows/main.yml"
	secondPath := ".github/workflows/second.yml"

	valid := github.RepositoryScheduleData{
		DefaultBranchFullRef: "refs/head/master",
		ActorLogin:           "mona",
		ActorGID:             actorID,
		RepositoryScheduleState: github.RepositoryScheduleState{
			CurrentHeadSHA: "aaa",
			PipelineFiles: []types.ResolvedFile{
				{
					Path: mainPath,
					Text: validCronPipline,
					SHA:  "aabbff",
				},
				{
					Path: secondPath,
					Text: validCronPipline,
					SHA:  "aabbff",
				},
			},
		},
	}

	invalid := github.RepositoryScheduleData{
		DefaultBranchFullRef: "refs/head/master",
		ActorLogin:           "mona",
		ActorGID:             actorID,
		RepositoryScheduleState: github.RepositoryScheduleState{
			CurrentHeadSHA: "aaa",
			PipelineFiles: []types.ResolvedFile{
				{
					Path: mainPath,
					Text: invalidCronPipeline,
					SHA:  "aabbff",
				},
				{
					Path: secondPath,
					Text: validCronPipline,
					SHA:  "aabbff",
				},
			},
		},
	}

	calls := 0
	client.On("GetRepositoryScheduleData", mock.Anything, mock.Anything, mock.Anything,
		mock.Anything, mock.Anything, mock.Anything).
		Return(func(ctx context.Context, repoNodeID types.GlobalID, branchRef types.GitRef, actorID types.GlobalID, env launchconfig.AppEnv) *github.RepositoryScheduleData {
			if calls == 0 {
				calls++
				return &valid
			}
			return &invalid
		}, func(ctx context.Context, repoNodeID types.GlobalID, branchRef types.GitRef, actorID types.GlobalID, env launchconfig.AppEnv) error {
			return nil
		})

	s.ghTwirpClient.EXPECT().IsUserSpammy(mock.Anything, mock.Anything).Return(false, nil)
	s.Require().NoError(s.store.EmptyForTests())

	srv.SyncOnPush(ctx,
		repoID,
		"refs/head/master",
		actorID,
		ownerID,
	)

	c, err := s.store.CountForTests(repoID)
	s.Require().NoError(err)
	s.Equal(2, c)

	c, err = s.store.CountForTestsNextColumn(repoID)
	s.Require().NoError(err)
	s.Equal(2, c)

	s.Require().NoError(s.store.EmptyForTests())

	srv.SyncOnPush(ctx,
		repoID,
		"refs/head/master",
		actorID,
		ownerID,
	)

	c, err = s.store.CountForFileForTestsNextColumn(repoID, mainPath)
	s.Require().NoError(err)
	s.Equal(0, c)
	c, err = s.store.CountForFileForTestsNextColumn(repoID, secondPath)
	s.Require().NoError(err)
	s.Equal(1, c)
}

// https://github.com/github/c2c-actions-experience/issues/6602 is tracking the removal of this function
func nextIDFromGlobalID(legacyGID types.GlobalID) types.GlobalID {
	return types.GlobalID(fmt.Sprintf("%s%s", nextIDPrefix, legacyGID))
}
