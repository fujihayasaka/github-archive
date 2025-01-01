package schedules

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
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	launchconfig "github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services/deploy/scheduled/config"
	"github.com/github/launch/services/deploy/scheduled/model"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/testutils"
)

const (
	fixtureOriginalSchedule = "* * 2 2 2"
	labWorkflow             = ".github/workflows-lab/main.yml"
	prodWorkflow            = ".github/workflows/main.yml"
	nextIDPrefix            = "next-"
	metdataFragment         = `
		commit_sha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1',
		actor_login='actor_login_one',
	`
	repoIDOne = types.GlobalID("repo_id_one")
)

var (
	testScatterOffsetDuration = time.Minute * 5

	defaultStoreSetup = storeSetup{
		environment: launchconfig.ProductionAppEnv,
	}

	scheduleMD = model.ScheduleSync{
		ActorID:    nextIDFromGlobalID("ActorIDUpdate"),
		ActorLogin: "ActorLoginUpdate",
		CommitSHA:  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1",
		RepoNodeID: nextIDFromGlobalID("repo_id_one"),
	}
)

type storeSetup struct {
	environment   launchconfig.AppEnv
	isMultiTenant bool
}

type scheduleTestRow struct {
	ID            int64
	Tier          int
	Schedule      string
	NextAt        time.Time
	CommitSHA     types.CommitSha
	ActorLogin    string
	ActorID       types.GlobalID
	RepoNodeID    types.GlobalID
	ScatterOffset float64
	Environment   string
}

func TestScheduleUpdate(t *testing.T) {
	testutils.NoShort(t)
	suite.Run(t, new(scheduleUpdateSuite))
}

type scheduleUpdateSuite struct {
	suite.Suite
	conn             *sql.DB
	store            Store
	parser           model.ScheduleParser
	globalIDMigrator deployer.GlobalIDMigrator
	mockTwirpClient  *ghtwirp.MockClient
}

func (s *scheduleUpdateSuite) SetupTest() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)

	s.mockTwirpClient = &ghtwirp.MockClient{}
	s.globalIDMigrator = deployer.NewGlobalIDMigrator(s.mockTwirpClient)

	s.conn = conn
	s.store = makeStore(conn, defaultStoreSetup, s.globalIDMigrator, s.mockTwirpClient.IsFeatureEnabledForActor)
	s.Require().NoError(s.store.StartTests())
	s.parser = model.NewScheduleParser()

	s.Require().NoError(s.store.EmptyForTests())

	s.mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		if strings.HasPrefix(globalID, nextIDPrefix) {
			// already a next id, return original argument
			return types.GlobalID(globalID)
		}
		return nextIDFromGlobalID(types.GlobalID(globalID))
	}, nil)

	examples := []struct {
		identifier  string
		wFilePath   string
		environment string
	}{
		{
			identifier:  "workflow_identifier_0",
			wFilePath:   prodWorkflow,
			environment: "production",
		},
		{
			identifier:  "workflow_identifier_1",
			environment: "production",
			wFilePath:   prodWorkflow,
		},
		{
			identifier:  "workflow_identifier_2",
			wFilePath:   prodWorkflow,
			environment: "production",
		},
		{
			identifier:  "workflow_identifier_0",
			wFilePath:   labWorkflow,
			environment: "lab",
		},
	}

	for _, eg := range examples {
		_, err := s.conn.Exec(fmt.Sprintf(`
			INSERT INTO workflow_schedules
			SET
				tier=?,
				repository_node_id=?,
				repository_next_id=?,
				schedule_hash=?,
				schedule_next_hash=?,
				workflow_identifier=?,
				schedule=?,
				workflow_file_path=?,
				environment=?,
				actor_node_id='actor_id_one',
				actor_next_id='U_actornext',
				-- real values 0..1, easier to spot in tests
				scatter_offset=-99,
				%s
				next_run_at='2000-01-01'
			`, metdataFragment),
			types.RepositoryTier1,
			nextIDFromGlobalID(repoIDOne),
			nextIDFromGlobalID(repoIDOne),
			NewScheduleHash(
				nextIDFromGlobalID(repoIDOne),
				eg.identifier,
				eg.wFilePath,
				fixtureOriginalSchedule,
			),
			NewScheduleHash(
				nextIDFromGlobalID(repoIDOne),
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

func (s *scheduleUpdateSuite) TearDownTest() {
	s.Require().NoError(s.store.EndTests())
	err := s.conn.Close()
	s.Require().NoError(err)
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_MixedOperations() {
	newSchedule := makeSelectorMapForFile(prodWorkflow, map[string]string{
		"workflow_identifier_new": "* * * * *",
		"workflow_identifier_0":   "* * * * 1",
		"workflow_identifier_2":   "* * * * 2",
	})
	update := s.updateFor(newSchedule, types.RepositoryTier1)

	ensureGetRow := func(identifer string, row *scheduleTestRow) {
		err := s.getScheduleForMainWorkflowByIdentifier(identifer, row)
		s.NoError(err, "failed to find row with identifier '%s'", identifer)
	}

	ctx := context.Background()
	err := s.store.PersistUpdate(ctx, update)
	s.Require().NoError(err)

	updatedRow := scheduleTestRow{}
	ensureGetRow("workflow_identifier_0", &updatedRow)
	s.Equal("* * * * 1", updatedRow.Schedule)
	s.Equal(1, updatedRow.Tier)
	s.Equal(scheduleMD.ActorID, updatedRow.ActorID)
	s.Equal(scheduleMD.RepoNodeID, updatedRow.RepoNodeID)
	s.Equal(scheduleMD.ActorLogin, updatedRow.ActorLogin)

	createdRow := scheduleTestRow{}
	ensureGetRow("workflow_identifier_new", &createdRow)
	s.Equal("* * * * *", createdRow.Schedule)
	s.Equal(scheduleMD.ActorID, createdRow.ActorID)
	s.Equal(scheduleMD.RepoNodeID, createdRow.RepoNodeID)

	unaffectedRow := scheduleTestRow{}
	ensureGetRow("workflow_identifier_2", &unaffectedRow)
	s.Equal("* * * * 2", unaffectedRow.Schedule)
	s.Equal(scheduleMD.ActorID, unaffectedRow.ActorID)
	s.Equal(scheduleMD.RepoNodeID, unaffectedRow.RepoNodeID)

	err = s.getScheduleForMainWorkflowByIdentifier("workflow_identifier_1", &unaffectedRow)
	s.Require().EqualError(err, "sql: no rows in result set", "should have deleted rows not in new schedule set")
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_Reinserted() {
	// Updating workflow_identifier_0, workflow_identifier_2 should be untouched
	newSchedule := makeSelectorMapForFile(prodWorkflow, map[string]string{
		"workflow_identifier_0": "* * * * 1",
		"workflow_identifier_2": "* * 2 2 2",
	})
	update := s.updateFor(newSchedule, types.RepositoryTier1)

	ensureGetRow := func(identifer string, row *scheduleTestRow) {
		err := s.getScheduleForMainWorkflowByIdentifier(identifer, row)
		s.NoError(err, "failed to find row with identifier '%s'", identifer)
	}

	ctx := context.Background()
	updatedRowOriginal := scheduleTestRow{}
	ensureGetRow("workflow_identifier_0", &updatedRowOriginal)

	unaffectedRowOriginal := scheduleTestRow{}
	ensureGetRow("workflow_identifier_2", &unaffectedRowOriginal)
	err := s.store.PersistUpdate(ctx, update)
	s.Require().NoError(err)

	updatedRow := scheduleTestRow{}
	ensureGetRow("workflow_identifier_0", &updatedRow)
	s.Equal("* * * * 1", updatedRow.Schedule)
	s.Equal(1, updatedRow.Tier)
	s.NotEqual(updatedRowOriginal.ID, updatedRow.ID)
	s.Equal(scheduleMD.ActorID, updatedRow.ActorID)
	s.Equal(nextIDFromGlobalID(repoIDOne), updatedRow.RepoNodeID)

	unaffectedRow := scheduleTestRow{}
	ensureGetRow("workflow_identifier_2", &unaffectedRow)
	s.Equal("* * 2 2 2", unaffectedRow.Schedule)
	s.Equal(unaffectedRowOriginal.ID, unaffectedRow.ID)
	s.Equal(unaffectedRowOriginal.ActorID, unaffectedRow.ActorID)
	s.Equal(unaffectedRowOriginal.RepoNodeID, unaffectedRow.RepoNodeID)

	err = s.getScheduleForMainWorkflowByIdentifier("workflow_identifier_1", &unaffectedRow)
	s.Require().EqualError(err, "sql: no rows in result set", "should have deleted rows not in new schedule set")
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_DeleteOnly() {
	update := s.updateFor(nil, types.RepositoryTier1)

	ctx := context.Background()
	err := s.store.PersistUpdate(ctx, update)
	s.Require().NoError(err)

	deletedRow := scheduleTestRow{}
	err = s.getScheduleForMainWorkflowByIdentifier("workflow_identifier_0", &deletedRow)
	s.Require().EqualError(err, "sql: no rows in result set", "should have deleted rows")
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_CreateOnly() {
	update := s.updateFor(makeSelectorMapForFile(prodWorkflow, map[string]string{
		"workflow_identifier_new": "* * * * *",
		"workflow_identifier_0":   "* * * * *",
		"workflow_identifier_1":   "* * * * *",
		"workflow_identifier_2":   "* * * * *",
	}), types.RepositoryTier1)

	ctx := context.Background()
	err := s.store.PersistUpdate(ctx, update)
	s.NoError(err)

	createdRow := scheduleTestRow{}
	err = s.getScheduleForMainWorkflowByIdentifier("workflow_identifier_new", &createdRow)
	s.Require().NoError(err, "failed to find created row")
	s.Equal("* * * * *", createdRow.Schedule)
	s.Equal(int(types.RepositoryTier1), createdRow.Tier)
	s.assertRowUpdatedOrCreated(createdRow)

	for i := 0; i < 3; i++ {
		unaffectedRow := scheduleTestRow{}
		id := fmt.Sprintf("workflow_identifier_%d", i)
		err = s.getScheduleForMainWorkflowByIdentifier(id, &unaffectedRow)
		s.NoError(err, "failed to find unaffected row '%s'", id)
		s.Equal("* * * * *", unaffectedRow.Schedule)
		s.Equal(scheduleMD.ActorID, unaffectedRow.ActorID)
		s.Equal(scheduleMD.RepoNodeID, unaffectedRow.RepoNodeID)
	}
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_ScatterForNonTier1() {
	update := s.updateFor(makeSelectorMapForFile(prodWorkflow, map[string]string{
		"workflow_identifier_new": "* * * * *",
	}), types.RepositoryTier3)

	ctx := context.Background()
	err := s.store.PersistUpdate(ctx, update)
	s.NoError(err)

	createdRow := scheduleTestRow{}
	err = s.getScheduleForMainWorkflowByIdentifier("workflow_identifier_new", &createdRow)
	s.Require().NoError(err, "failed to find created row")
	s.Equal("* * * * *", createdRow.Schedule)
	s.Equal(int(types.RepositoryTier3), createdRow.Tier)
	s.assertRowUpdatedOrCreated(createdRow)
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_MissingActor() {
	update := s.updateFor(makeSelectorMapForFile(prodWorkflow, map[string]string{
		"workflow_identifier_new": "* * * * *",
	}), types.RepositoryTier1)

	update.ActorID = ""
	update.ActorLogin = ""

	ctx := context.Background()
	err := s.store.PersistUpdate(ctx, update)
	s.Error(err)
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_UpdateOnly() {
	update := s.updateFor(makeSelectorMapForFile(prodWorkflow, map[string]string{
		"workflow_identifier_0": "* * * * 0",
		"workflow_identifier_1": "* * * * 1",
		"workflow_identifier_2": "* * * * 2",
	}), types.RepositoryTier1)

	ctx := context.Background()
	err := s.store.PersistUpdate(ctx, update)
	s.Require().NoError(err)

	for i := 0; i < 3; i++ {
		updatedRow := scheduleTestRow{}
		id := fmt.Sprintf("workflow_identifier_%d", i)
		err = s.getScheduleForMainWorkflowByIdentifier(id, &updatedRow)
		s.NoError(err, "failed to find row '%s'", id)
		s.Equal(fmt.Sprintf("* * * * %d", i), updatedRow.Schedule)
		s.Equal(scheduleMD.ActorID, updatedRow.ActorID)
		s.Equal(scheduleMD.RepoNodeID, updatedRow.RepoNodeID)
	}
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_CommitShaSync() {
	update := s.updateFor(makeSelectorMapForFile(prodWorkflow, map[string]string{
		"workflow_identifier_0": "* * * * 0",
		"workflow_identifier_1": fixtureOriginalSchedule,
	}), types.RepositoryTier1)

	ctx := context.Background()
	err := s.store.PersistUpdate(ctx, update)
	s.Require().NoError(err)

	affectedRow := &scheduleTestRow{}
	err = s.getScheduleForMainWorkflowByIdentifier("workflow_identifier_0", affectedRow)
	s.Require().NoError(err)
	s.Equal("* * * * 0", affectedRow.Schedule)
	s.Equal(scheduleMD.CommitSHA, affectedRow.CommitSHA)

	unaffectedRow := &scheduleTestRow{}
	err = s.getScheduleForMainWorkflowByIdentifier("workflow_identifier_1", unaffectedRow)
	s.Require().NoError(err)
	s.Equal(fixtureOriginalSchedule, unaffectedRow.Schedule)
	s.Equal(scheduleMD.CommitSHA, unaffectedRow.CommitSHA)
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_EnvironmentSpecific() {
	prepareProd := s.updateFor(makeSelectorMapForFile(prodWorkflow, map[string]string{
		"workflow_identifier_0": fixtureOriginalSchedule,
	}), types.RepositoryTier1)

	ctx := context.Background()
	err := s.store.PersistUpdate(ctx, prepareProd)
	s.Require().NoError(err)
	s.assertRowPresent("workflow_identifier_0", prodWorkflow, fixtureOriginalSchedule, "production")

	labRepo := makeStore(s.conn, storeSetup{
		environment: "lab",
	}, s.globalIDMigrator, s.mockTwirpClient.IsFeatureEnabledForActor)

	// update with empty - clearing the repo
	err = labRepo.PersistUpdate(ctx, s.updateFor(makeSelectorMapForFile(prodWorkflow, map[string]string{}), types.RepositoryTier1))
	s.Require().NoError(err)

	s.assertRowPresent("workflow_identifier_0", prodWorkflow, fixtureOriginalSchedule, "production")
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_EnvironmentSpecific_NextColumn() {
	prepareProd := s.updateFor(makeSelectorMapForFile(prodWorkflow, map[string]string{
		"workflow_identifier_0": fixtureOriginalSchedule,
	}), types.RepositoryTier1)

	ctx := context.Background()
	err := s.store.PersistUpdate(ctx, prepareProd)
	s.Require().NoError(err)
	s.assertRowPresent_NextHash("workflow_identifier_0", prodWorkflow, fixtureOriginalSchedule, "production")

	labRepo := makeStore(s.conn, storeSetup{
		environment: "lab",
	}, s.globalIDMigrator, s.mockTwirpClient.IsFeatureEnabledForActor)

	// update with empty - clearing the repo
	err = labRepo.PersistUpdate(ctx, s.updateFor(makeSelectorMapForFile(prodWorkflow, map[string]string{}), types.RepositoryTier1))
	s.Require().NoError(err)

	s.assertRowPresent_NextHash("workflow_identifier_0", prodWorkflow, fixtureOriginalSchedule, "production")
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_StoresEnvironment() {
	update := s.updateFor(makeSelectorMapForFile(prodWorkflow, map[string]string{
		"workflow_identifier_0": "* * * * *",
	}), types.RepositoryTier1)

	ctx := context.Background()
	err := s.store.PersistUpdate(ctx, update)
	s.Require().NoError(err)

	row := &scheduleTestRow{}
	err = s.getScheduleForMainWorkflowByIdentifier("workflow_identifier_0", row)
	s.Require().NoError(err)
	s.Equal("production", row.Environment)
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_RemoveSchedules() {
	ctx := context.Background()
	err := s.store.RemoveSchedules(ctx, repoIDOne)
	s.Require().NoError(err)

	deleted := scheduleTestRow{}
	err = s.getScheduleForMainWorkflowByIdentifier("workflow_identifier_1", &deleted)
	s.EqualError(err, "sql: no rows in result set")
	s.assertRowPresent("workflow_identifier_0", labWorkflow, fixtureOriginalSchedule, "lab")
}

func (s *scheduleUpdateSuite) Test_PersistUpdate_RemoveSchedules_NextColumn() {
	ctx := context.Background()
	err := s.store.RemoveSchedules(ctx, repoIDOne)
	s.Require().NoError(err)

	deleted := scheduleTestRow{}
	err = s.getScheduleForMainWorkflowByRepository(repoIDOne.String(), &deleted)
	s.EqualError(err, "sql: no rows in result set")

	err = s.getScheduleForMainWorkflowByRepositoryNextColumn(nextIDFromGlobalID(repoIDOne).String(), &deleted)
	s.EqualError(err, "sql: no rows in result set")
}

func (s *scheduleUpdateSuite) updateFor(content map[types.WorkflowSelector]string, tier types.RepositoryTier) model.ScheduleSync {
	return model.ScheduleSync{
		RepoNodeID:                repoIDOne,
		FlowIdentifiersToSchedule: content,
		Tier:                      tier,
		ActorID:                   scheduleMD.ActorID,
		ActorLogin:                scheduleMD.ActorLogin,
		CommitSHA:                 scheduleMD.CommitSHA,
	}
}

func (s *scheduleUpdateSuite) assertRowPresent(ident string, wfp string, schedule, env string) {
	unaffected := scheduleTestRow{}
	h := NewScheduleHash(nextIDFromGlobalID(repoIDOne), ident, wfp, schedule)
	row := s.conn.QueryRow(`select schedule from workflow_schedules
		where schedule_hash = ?
			and environment = ?
		`, h, env)
	err := row.Scan(&unaffected.Schedule)
	s.Require().NoError(err)
}

func (s *scheduleUpdateSuite) assertRowPresent_NextHash(ident string, wfp string, schedule, env string) {
	unaffected := scheduleTestRow{}
	h := NewScheduleHash(nextIDFromGlobalID(repoIDOne), ident, wfp, schedule)
	row := s.conn.QueryRow(`select schedule from workflow_schedules
		where schedule_next_hash = ?
			and environment = ?
		`, h, env)
	err := row.Scan(&unaffected.Schedule)
	s.Require().NoError(err)
}

func (s *scheduleUpdateSuite) assertRowUpdatedOrCreated(r scheduleTestRow) {
	s.NotEqual(-99, r.NextAt, "should have regenerated offset")
	s.NotEqual(0, r.ScatterOffset, "should not be zero (possible, but radically unlikely)")

	schedule, err := s.parser.ParseExpression(r.Schedule)
	s.Assert().NoError(err)

	runAtBase := schedule.Next(time.Now().UTC())
	upperBound := runAtBase
	if r.Tier != int(types.RepositoryTier1) {
		upperBound = runAtBase.Add(testScatterOffsetDuration * tierScatterScaleFactor)
	} else {
		upperBound = runAtBase.Add(testScatterOffsetDuration)
	}
	s.True(r.NextAt.After(runAtBase) && r.NextAt.Before(upperBound), "next at mischeduled")

	s.Equal(scheduleMD.CommitSHA, r.CommitSHA)
	s.Equal(scheduleMD.ActorLogin, r.ActorLogin)
	s.Equal(scheduleMD.ActorID, r.ActorID)
}

func (s *scheduleUpdateSuite) assertRowUpdatedOrCreated_NextGlobalID(r scheduleTestRow) {
	s.NotEqual(-99, r.NextAt, "should have regenerated offset")
	s.NotEqual(0, r.ScatterOffset, "should not be zero (possible, but radically unlikely)")

	schedule, err := s.parser.ParseExpression(r.Schedule)
	s.Assert().NoError(err)

	runAtBase := schedule.Next(time.Now().UTC())
	upperBound := runAtBase
	if r.Tier != int(types.RepositoryTier1) {
		upperBound = runAtBase.Add(testScatterOffsetDuration * tierScatterScaleFactor)
	} else {
		upperBound = runAtBase.Add(testScatterOffsetDuration)
	}
	s.True(r.NextAt.After(runAtBase) && r.NextAt.Before(upperBound), "next at mischeduled")

	s.Equal(scheduleMD.CommitSHA, r.CommitSHA)
	s.Equal(scheduleMD.ActorLogin, r.ActorLogin)
	s.Equal(scheduleMD.ActorID, r.ActorID)
	s.Equal(scheduleMD.RepoNodeID, r.RepoNodeID)
}

func (s *scheduleUpdateSuite) getScheduleForMainWorkflowByIdentifier(flowIdentifier string, r *scheduleTestRow) error {
	row := s.conn.QueryRow(`
			SELECT
				id,
				tier,
				schedule,
				next_run_at,
				scatter_offset,
				commit_sha,
				actor_login,
				actor_node_id,
				repository_node_id,
				environment
			FROM workflow_schedules
			WHERE workflow_identifier = ?
				AND environment = ?
		`, flowIdentifier, "production")
	return row.Scan(
		&r.ID,
		&r.Tier,
		&r.Schedule,
		&r.NextAt,
		&r.ScatterOffset,
		&r.CommitSHA,
		&r.ActorLogin,
		&r.ActorID,
		&r.RepoNodeID,
		&r.Environment,
	)
}

func (s *scheduleUpdateSuite) getScheduleForMainWorkflowByRepository(repoID string, r *scheduleTestRow) error {
	row := s.conn.QueryRow(`
			SELECT
				id,
				tier,
				schedule,
				next_run_at,
				scatter_offset,
				commit_sha,
				actor_login,
				actor_node_id,
				environment
			FROM workflow_schedules
			WHERE repository_node_id = ?
				AND environment = ?
		`, repoID, "production")
	return row.Scan(
		&r.ID,
		&r.Tier,
		&r.Schedule,
		&r.NextAt,
		&r.ScatterOffset,
		&r.CommitSHA,
		&r.ActorLogin,
		&r.ActorID,
		&r.Environment,
	)
}

func (s *scheduleUpdateSuite) getScheduleForMainWorkflowByRepositoryNextColumn(repoID string, r *scheduleTestRow) error {
	row := s.conn.QueryRow(`
			SELECT
				id,
				tier,
				schedule,
				next_run_at,
				scatter_offset,
				commit_sha,
				actor_login,
				actor_node_id,
				environment
			FROM workflow_schedules
			WHERE repository_next_id = ?
				AND environment = ?
		`, repoID, "production")
	return row.Scan(
		&r.ID,
		&r.Tier,
		&r.Schedule,
		&r.NextAt,
		&r.ScatterOffset,
		&r.CommitSHA,
		&r.ActorLogin,
		&r.ActorID,
		&r.Environment,
	)
}

func makeSelectorMapForFile(path string, input map[string]string) map[types.WorkflowSelector]string {
	out := make(map[types.WorkflowSelector]string, len(input))
	for id, cron := range input {
		out[types.WorkflowSelector{
			WorkflowPath: path,
			Identifier:   id,
		}] = cron
	}
	return out
}

// https://github.com/github/c2c-actions-experience/issues/6602 is tracking the removal of this function
func nextIDFromGlobalID(legacyGID types.GlobalID) types.GlobalID {
	return types.GlobalID(fmt.Sprintf("%s%s", nextIDPrefix, legacyGID))
}

func makeStoreWithObs(
	conn *sql.DB,
	setup storeSetup,
	globalIDMigrator deployer.GlobalIDMigrator,
	featureEnabled func(context.Context, string, types.GlobalID) bool,
	log logger.Logger,
	stat statter.Statter,
) Store {

	return New(
		asql.New(conn, log, stat, testutils.NewNoopBreaker(), asql.LaunchCluster),
		log,
		model.NewScheduleParser(),
		config.ScheduledConfig{
			ScatterOffsetDuration:     testScatterOffsetDuration,
			ReassignWorkAfterDuration: time.Hour,
			TasksPerTick:              5,
			Environment:               setup.environment,
		},
		clock.New(),
		stat,
		globalIDMigrator,
		featureEnabled,
	)
}

func makeStore(
	conn *sql.DB,
	setup storeSetup,
	globalIDMigrator deployer.GlobalIDMigrator,
	featureEnabled func(context.Context, string, types.GlobalID) bool,
) Store {
	log := logger.TestLogger()
	stat := statter.NullStatter()
	return makeStoreWithObs(conn, setup, globalIDMigrator, featureEnabled, log, stat)
}
