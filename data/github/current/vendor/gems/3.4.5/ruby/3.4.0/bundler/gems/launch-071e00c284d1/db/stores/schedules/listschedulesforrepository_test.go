package schedules

import (
	"context"
	"database/sql"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/statter"
	launchconfig "github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
)

type listSchedulesForRepositoryTest struct {
	suite.Suite
	conn  *sql.DB
	store Store
}

var oneHourFromNow = time.Now().Add(1 * time.Hour).UTC()

func (s *listSchedulesForRepositoryTest) SetupSuite() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)

	mockTwirpClient := &ghtwirp.MockClient{}
	mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		if strings.HasPrefix(globalID, nextIDPrefix) {
			// already a next id, return original argument
			return types.GlobalID(globalID)
		}
		return nextIDFromGlobalID(types.GlobalID(globalID))
	}, nil)
	globalIDMigrator := deployer.NewGlobalIDMigrator(mockTwirpClient)
	s.conn = conn
	s.store = makeStore(conn, defaultStoreSetup, globalIDMigrator, mockTwirpClient.IsFeatureEnabledForActor)
	s.Require().NoError(s.store.StartTests())
}

func (s *listSchedulesForRepositoryTest) SetupTest() {
	s.Require().NoError(s.store.EmptyForTests())
	s.Require().NoError(s.store.StartTests())
}

func (s *listSchedulesForRepositoryTest) TearDownSuite() {
	s.Require().NoError(s.store.EndTests())
	err := s.conn.Close()
	s.Require().NoError(err)
}

func (s *listSchedulesForRepositoryTest) TestListOnlyForEnv() {
	repo := nextIDFromGlobalID("repo-one")

	rows := []scheduleFixtureRow{
		{
			ScheduleHash: "repo-one-0-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repo,
			RepoNextGID:  repo,
			NextRunAt:    oneHourFromNow,
		},
		{
			ScheduleHash: "repo-one-1-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repo,
			RepoNextGID:  repo,
			NextRunAt:    oneHourFromNow,
		},
		{
			ScheduleHash: "repo-one-2-hash",
			Environment:  launchconfig.LabAppEnv,
			RepoGID:      repo,
			RepoNextGID:  repo,
			NextRunAt:    oneHourFromNow,
		},
	}

	for _, row := range rows {
		s.Require().NoError(insertScheduleRow(s.conn, row))
	}

	schedules, err := s.store.ListSchedulesForRepository(context.Background(), launchconfig.ProductionAppEnv, repo)
	s.Require().NoError(err)
	s.Assert().EqualValues(2, len(schedules))

	for _, sch := range schedules {
		s.Assert().NotEmpty(sch.ScheduleHash)
		s.Assert().Equal(launchconfig.ProductionAppEnv.String(), sch.Environment)
		s.Assert().Equal(repo, sch.RepositoryNodeID)
		s.Assert().Equal(repo, sch.RepositoryNextID)
		s.Assert().WithinDuration(oneHourFromNow, sch.NextRunAt, time.Millisecond)
	}
}

func (s *listSchedulesForRepositoryTest) TestListsOnlyForRepo() {
	repoOne := nextIDFromGlobalID("repo-one")
	repoTwo := nextIDFromGlobalID("repo-two")

	rows := []scheduleFixtureRow{
		{
			ScheduleHash: "repo-one-0-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoOne,
			RepoNextGID:  repoOne,
			NextRunAt:    oneHourFromNow,
		},
		{
			ScheduleHash: "repo-one-1-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoOne,
			RepoNextGID:  repoOne,
			NextRunAt:    oneHourFromNow,
		},
		{
			ScheduleHash: "repo-two-0-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoTwo,
			RepoNextGID:  repoTwo,
			NextRunAt:    oneHourFromNow,
		},
	}

	for _, row := range rows {
		s.Require().NoError(insertScheduleRow(s.conn, row))
	}

	schedules, err := s.store.ListSchedulesForRepository(context.Background(), launchconfig.ProductionAppEnv, repoOne)
	s.Require().NoError(err)
	s.Assert().EqualValues(2, len(schedules))

	for _, sch := range schedules {
		s.Assert().NotEmpty(sch.ScheduleHash)
		s.Assert().Equal(launchconfig.ProductionAppEnv.String(), sch.Environment)
		s.Assert().Equal(repoOne, sch.RepositoryNodeID)
		s.Assert().Equal(repoOne, sch.RepositoryNextID)
		s.Assert().WithinDuration(oneHourFromNow, sch.NextRunAt, time.Millisecond)
	}
}

func (s *listSchedulesForRepositoryTest) TestListsOnlyForRepo_NextColumn() {
	repoThree := nextIDFromGlobalID("repo-three")
	repoFour := nextIDFromGlobalID("repo-four")

	rows := []scheduleFixtureRow{
		{
			ScheduleHash: "repo-three-0-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoThree,
			RepoNextGID:  repoThree,
			NextRunAt:    oneHourFromNow,
		},
		{
			ScheduleHash: "repo-three-1-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoThree,
			RepoNextGID:  repoThree,
			NextRunAt:    oneHourFromNow,
		},
		{
			ScheduleHash: "repo-four-0-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoFour,
			RepoNextGID:  repoFour,
			NextRunAt:    oneHourFromNow,
		},
	}

	for _, row := range rows {
		s.Require().NoError(insertScheduleRow(s.conn, row))
	}

	schedules, err := s.store.ListSchedulesForRepository(context.Background(), launchconfig.ProductionAppEnv, repoThree)
	s.Require().NoError(err)
	s.Assert().EqualValues(2, len(schedules))

	for _, sch := range schedules {
		s.Assert().NotEmpty(sch.ScheduleHash)
		s.Assert().Equal(launchconfig.ProductionAppEnv.String(), sch.Environment)
		s.Assert().Equal(repoThree, sch.RepositoryNodeID)
		s.Assert().Equal(repoThree, sch.RepositoryNextID)
		s.Assert().WithinDuration(oneHourFromNow, sch.NextRunAt, time.Millisecond)
	}
}

func TestSchedulerRepo_ListSchedulesForRepository(t *testing.T) {
	suite.Run(t, new(listSchedulesForRepositoryTest))
}
