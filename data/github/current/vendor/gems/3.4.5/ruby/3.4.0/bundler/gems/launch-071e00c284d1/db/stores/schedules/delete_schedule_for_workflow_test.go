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

type deleteScheduleForWorkflowTest struct {
	suite.Suite
	conn  *sql.DB
	store Store
}

func (s *deleteScheduleForWorkflowTest) SetupSuite() {
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

func (s *deleteScheduleForWorkflowTest) TearDownSuite() {
	s.Require().NoError(s.store.EndTests())
	err := s.conn.Close()
	s.Require().NoError(err)
}

func (s *deleteScheduleForWorkflowTest) TestDeletesOnlyForWorkflowPath() {
	repo := nextIDFromGlobalID("repo")

	rows := []scheduleFixtureRow{
		{
			ScheduleHash:     "hash-repo-0",
			Environment:      launchconfig.ProductionAppEnv,
			RepoGID:          repo,
			RepoNextGID:      repo,
			WorkflowFilePath: ".github/workflows/workflow-1.yml",
			NextRunAt:        dayAgo,
		},
		{
			ScheduleHash:     "hash-repo-1",
			Environment:      launchconfig.ProductionAppEnv,
			RepoGID:          repo,
			RepoNextGID:      repo,
			WorkflowFilePath: ".github/workflows/workflow-2.yml",
			NextRunAt:        dayAgo,
		},
		{
			ScheduleHash:     "hash-repo-2",
			Environment:      launchconfig.ProductionAppEnv,
			RepoGID:          repo,
			RepoNextGID:      repo,
			WorkflowFilePath: ".github/workflows/workflow-3.yml",
			NextRunAt:        dayAgo,
		},
	}

	for _, row := range rows {
		s.Require().NoError(insertScheduleRow(s.conn, row))
	}

	count, err := s.store.DeleteScheduleForWorkflow(context.Background(), launchconfig.ProductionAppEnv, repo, ".github/workflows/workflow-1.yml")
	s.Require().NoError(err)
	s.Assert().EqualValues(1, count)

	hashes, err := readWorkflowFilePaths(s.conn, repo)
	s.Require().NoError(err)
	s.Assert().Equal([]string{".github/workflows/workflow-2.yml", ".github/workflows/workflow-3.yml"}, hashes)
}

func (s *deleteScheduleForWorkflowTest) TestDeletesOnlyForRepo() {
	repoOne := nextIDFromGlobalID("repo-one")
	repoTwo := nextIDFromGlobalID("repo-two")

	rows := []scheduleFixtureRow{
		{
			ScheduleHash:     "hash-repo-one-0",
			Environment:      launchconfig.ProductionAppEnv,
			RepoGID:          repoOne,
			RepoNextGID:      repoOne,
			WorkflowFilePath: ".github/workflows/workflow-1.yml",
			NextRunAt:        dayAgo,
		},
		{
			ScheduleHash:     "hash-repo-one-1",
			Environment:      launchconfig.ProductionAppEnv,
			RepoGID:          repoOne,
			RepoNextGID:      repoOne,
			WorkflowFilePath: ".github/workflows/workflow-2.yml",
			NextRunAt:        dayAgo,
		},
		{
			ScheduleHash:     "hash-repo-two-0",
			Environment:      launchconfig.ProductionAppEnv,
			RepoGID:          repoTwo,
			RepoNextGID:      repoTwo,
			WorkflowFilePath: ".github/workflows/workflow-1.yml",
			NextRunAt:        dayAgo,
		},
	}

	for _, row := range rows {
		s.Require().NoError(insertScheduleRow(s.conn, row))
	}

	count, err := s.store.DeleteScheduleForWorkflow(context.Background(), launchconfig.ProductionAppEnv, repoOne, ".github/workflows/workflow-1.yml")
	s.Require().NoError(err)
	s.Assert().EqualValues(1, count)

	hashes, err := readWorkflowFilePaths(s.conn, repoOne)
	s.Require().NoError(err)
	s.Assert().Equal([]string{".github/workflows/workflow-2.yml"}, hashes)

	hashes, err = readWorkflowFilePaths(s.conn, repoTwo)
	s.Require().NoError(err)
	s.Assert().Equal([]string{".github/workflows/workflow-1.yml"}, hashes)
}

func (s *deleteScheduleForWorkflowTest) TestDeletesOnlyForRepo_NextColumn() {
	repoThree := nextIDFromGlobalID("repo-three")
	repoFour := nextIDFromGlobalID("repo-four")

	rows := []scheduleFixtureRow{
		{
			ScheduleHash:     "hash-repo-three-0",
			Environment:      launchconfig.ProductionAppEnv,
			RepoGID:          repoThree,
			RepoNextGID:      repoThree,
			WorkflowFilePath: ".github/workflows/workflow-1.yml",
			NextRunAt:        dayAgo,
		},
		{
			ScheduleHash:     "hash-repo-three-1",
			Environment:      launchconfig.ProductionAppEnv,
			RepoGID:          repoThree,
			RepoNextGID:      repoThree,
			WorkflowFilePath: ".github/workflows/workflow-2.yml",
			NextRunAt:        dayAgo,
		},
		{
			ScheduleHash:     "hash-repo-four-0",
			Environment:      launchconfig.ProductionAppEnv,
			RepoGID:          repoFour,
			RepoNextGID:      repoFour,
			WorkflowFilePath: ".github/workflows/workflow-1.yml",
			NextRunAt:        dayAgo,
		},
		{
			ScheduleHash:     "hash-repo-four-1",
			Environment:      launchconfig.ProductionAppEnv,
			RepoGID:          repoFour,
			RepoNextGID:      repoFour,
			WorkflowFilePath: ".github/workflows/workflow-2.yml",
			NextRunAt:        dayAgo,
		},
	}

	for _, row := range rows {
		s.Require().NoError(insertScheduleRow(s.conn, row))
	}

	count, err := s.store.DeleteScheduleForWorkflow(context.Background(), launchconfig.ProductionAppEnv, repoThree, ".github/workflows/workflow-1.yml")
	s.Require().NoError(err)
	s.Assert().EqualValues(1, count)

	paths, err := readWorkflowFilePaths(s.conn, repoThree)
	s.Require().NoError(err)
	s.Assert().Equal([]string{".github/workflows/workflow-2.yml"}, paths)

	paths, err = readWorkflowFilePathsNextColumn(s.conn, repoThree)
	s.Require().NoError(err)
	s.Assert().Equal([]string{".github/workflows/workflow-2.yml"}, paths)

	paths, err = readWorkflowFilePaths(s.conn, repoFour)
	s.Require().NoError(err)
	s.Assert().Equal([]string{".github/workflows/workflow-1.yml", ".github/workflows/workflow-2.yml"}, paths)

	paths, err = readWorkflowFilePathsNextColumn(s.conn, repoFour)
	s.Require().NoError(err)
	s.Assert().Equal([]string{".github/workflows/workflow-1.yml", ".github/workflows/workflow-2.yml"}, paths)

	count, err = s.store.DeleteScheduleForWorkflow(context.Background(), launchconfig.ProductionAppEnv, repoFour, ".github/workflows/workflow-1.yml")
	paths, err = readWorkflowFilePaths(s.conn, repoFour)
	s.Require().NoError(err)
	s.Assert().Equal([]string{".github/workflows/workflow-2.yml"}, paths)

	paths, err = readWorkflowFilePathsNextColumn(s.conn, repoFour)
	s.Require().NoError(err)
	s.Assert().Equal([]string{".github/workflows/workflow-2.yml"}, paths)
}

func readWorkflowFilePaths(db *sql.DB, repoNodeID types.GlobalID) ([]string, error) {
	rows, err := db.QueryContext(context.Background(), `SELECT workflow_file_path FROM workflow_schedules WHERE repository_node_id = ?`, repoNodeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var workflowFilePaths []string
	for rows.Next() {
		var filePath string
		err = rows.Scan(&filePath)
		if err != nil {
			return nil, err
		}
		workflowFilePaths = append(workflowFilePaths, filePath)
	}
	if rows.Err() != nil {
		return nil, rows.Err()
	}
	return workflowFilePaths, nil
}

func readWorkflowFilePathsNextColumn(db *sql.DB, repoNodeID types.GlobalID) ([]string, error) {
	rows, err := db.QueryContext(context.Background(), `SELECT workflow_file_path FROM workflow_schedules WHERE repository_next_id = ?`, repoNodeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var workflowFilePaths []string
	for rows.Next() {
		var filePath string
		err = rows.Scan(&filePath)
		if err != nil {
			return nil, err
		}
		workflowFilePaths = append(workflowFilePaths, filePath)
	}
	if rows.Err() != nil {
		return nil, rows.Err()
	}
	return workflowFilePaths, nil
}

func TestSchedulerRepo_DeleteSchedulesForWorkflow(t *testing.T) {
	suite.Run(t, new(deleteScheduleForWorkflowTest))
}
