package schedules

import (
	"context"
	"database/sql"
	"time"

	"github.com/facebookgo/clock"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	launchconfig "github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services/deploy/scheduled/config"
	"github.com/github/launch/services/deploy/scheduled/model"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
)

type Store interface {
	PersistUpdate(ctx context.Context, update model.ScheduleSync) error
	UpdateOwnerID(ctx context.Context, repoNodeID types.GlobalID, ownerID int64) error
	FindAndLock(ctx context.Context, workerID string, tasksPerTick int) ([]ScheduleRun, error)
	ScheduleNextRun(ctx context.Context, run ScheduleRun) error
	UnlockStale(context.Context) error
	RemoveSchedules(ctx context.Context, id types.GlobalID) error
	DeleteSchedulesForRepository(ctx context.Context, env launchconfig.AppEnv, id types.GlobalID) (int64, error)
	DeleteScheduleForWorkflow(ctx context.Context, env launchconfig.AppEnv, repoID types.GlobalID, workflowFilePath string) (int64, error)
	ListSchedulesForRepository(ctx context.Context, env launchconfig.AppEnv, id types.GlobalID) ([]WorkflowSchedule, error)

	// test helper methods
	EmptyForTests() error
	CountForTests(repoNodeID types.GlobalID) (int, error)
	CountForTestsNextColumn(repoNodeID types.GlobalID) (int, error)
	CountForFileForTests(repoNodeID types.GlobalID, workflowFile string) (int, error)
	CountForFileForTestsNextColumn(repoNodeID types.GlobalID, workflowFile string) (int, error)
	StartTests() error
	EndTests() error
}

func New(
	DB *asql.SQL,
	Logger logger.Logger,
	ScheduleParser model.ScheduleParser,
	Cfg config.ScheduledConfig,
	clock clock.Clock,
	statter statter.Statter,
	gidMigrator deployer.GlobalIDMigrator,
	featureEnabled func(context.Context, string, types.GlobalID) bool,
) Store {
	return &dbStore{
		DB:             DB,
		rawDB:          DB.Conn(),
		obs:            observability.New(Logger, statter),
		ScheduleParser: ScheduleParser,
		Cfg:            Cfg,
		clock:          clock,
		gidMigrator:    gidMigrator,
		featureEnabled: featureEnabled,
	}
}

type dbStore struct {
	DB             *asql.SQL
	rawDB          *sql.DB
	obs            *observability.Observability
	ScheduleParser model.ScheduleParser
	Cfg            config.ScheduledConfig
	clock          clock.Clock
	gidMigrator    deployer.GlobalIDMigrator
	featureEnabled func(context.Context, string, types.GlobalID) bool
}

type WorkflowSchedule struct {
	ID                 int64
	ScheduleHash       string
	ScheduleNextHash   string
	RepositoryNodeID   types.GlobalID
	RepositoryNextID   types.GlobalID
	WorkflowIdentifier string
	WorkflowFilePath   string
	Environment        string
	Schedule           string
	ScatterOffset      float64
	NextRunAt          time.Time
	CommitSHA          types.CommitSha
	ActorNodeID        types.GlobalID
	ActorNextID        types.GlobalID
	ActorLogin         string
	CreatedAt          *time.Time
	Tier               types.RepositoryTier
	TierUpdatedAt      *time.Time
	OwnerID            *int64
}
