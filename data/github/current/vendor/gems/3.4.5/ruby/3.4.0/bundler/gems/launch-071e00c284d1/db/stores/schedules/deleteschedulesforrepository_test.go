package schedules

import (
	"context"
	"database/sql"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/statter"
	launchconfig "github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
)

type deleteSchedulesForRepositoryTest struct {
	suite.Suite
	conn  *sql.DB
	store Store
}

func (s *deleteSchedulesForRepositoryTest) SetupSuite() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)

	mockTwirpClient := &ghtwirp.MockClient{}
	globalIDMigrator := deployer.NewGlobalIDMigrator(mockTwirpClient)
	mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		if strings.HasPrefix(globalID, nextIDPrefix) {
			// already a next id, return original argument
			return types.GlobalID(globalID)
		}
		return nextIDFromGlobalID(types.GlobalID(globalID))
	}, nil)
	s.conn = conn
	s.store = makeStore(conn, defaultStoreSetup, globalIDMigrator, mockTwirpClient.IsFeatureEnabledForActor)
	s.Require().NoError(s.store.StartTests())
	s.Require().NoError(s.store.EmptyForTests())
}

func (s *deleteSchedulesForRepositoryTest) TearDownSuite() {
	s.Require().NoError(s.store.EndTests())
	err := s.conn.Close()
	s.Require().NoError(err)
}

func (s *deleteSchedulesForRepositoryTest) TestDeletesOnlyForEnv() {
	repo := nextIDFromGlobalID("repo-one")

	rows := []scheduleFixtureRow{
		{
			ScheduleHash: "repo-one-0-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repo,
			RepoNextGID:  repo,
			NextRunAt:    dayAgo,
		},
		{
			ScheduleHash: "repo-one-1-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repo,
			RepoNextGID:  repo,
			NextRunAt:    dayAgo,
		},
		{
			ScheduleHash: "repo-one-2-hash",
			Environment:  launchconfig.LabAppEnv,
			RepoGID:      repo,
			RepoNextGID:  repo,
			NextRunAt:    dayAgo,
		},
	}

	for _, row := range rows {
		s.Require().NoError(insertScheduleRow(s.conn, row))
	}

	count, err := s.store.DeleteSchedulesForRepository(context.Background(), launchconfig.ProductionAppEnv, repo)
	s.Require().NoError(err)
	s.Assert().EqualValues(2, count)

	hashes, err := readWorkflowScheduleHashes(s.conn, repo)
	s.Require().NoError(err)
	s.Assert().Equal([]string{"repo-one-2-hash"}, hashes)
}

func (s *deleteSchedulesForRepositoryTest) TestDeletesOnlyForRepo() {
	repoOne := nextIDFromGlobalID("repo-one")
	repoTwo := nextIDFromGlobalID("repo-two")

	rows := []scheduleFixtureRow{
		{
			ScheduleHash: "repo-one-0-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoOne,
			RepoNextGID:  repoOne,
			NextRunAt:    dayAgo,
		},
		{
			ScheduleHash: "repo-one-1-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoOne,
			RepoNextGID:  repoOne,
			NextRunAt:    dayAgo,
		},
		{
			ScheduleHash: "repo-two-0-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoTwo,
			RepoNextGID:  repoTwo,
			NextRunAt:    dayAgo,
		},
	}

	for _, row := range rows {
		s.Require().NoError(insertScheduleRow(s.conn, row))
	}

	count, err := s.store.DeleteSchedulesForRepository(context.Background(), launchconfig.ProductionAppEnv, repoOne)
	s.Require().NoError(err)
	s.Assert().EqualValues(2, count)

	hashes, err := readWorkflowScheduleHashes(s.conn, repoTwo)
	s.Require().NoError(err)
	s.Assert().Equal([]string{"repo-two-0-hash"}, hashes)
}

func (s *deleteSchedulesForRepositoryTest) TestDeletesOnlyForRepo_NextColumn() {
	repoThree := nextIDFromGlobalID("repo-three")
	repoFour := nextIDFromGlobalID("repo-four")

	rows := []scheduleFixtureRow{
		{
			ScheduleHash: "repo-three-0-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoThree,
			RepoNextGID:  repoThree,
			NextRunAt:    dayAgo,
		},
		{
			ScheduleHash: "repo-three-1-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoThree,
			RepoNextGID:  repoThree,
			NextRunAt:    dayAgo,
		},
		{
			ScheduleHash: "repo-four-0-hash",
			Environment:  launchconfig.ProductionAppEnv,
			RepoGID:      repoFour,
			RepoNextGID:  repoFour,
			NextRunAt:    dayAgo,
		},
	}

	for _, row := range rows {
		s.Require().NoError(insertScheduleRow(s.conn, row))
	}

	count, err := s.store.DeleteSchedulesForRepository(context.Background(), launchconfig.ProductionAppEnv, repoThree)
	s.Require().NoError(err)
	s.Assert().EqualValues(2, count)

	hashes, err := readWorkflowScheduleHashes(s.conn, repoThree)
	s.Require().NoError(err)
	s.Assert().Equal([]string(nil), hashes)

	hashes, err = readWorkflowScheduleHashes(s.conn, repoFour)
	s.Require().NoError(err)
	s.Assert().Equal([]string{"repo-four-0-hash"}, hashes)

	hashes, err = readWorkflowScheduleHashesNextColumn(s.conn, repoFour)
	s.Require().NoError(err)
	s.Assert().Equal([]string{"repo-four-0-hash"}, hashes)
}

func TestSchedulerRepo_DeleteSchedulesForRepository(t *testing.T) {
	suite.Run(t, new(deleteSchedulesForRepositoryTest))
}

func readWorkflowScheduleHashes(db *sql.DB, repoNodeID types.GlobalID) ([]string, error) {
	rows, err := db.QueryContext(context.Background(), `SELECT schedule_hash FROM workflow_schedules WHERE repository_node_id = ?`, repoNodeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var scheduleHashes []string
	for rows.Next() {
		var scheduleHash string
		err = rows.Scan(&scheduleHash)
		if err != nil {
			return nil, err
		}
		scheduleHashes = append(scheduleHashes, scheduleHash)
	}
	if rows.Err() != nil {
		return nil, rows.Err()
	}
	return scheduleHashes, nil
}

func readWorkflowScheduleHashesNextColumn(db *sql.DB, repoNodeID types.GlobalID) ([]string, error) {
	rows, err := db.QueryContext(context.Background(), `SELECT schedule_hash FROM workflow_schedules WHERE repository_next_id = ?`, repoNodeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var scheduleHashes []string
	for rows.Next() {
		var scheduleHash string
		err = rows.Scan(&scheduleHash)
		if err != nil {
			return nil, err
		}
		scheduleHashes = append(scheduleHashes, scheduleHash)
	}
	if rows.Err() != nil {
		return nil, rows.Err()
	}
	return scheduleHashes, nil
}
