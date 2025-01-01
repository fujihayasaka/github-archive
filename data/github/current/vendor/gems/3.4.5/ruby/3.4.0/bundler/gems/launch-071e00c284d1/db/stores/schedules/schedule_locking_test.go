package schedules

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/pkg/errors"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	launchconfig "github.com/github/launch/pkg/launchconfig"

	"github.com/github/launch/utils/testutils"

	"github.com/github/launch/types"

	"github.com/github/launch/services/deploy/scheduled/model"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/mysqldb"
)

var dayAgo = time.Now().Add(-24 * time.Hour).UTC()

const scheduleTestsRepoGID = "repo_id_ten"

const tasksPerTick = 5

type scheduleLockingSuite struct {
	suite.Suite
	conn            *sql.DB
	store           Store
	defaultStore    Store
	parser          model.ScheduleParser
	mockTwirpClient *ghtwirp.MockClient
}

func (s *scheduleLockingSuite) SetupSuite() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)
	mockTwirpClient := ghtwirp.NewMockClient(s.T())

	globalIDMigrator := deployer.NewGlobalIDMigrator(mockTwirpClient)

	s.conn = conn
	s.store = makeStore(conn, defaultStoreSetup, globalIDMigrator, mockTwirpClient.IsFeatureEnabledForActor)
	s.Require().NoError(s.store.StartTests())
	s.defaultStore = s.store

	s.parser = model.NewScheduleParser()
	s.mockTwirpClient = mockTwirpClient
}

func (s *scheduleLockingSuite) TearDownSuite() {
	s.Require().NoError(s.store.EndTests())
	err := s.conn.Close()
	s.Require().NoError(err)
}

var originalLockedByID = "originalLockedBy"
var unlockedLockedByValue = ""

const hourlyScheduleString = "0 * * * *"
const minuteScheduleString = "* * * * *"

type scheduleFixtureRow struct {
	ScheduleHash     string
	LockedAt         *time.Time
	LockedBy         *string
	NextRunAt        time.Time
	Schedule         string
	WorkflowFilePath string
	Environment      launchconfig.AppEnv
	RepoGID          types.GlobalID
	RepoNextGID      types.GlobalID
	Tier             int
	TierUpdatedAt    *time.Time
}

func (s *scheduleLockingSuite) SetupTest() {

	s.Require().NoError(s.store.EmptyForTests())

	now := time.Now()

	examples := []scheduleFixtureRow{
		{
			ScheduleHash:  "locked",
			Schedule:      "* * * * *",
			LockedAt:      &now,
			LockedBy:      &originalLockedByID,
			NextRunAt:     dayAgo,
			Environment:   launchconfig.ProductionAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          3,
			TierUpdatedAt: &dayAgo,
		},
		{
			ScheduleHash:  "unlocked",
			Schedule:      hourlyScheduleString,
			LockedAt:      nil,
			LockedBy:      nil,
			NextRunAt:     dayAgo,
			Environment:   launchconfig.ProductionAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          3,
			TierUpdatedAt: nil,
		},
		{
			ScheduleHash: "unlockedEveryMinute",
			// hourly
			Schedule:      minuteScheduleString,
			LockedAt:      nil,
			LockedBy:      nil,
			NextRunAt:     dayAgo,
			Environment:   launchconfig.ProductionAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          3,
			TierUpdatedAt: &dayAgo,
		},
		{
			ScheduleHash:  "lockedLab",
			Schedule:      "* * * * *",
			LockedAt:      &now,
			LockedBy:      &originalLockedByID,
			NextRunAt:     dayAgo,
			Environment:   launchconfig.LabAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          3,
			TierUpdatedAt: &dayAgo,
		},
		{
			ScheduleHash:  "unlockedLab",
			Schedule:      "* * * * *",
			LockedAt:      nil,
			LockedBy:      nil,
			NextRunAt:     dayAgo,
			Environment:   launchconfig.LabAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          3,
			TierUpdatedAt: nil,
		},
		{
			ScheduleHash:  "tier1Unlocked",
			Schedule:      hourlyScheduleString,
			LockedAt:      nil,
			LockedBy:      nil,
			NextRunAt:     dayAgo,
			Environment:   launchconfig.ProductionAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          1,
			TierUpdatedAt: nil,
		},
	}

	for _, eg := range examples {
		err := insertScheduleRow(s.conn, eg)
		s.Require().NoError(err)
	}

	// Reset changes to mocks and store
	s.store = s.defaultStore
	s.mockTwirpClient.ExpectedCalls = nil
}

func insertScheduleRow(db *sql.DB, eg scheduleFixtureRow) error {
	return insertScheduleRows(db, []scheduleFixtureRow{eg})
}

func insertScheduleRows(db *sql.DB, sfrs []scheduleFixtureRow) error {
	const paramsPerRow = 18
	params := make([]any, 0, len(sfrs)*paramsPerRow)
	insertRows := make([]string, 0, len(sfrs))

	for _, row := range sfrs {
		workflowFilePath := ".github/workflows/schedule.yml"
		if row.WorkflowFilePath != "" {
			workflowFilePath = row.WorkflowFilePath
		}

		params = append(params, []any{
			row.ScheduleHash,  // schedule_hash
			row.ScheduleHash,  // schedule_next_hash
			row.LockedAt,      // locked_at
			row.LockedBy,      // locked_by
			row.Schedule,      // schedule
			row.NextRunAt,     // next_run_at
			workflowFilePath,  // workflow_file_path
			row.Environment,   // environment
			"U_actornext",     // actor_node_id
			"U_actornext",     // actor_next_id
			row.RepoNextGID,   // repository_node_id
			row.RepoNextGID,   // repository_next_id
			"thing",           // workflow_identifier
			row.Tier,          // tier
			row.TierUpdatedAt, // tier_updated_at
			"aaa",             // commit_sha
			"actor_login",     // actor_login
			0.5,               // scatter_offset
		}...)
		insertRows = append(insertRows, fmt.Sprintf("(%s)", mysqldb.Placeholders(paramsPerRow)))
	}

	insertSQL := fmt.Sprintf(`
		INSERT INTO workflow_schedules
		(
			schedule_hash,
			schedule_next_hash,
			locked_at,
			locked_by,
			schedule,
			next_run_at,
			workflow_file_path,
			environment,
			actor_node_id,
			actor_next_id,
			repository_node_id,
			repository_next_id,
			workflow_identifier,
			tier,
			tier_updated_at,
			commit_sha,
			actor_login,
			scatter_offset
		)
		VALUES %s
		`, strings.Join(insertRows, ","))

	r, err := db.Exec(insertSQL, params...)
	if err != nil {
		return err
	}
	if c, err := r.RowsAffected(); c != int64(len(sfrs)) || err != nil {
		return errors.Errorf("failed to insert, count %d err %s", c, err)
	}
	return nil
}

func (s *scheduleLockingSuite) Test_FindAndLock_RetrievesAndLocksOutstandingSchedules() {
	ctx := context.Background()
	rows, err := s.store.FindAndLock(ctx, "testWorker", tasksPerTick)
	s.Require().NoError(err)

	schedules := make([]string, 0)
	for _, r := range rows {
		schedules = append(schedules, r.Schedule)
	}

	s.ElementsMatch([]string{
		hourlyScheduleString,
		hourlyScheduleString,
		minuteScheduleString,
	}, schedules)
	s.Assert().Equal("testWorker", s.getLockedBy("unlocked"))
}

func (s *scheduleLockingSuite) Test_FindAndLock_ScatterTier1Check() {
	workerID := "testWorker"
	scheduleHash := "tier1Unlocked"

	ctx := context.Background()
	rows, err := s.store.FindAndLock(ctx, workerID, tasksPerTick)
	s.Require().NoError(err)
	s.Require().Len(rows, 3)

	// check locking has had expected effect
	postLock := s.getNextRunAt(scheduleHash)
	s.Require().NotEqual(dayAgo, postLock)
	s.Require().Equal(workerID, s.getLockedBy(scheduleHash))

	// then that unlocking works
	var tier1Row ScheduleRun
	for _, row := range rows {
		if row.Tier == 1 {
			tier1Row = row
			break
		}
	}
	s.Require().NotNil(tier1Row)

	err = s.store.ScheduleNextRun(ctx, tier1Row)
	s.Require().NoError(err)
	s.Assert().Equal("", s.getLockedBy(scheduleHash))

	now := time.Now().UTC()
	schedule, err := s.parser.ParseExpression(hourlyScheduleString)
	s.Assert().NoError(err)
	baseNextAt := schedule.Next(now)
	// we know the scatter offset is set to 0.5
	roughExpectation := baseNextAt.Add(testScatterOffsetDuration / 2)
	delta := roughExpectation.Sub(s.getNextRunAt(scheduleHash))

	// this is an hourly schedule, so we can use a second granularity to avoid flapping
	s.True(delta.Abs() < time.Second, "delta calculation off")
}

func (s *scheduleLockingSuite) Test_FindAndLock_MarkingRunsComplete() {
	workerID := "testWorker"
	scheduleHash := "unlocked"

	ctx := context.Background()
	rows, err := s.store.FindAndLock(ctx, workerID, tasksPerTick)
	s.Require().NoError(err)
	s.Require().Len(rows, 3)

	// check locking has had expected effect
	postLock := s.getNextRunAt(scheduleHash)
	s.Require().NotEqual(dayAgo, postLock)
	s.Require().Equal(workerID, s.getLockedBy(scheduleHash))

	// then that unlocking works
	var tier3Row ScheduleRun
	for _, row := range rows {
		if row.Tier == 3 {
			tier3Row = row
			break
		}
	}
	s.Require().NotNil(tier3Row)

	err = s.store.ScheduleNextRun(ctx, tier3Row)
	s.Require().NoError(err)
	s.Assert().Equal("", s.getLockedBy(scheduleHash))

	now := time.Now().UTC()
	schedule, err := s.parser.ParseExpression(hourlyScheduleString)
	s.Assert().NoError(err)
	baseNextAt := schedule.Next(now)
	// scatter offset 0.5, tier 3 has a scale factor of 2x, so use the full duration
	roughExpectation := baseNextAt.Add(testScatterOffsetDuration)
	delta := roughExpectation.Sub(s.getNextRunAt(scheduleHash))

	// this is an hourly schedule, so we can use a second granularity to avoid flapping
	s.True(delta.Abs() < time.Second, "delta calculation off")
}

func (s *scheduleLockingSuite) Test_FindAndLock_ScheduleRemovedConcurrently() {
	ctx := context.Background()
	rows, err := s.store.FindAndLock(ctx, "testWorker", tasksPerTick)
	s.Require().NoError(err)

	res, err := s.conn.Exec("DELETE FROM workflow_schedules WHERE id = ?", rows[0].ID)
	s.Require().NoError(err)
	c, err := res.RowsAffected()
	s.Require().NoError(err)
	s.Require().Equal(int64(1), c)

	err = s.store.ScheduleNextRun(ctx, rows[0])
	s.Require().NoError(err)
}

func (s *scheduleLockingSuite) Test_FindAndLock_HandlesNoSchedulesFound() {
	// lock everything
	_, err := s.conn.Exec("UPDATE workflow_schedules SET locked_by = 'test'")
	s.Require().NoError(err)

	ctx := context.Background()
	rows, err := s.store.FindAndLock(ctx, "any", tasksPerTick)
	s.Require().NoError(err)

	s.Len(rows, 0)
}

func (s *scheduleLockingSuite) Test_FindAndLock_DoesNotAffectLockedSchedules() {
	ctx := context.Background()
	_, err := s.store.FindAndLock(ctx, "testWorker", tasksPerTick)
	s.Require().NoError(err)

	s.Assert().Equal(originalLockedByID, s.getLockedBy("locked"))
}

func (s *scheduleLockingSuite) Test_FindAndLock_OnlyAffectsOwnEnvironment() {
	ctx := context.Background()
	_, err := s.store.FindAndLock(ctx, "testWorker", tasksPerTick)
	s.Require().NoError(err)

	s.Assert().Equal("", s.getLockedBy("unlockedLab"))
}

func (s *scheduleLockingSuite) Test_UnlockStale_UnlockingRowsThatSeemAbandoned() {
	// make locked row seem abandoned
	_, err := s.conn.Exec(`
		UPDATE workflow_schedules
		SET locked_at = DATE_ADD(UTC_TIMESTAMP, INTERVAL -1 DAY)
		WHERE locked_at IS NOT NULL
	`)
	s.Require().NoError(err)
	s.Require().Equal(originalLockedByID, s.getLockedBy("locked"))

	ctx := context.Background()
	err = s.store.UnlockStale(ctx)
	s.Require().NoError(err)

	s.Assert().Equal("", s.getLockedBy("locked"))
}

func (s *scheduleLockingSuite) Test_FindAndLock_UnlockingStaleRowsInBatches() {
	stat := statter.NewMockStatter(s.T())
	stat.EXPECT().Distribution(mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	stat.EXPECT().Timing(mock.Anything, mock.Anything, mock.Anything, mock.Anything)

	s.store = makeStoreWithObs(
		s.conn,
		defaultStoreSetup,
		deployer.NewGlobalIDMigrator(s.mockTwirpClient),
		s.mockTwirpClient.IsFeatureEnabledForActor,
		logger.TestLogger(),
		stat,
	)

	staleScheduleCount := unlockStaleBatchSize + 1
	worker := "launch-worker-unlock-stale"

	sfrs := make([]scheduleFixtureRow, 0, staleScheduleCount)
	for i := 0; i < staleScheduleCount; i++ {
		name := "schedule " + strconv.Itoa(i)
		sfrs = append(sfrs, scheduleFixtureRow{
			ScheduleHash:  name,
			NextRunAt:     time.Now().Add(-time.Minute),
			Schedule:      "* * * * *",
			Environment:   launchconfig.ProductionAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          1,
			TierUpdatedAt: &dayAgo,
			LockedAt:      &dayAgo, // abandoned locked row
			LockedBy:      &worker,
		})
	}
	err := insertScheduleRows(s.conn, sfrs)
	s.Require().NoError(err)

	s.Require().Equal(int64(staleScheduleCount), s.countByLockedBy(worker))

	ctx := context.Background()

	// First batch
	stat.EXPECT().Counter(mock.Anything, "scheduled.unlockedStale", mock.Anything, int64(unlockStaleBatchSize)).Once()

	// Second batch
	stat.EXPECT().Counter(mock.Anything, "scheduled.unlockedStale", mock.Anything, int64(1)).Once()

	err = s.store.UnlockStale(ctx)
	s.Require().NoError(err)

	s.Assert().Equal(int64(0), s.countByLockedBy(worker))
}

func (s *scheduleLockingSuite) Test_FindAndLock_UnlockingStaleRowsInBatches_SmallBatch() {
	stat := statter.NewMockStatter(s.T())
	stat.EXPECT().Distribution(mock.Anything, mock.Anything, mock.Anything, mock.Anything)
	stat.EXPECT().Timing(mock.Anything, mock.Anything, mock.Anything, mock.Anything)

	s.store = makeStoreWithObs(
		s.conn,
		defaultStoreSetup,
		deployer.NewGlobalIDMigrator(s.mockTwirpClient),
		s.mockTwirpClient.IsFeatureEnabledForActor,
		logger.TestLogger(),
		stat,
	)

	staleScheduleCount := 12
	worker := "launch-worker-unlock-stale"

	s.Require().Less(staleScheduleCount, unlockStaleBatchSize)

	sfrs := make([]scheduleFixtureRow, 0, staleScheduleCount)
	for i := 0; i < staleScheduleCount; i++ {
		name := "schedule " + strconv.Itoa(i)
		sfrs = append(sfrs, scheduleFixtureRow{
			ScheduleHash:  name,
			NextRunAt:     time.Now().Add(-time.Minute),
			Schedule:      "* * * * *",
			Environment:   launchconfig.ProductionAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          1,
			TierUpdatedAt: &dayAgo,
			LockedAt:      &dayAgo, // abandoned locked row
			LockedBy:      &worker,
		})
	}
	err := insertScheduleRows(s.conn, sfrs)
	s.Require().NoError(err)

	s.Require().Equal(int64(staleScheduleCount), s.countByLockedBy(worker))

	ctx := context.Background()

	// Single batch
	stat.EXPECT().Counter(mock.Anything, "scheduled.unlockedStale", mock.Anything, int64(staleScheduleCount)).Once()

	err = s.store.UnlockStale(ctx)
	s.Require().NoError(err)

	s.Assert().Equal(int64(0), s.countByLockedBy(worker))
}

func (s *scheduleLockingSuite) Test_FindAndLock_PrioritizesByTier() {
	// Lock all rows from the setup
	_, err := s.conn.Exec("UPDATE workflow_schedules SET locked_by = 'test'")
	s.Require().NoError(err)

	// Add new rows, expecting the following results (these tests lock five rows):
	// Tier 1, to run 5 min ago: score 12 * 5 = 60, locked
	// Tier 2, to run 10 min ago: score 4 * 10 = 40, locked
	// Tier 3, to run 20 min ago: score 1 * 20 = 20, locked
	// Tier 2, to run 4 min ago: score 4 * 4 = 16, locked
	// Tier 1, to run 1 min ago: score 12 * 1 = 12, locked
	// Tier 3, to run 10 min ago: score 1 * 10 = 10, not locked
	// Tier 2, to run 2 min ago: score 4 * 2 = 8, not locked
	// Tier 1, to run now: score 12 * 0 = 0, not locked

	scheduleDefinitions := [][]int{{1, 0}, {1, 1}, {1, 5}, {2, 2}, {2, 4}, {2, 10}, {3, 10}, {3, 20}}

	for _, scheduleDefinition := range scheduleDefinitions {
		name := "tier " + strconv.Itoa(scheduleDefinition[0]) + ", " + strconv.Itoa(scheduleDefinition[1]) + " min late"
		err = insertScheduleRow(s.conn, scheduleFixtureRow{
			ScheduleHash:  name,
			NextRunAt:     time.Now().Add(-time.Minute * time.Duration(scheduleDefinition[1])).Add(-5 * time.Second),
			Schedule:      "* * * * *",
			Environment:   launchconfig.ProductionAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          scheduleDefinition[0],
			TierUpdatedAt: &dayAgo,
		})
		s.Require().NoError(err)
	}

	// Perform the lock operation
	ctx := context.Background()
	res, err := s.store.FindAndLock(ctx, "testWorker", tasksPerTick)
	s.Assert().Len(res, tasksPerTick)
	s.Require().NoError(err)

	// Make sure the expected ones are locked
	s.Assert().Equal("testWorker", s.getLockedBy("tier 1, 5 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 2, 10 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 3, 20 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 2, 4 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 1, 1 min late"))
	s.Assert().Equal("", s.getLockedBy("tier 3, 10 min late"))
	s.Assert().Equal("", s.getLockedBy("tier 2, 2 min late"))
	s.Assert().Equal("", s.getLockedBy("tier 1, 0 min late"))
}

func (s *scheduleLockingSuite) Test_FindAndLock__GetsLowerTiersWithHigherPriorityWhenCandidatesFull() {
	recordingLogger := testutils.NewRecordingLogger()
	s.store = makeStoreWithObs(
		s.conn,
		defaultStoreSetup,
		deployer.NewGlobalIDMigrator(s.mockTwirpClient),
		s.mockTwirpClient.IsFeatureEnabledForActor,
		recordingLogger.Logger,
		statter.NullStatter(),
	)

	// Lock all rows from the setup
	_, err := s.conn.Exec("UPDATE workflow_schedules SET locked_by = 'test'")
	s.Require().NoError(err)

	// Add new rows, expecting the following results (these tests lock five rows):
	// Tier 1, to run 5 min ago: score 12 * 5 = 60, locked
	// Tier 2, to run 10 min ago: score 4 * 10 = 40, locked
	// Tier 3, to run 20 min ago: score 1 * 20 = 20, locked
	// Tier 2, to run 4 min ago: score 4 * 4 = 16, locked
	// Tier 1, to run 1 min ago: score 12 * 1 = 12, locked
	// Tier 2, to run 2 min ago: score 4 * 2 = 8, not locked
	// Tier 3, to run 5 min ago: score 1 * 5 = 5, not locked
	// Tier 1, to run now: score 12 * 0 = 0, not locked

	// When we fetch the schedules:
	// Tier 1 - fetches all 3 schedules, minWeightedAge is 0
	// Tier 2 - Since there aren't 5 schedules yet, fetches all 3 tier 2 schedules, takes only the top 5 candidates, minWeightedAge updated to 8
	// Tier 3 - fetches only the 1 tier 3 schedule with weighted age higher than 8

	scheduleDefinitions := [][]int{{1, 0}, {1, 1}, {1, 5}, {2, 2}, {2, 4}, {2, 10}, {3, 5}, {3, 20}}

	for _, scheduleDefinition := range scheduleDefinitions {
		name := "tier " + strconv.Itoa(scheduleDefinition[0]) + ", " + strconv.Itoa(scheduleDefinition[1]) + " min late"
		err = insertScheduleRow(s.conn, scheduleFixtureRow{
			ScheduleHash:  name,
			NextRunAt:     time.Now().Add(-time.Minute * time.Duration(scheduleDefinition[1])).Add(-5 * time.Second),
			Schedule:      "* * * * *",
			Environment:   launchconfig.ProductionAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          scheduleDefinition[0],
			TierUpdatedAt: &dayAgo,
		})
		s.Require().NoError(err)
	}

	// Perform the lock operation
	ctx := context.Background()
	res, err := s.store.FindAndLock(ctx, "testWorker", tasksPerTick)
	s.Assert().Len(res, tasksPerTick)
	s.Require().NoError(err)

	// Make sure the expected ones are locked
	s.Assert().Equal("testWorker", s.getLockedBy("tier 1, 5 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 2, 10 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 3, 20 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 2, 4 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 1, 1 min late"))
	s.Assert().Equal("", s.getLockedBy("tier 3, 5 min late"))
	s.Assert().Equal("", s.getLockedBy("tier 2, 2 min late"))
	s.Assert().Equal("", s.getLockedBy("tier 1, 0 min late"))

	// Assert loaded schedule counts
	s.assertLogged(recordingLogger, "gh.launch.schedule.tier1.count=3")
	s.assertLogged(recordingLogger, "gh.launch.schedule.tier2.count=3")
	s.assertLogged(recordingLogger, "gh.launch.schedule.tier3.count=1")
}

func (s *scheduleLockingSuite) Test_FindAndLock_GetsLowerTiersWithLowerPriorityWhenCandidatesNotFull() {
	recordingLogger := testutils.NewRecordingLogger()
	s.store = makeStoreWithObs(
		s.conn,
		defaultStoreSetup,
		deployer.NewGlobalIDMigrator(s.mockTwirpClient),
		s.mockTwirpClient.IsFeatureEnabledForActor,
		recordingLogger.Logger,
		statter.NullStatter(),
	)

	// Lock all rows from the setup
	_, err := s.conn.Exec("UPDATE workflow_schedules SET locked_by = 'test'")
	s.Require().NoError(err)

	// Add new rows, expecting the following results (these tests lock five rows):
	// Tier 1, to run 20 minutes ago: score 12 * 20 = 240, locked
	// Tier 1, to run 25 minutes ago: score 12 * 25 = 300, locked
	// Tier 1, to run 30 minutes ago: score 12 * 30 = 360, locked
	// Tier 2, to run 10 minutes ago: 4 * 10 = 40, locked
	// Tier 3, to run 20 minutes ago: 1 * 20 = 20, locked
	// Tier 3, to run 5 minutes ago: 1 * 5 = 5, not locked

	// When we fetch the schedules:
	// Tier 1 - fetches all 3 schedules, minWeightedAge is 240
	// Tier 2 - Since there aren't 5 schedules yet, fetches all 1 tier 2 schedules, takes only the top 5 candidates, minWeightedAge updated to 40
	// Tier 3 - Since there aren't 5 schedules yet, fetches all 2 tier 3 schedules, takes only the top 5 candidates

	scheduleDefinitions := [][]int{{1, 20}, {1, 25}, {1, 30}, {2, 10}, {3, 20}, {3, 5}}

	for _, scheduleDefinition := range scheduleDefinitions {
		name := "tier " + strconv.Itoa(scheduleDefinition[0]) + ", " + strconv.Itoa(scheduleDefinition[1]) + " min late"
		err = insertScheduleRow(s.conn, scheduleFixtureRow{
			ScheduleHash:  name,
			NextRunAt:     time.Now().Add(-time.Minute * time.Duration(scheduleDefinition[1])).Add(-5 * time.Second),
			Schedule:      "* * * * *",
			Environment:   launchconfig.ProductionAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          scheduleDefinition[0],
			TierUpdatedAt: &dayAgo,
		})
		s.Require().NoError(err)
	}

	// Perform the lock operation
	ctx := context.Background()
	res, err := s.store.FindAndLock(ctx, "testWorker", tasksPerTick)
	s.Assert().Len(res, tasksPerTick)
	s.Require().NoError(err)

	// Make sure the expected ones are locked
	s.Assert().Equal("testWorker", s.getLockedBy("tier 1, 20 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 1, 25 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 1, 30 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 2, 10 min late"))
	s.Assert().Equal("testWorker", s.getLockedBy("tier 3, 20 min late"))
	s.Assert().Equal("", s.getLockedBy("tier 3, 5 min late"))

	// Assert loaded schedule counts
	s.assertLogged(recordingLogger, "gh.launch.schedule.tier1.count=3")
	s.assertLogged(recordingLogger, "gh.launch.schedule.tier2.count=1")
	s.assertLogged(recordingLogger, "gh.launch.schedule.tier3.count=2")
}

func (s *scheduleLockingSuite) Test_FindAndLock_DoesntUnlockZero() {
	// Lock all rows from the setup
	_, err := s.conn.Exec("UPDATE workflow_schedules SET locked_by = 'test'")
	s.Require().NoError(err)

	// Create exactly tasksPerTick rows, all with the same tier and next run time
	for i := 0; i < tasksPerTick; i++ {
		name := "schedule " + strconv.Itoa(i)
		err = insertScheduleRow(s.conn, scheduleFixtureRow{
			ScheduleHash:  name,
			NextRunAt:     time.Now().Add(-time.Minute),
			Schedule:      "* * * * *",
			Environment:   launchconfig.ProductionAppEnv,
			RepoGID:       scheduleTestsRepoGID,
			Tier:          1,
			TierUpdatedAt: &dayAgo,
		})
		s.Require().NoError(err)
	}

	// Validate that we don't get a sql error (code used to be trying to call `unlock` with zero rows)
	ctx := context.Background()
	res, err := s.store.FindAndLock(ctx, "testWorker", tasksPerTick)
	s.Assert().Len(res, tasksPerTick)
	s.Require().NoError(err) // Before bugfix this would return a failure here
}

func (s *scheduleLockingSuite) getLockedBy(scheduleHash string) string {
	var lockedBy *string
	row := s.conn.QueryRow(`
			SELECT locked_by
			FROM workflow_schedules
			WHERE schedule_hash = ?
		`, scheduleHash)
	err := row.Scan(&lockedBy)
	s.Require().NoError(err)
	if lockedBy == nil {
		lockedBy = &unlockedLockedByValue
	}
	return *lockedBy
}

func (s *scheduleLockingSuite) countByLockedBy(worker string) int64 {
	var count int64
	row := s.conn.QueryRow(`
			SELECT COUNT(*)
			FROM workflow_schedules
			WHERE locked_by = ?
		`, worker)
	err := row.Scan(&count)
	s.Require().NoError(err)
	return count
}

func (s *scheduleLockingSuite) getNextRunAt(scheduleHash string) time.Time {
	var nextRunAt time.Time
	row := s.conn.QueryRow(`
			SELECT next_run_at
			FROM workflow_schedules
			WHERE schedule_hash = ?
		`, scheduleHash)
	err := row.Scan(&nextRunAt)
	s.Require().NoError(err)
	return nextRunAt
}

func (s *scheduleLockingSuite) assertLogged(logger testutils.RecordingLogger, message string) {
	s.Require().Contains(logger.String(), message, fmt.Sprintf("\nOutput:\n%s\nShould contain:\n%s", logger.String(), message))
}

func TestScheduleRepoLocking(t *testing.T) {
	testutils.NoShort(t)
	suite.Run(t, new(scheduleLockingSuite))
}
