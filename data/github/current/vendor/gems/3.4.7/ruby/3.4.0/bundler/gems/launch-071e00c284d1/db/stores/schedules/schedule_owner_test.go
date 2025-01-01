package schedules

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

type scheduleOwnerSuite struct {
	suite.Suite
	conn  *sql.DB
	store Store
}

const (
	ownerIDOne = int64(49)
)

func (s *scheduleOwnerSuite) SetupSuite() {
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
}

func (s *scheduleOwnerSuite) TearDownSuite() {
	s.Require().NoError(s.store.EmptyForTests())
	s.Require().NoError(s.store.EndTests())
	err := s.conn.Close()
	s.Require().NoError(err)
}

func (s *scheduleOwnerSuite) SetupTest() {
	s.Require().NoError(s.store.EmptyForTests())

	examples := []struct {
		identifier  string
		wFilePath   string
		environment string
		repoID      types.GlobalID
		repoNextID  types.GlobalID
	}{
		{
			identifier:  "workflow_identifier_0",
			wFilePath:   prodWorkflow,
			environment: "production",
			repoID:      repoIDOne,
			repoNextID:  nextIDFromGlobalID(repoIDOne),
		},
		{
			identifier:  "workflow_identifier_1",
			wFilePath:   prodWorkflow,
			environment: "production",
			repoID:      types.GlobalID("repo_id_two"),
			repoNextID:  nextIDFromGlobalID("repo_id_two"),
		},
	}

	for _, eg := range examples {
		_, err := s.conn.Exec(fmt.Sprintf(`
			INSERT INTO workflow_schedules
			SET
				repository_node_id=?,
				repository_next_id=?,
				owner_id=?,
				schedule_hash=?,
				schedule_next_hash=?,
				workflow_identifier=?,
				schedule=?,
				workflow_file_path=?,
				environment=?,
				actor_node_id='actor',
				actor_next_id='U_actornext',
				-- real values 0..1, easier to spot in tests
				scatter_offset=-99,
				%s
				next_run_at='2000-01-01'
			`, metdataFragment),
			eg.repoID,
			eg.repoNextID,
			0,
			NewScheduleHash(
				eg.repoID,
				eg.identifier,
				eg.wFilePath,
				fixtureOriginalSchedule,
			),
			NewScheduleHash(
				eg.repoNextID,
				eg.identifier,
				eg.wFilePath,
				fixtureOriginalSchedule,
			),
			eg.identifier,
			fixtureOriginalSchedule,
			eg.wFilePath,
			eg.environment,
		)
		s.Require().NoError(err)
	}
}

func (s *scheduleOwnerSuite) Test_UpdateOwnerID() {
	ctx := context.Background()

	err := s.store.UpdateOwnerID(ctx, repoIDOne, ownerIDOne)
	s.Require().NoError(err)

	schedule, err := s.store.FindAndLock(ctx, "worker", 5)
	s.Require().NoError(err)
	s.Assert().Equal(2, len(schedule))
	s.Assert().Equal(ownerIDOne, schedule[0].OwnerID)
	s.Assert().Equal(int64(0), schedule[1].OwnerID)
}

func (s *scheduleOwnerSuite) Test_UpdateOwnerID_NextColumn() {
	ctx := context.Background()

	err := s.store.UpdateOwnerID(ctx, repoIDOne, ownerIDOne)
	s.Require().NoError(err)

	ownerIDs, err := readOwnerID(s.conn, repoIDOne)
	s.Require().NoError(err)
	s.Assert().Equal(ownerIDOne, ownerIDs[0])

	ownerIDs, err = readOwnerIDNextColumn(s.conn, nextIDFromGlobalID(repoIDOne))
	s.Require().NoError(err)
	s.Assert().Equal(ownerIDOne, ownerIDs[0])
}

func readOwnerID(db *sql.DB, repoNodeID types.GlobalID) ([]int64, error) {
	rows, err := db.QueryContext(context.Background(), `SELECT owner_id FROM workflow_schedules WHERE repository_node_id = ?`, repoNodeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ownerIDs []int64
	for rows.Next() {
		var owner int64
		err = rows.Scan(&owner)
		if err != nil {
			return nil, err
		}
		ownerIDs = append(ownerIDs, owner)
	}
	if rows.Err() != nil {
		return nil, rows.Err()
	}
	return ownerIDs, nil
}

func readOwnerIDNextColumn(db *sql.DB, repoNodeID types.GlobalID) ([]int64, error) {
	rows, err := db.QueryContext(context.Background(), `SELECT owner_id FROM workflow_schedules WHERE repository_next_id = ?`, repoNodeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ownerIDs []int64
	for rows.Next() {
		var owner int64
		err = rows.Scan(&owner)
		if err != nil {
			return nil, err
		}
		ownerIDs = append(ownerIDs, owner)
	}
	if rows.Err() != nil {
		return nil, rows.Err()
	}
	return ownerIDs, nil
}

func TestScheduleUpdateOwner(t *testing.T) {
	testutils.NoShort(t)
	suite.Run(t, new(scheduleOwnerSuite))
}
