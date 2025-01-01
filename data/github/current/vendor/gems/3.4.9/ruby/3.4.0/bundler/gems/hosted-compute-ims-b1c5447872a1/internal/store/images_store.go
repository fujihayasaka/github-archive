package store

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/github/go-stats"
	dbstats "github.com/github/go-stats/db"
	"github.com/github/hosted-compute-ims/gen/ent"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store/mysql"
)

//go:generate mockgen -source=$GOFILE -destination=../../gen/mocks/mocks_store/mock_images_store.go -package mocks_store
type IImagesStore interface {
	// image definition store
	GetImageDefinitionById(ctx context.Context, id uint64) (*models.ImageDefinition, error)
	ListCuratedImageDefinitions(ctx context.Context) ([]*models.ImageDefinition, error)
	ListCustomerImageDefinitions(ctx context.Context, ownerId string) ([]*models.ImageDefinition, error)
	GetImageDefinitionsCountByOwnerId(ctx context.Context, ownerId string) (int, error)

	AddImageDefinition(ctx context.Context, image *models.ImageDefinition) (uint64, error)
	UpdateImageDefinition(ctx context.Context, id uint64, updateDefinition *models.ImageDefinitionUpdate) (uint64, error)
	DeleteImageDefinition(ctx context.Context, id uint64) error

	// image version store
	GetImageVersionById(ctx context.Context, id uint64) (*models.ImageVersion, error)
	GetImageVersionByDefinitionIdAndVersion(ctx context.Context, imageDefinitionId uint64, version string) (*models.ImageVersion, error)
	ListImageVersionsByDefinitionId(ctx context.Context, imageDefinitionId uint64) ([]*models.ImageVersion, error)
	GetImageVersionsStorageMetadataForDefinitionIds(ctx context.Context, imageDefinitionIds []uint64) (map[uint64]*models.ImageVersionsStorageMetadata, error)

	GetLatestImageVersion(ctx context.Context, imageDefinitionId uint64) (*models.ImageVersion, error)
	GetLatestImageVersions(ctx context.Context, imageDefinitionIds []uint64) (map[uint64]*models.ImageVersion, error)

	AddImageVersion(ctx context.Context, version *models.ImageVersion) (uint64, error)
	UpdateImageVersion(ctx context.Context, id uint64, updateVersion *models.ImageVersionUpdate) (uint64, error)
	DeleteImageVersionById(ctx context.Context, id uint64) error

	// image replication store
	UpdateImageReplication(ctx context.Context, imageReplicationData *models.ImageVersionReplicationData) error
	GetImageReplicationsByImageIdAndVersion(ctx context.Context, imageDefinitionId uint64, version string) (*models.ImageVersionReplicationData, error)

	// internal only functions
	UpdateImageVersionState(ctx context.Context, id uint64, state models.ImageVersionState, stateDetails string) error
	UpdateImageVersionStateDetailsForState(ctx context.Context, id uint64, state models.ImageVersionState, stateDetails string) error
	UpdateImageVersionSize(ctx context.Context, id uint64, sizeGB int32) error

	AssignAzureSubscriptionToImageDefinition(ctx context.Context, imageDefinitionId uint64, maxImageDefinitionsPerSubscription int, queryLimit int) (uint64, error)
	UnassignAzureSubscriptionFromImageDefinition(ctx context.Context, imageDefinitionId uint64) error
	GetAzureSubscriptionById(ctx context.Context, id uint64) (*models.AzureSubscription, error)

	// TODO marketplace image store
}

type ImagesStore struct {
	dbRw           *sql.DB
	writeEntClient *ent.Client
	readEntClient  *ent.Client
	logger         log.Logger
	statter        stats.Client
}

func NewImagesStore(dbRw *sql.DB, writeEntClient *ent.Client, readEntClient *ent.Client, logger log.Logger, statter stats.Client) *ImagesStore {
	return &ImagesStore{
		dbRw:           dbRw,
		writeEntClient: writeEntClient,
		readEntClient:  readEntClient,
		logger:         logger,
		statter:        statter,
	}
}

func NewImagesStoreWithMySQLConnection(cfg *mysql.Config, logger log.Logger, statter stats.Client) (*ImagesStore, error) {
	dbURL, err := cfg.DatabaseWriteURL()
	if err != nil {
		return nil, fmt.Errorf("failed to construct db write url %s, error occurred: %w", dbURL, err)
	}

	rwSqlConnection, err := mysql.NewConnection(cfg, dbURL)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize raw rw database connection with mysql config: %w", err)
	}

	writeEntClient, err := mysql.NewWriteEntClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize read-write ent client using mysql config: %w", err)
	}

	readEntClient, err := mysql.NewReadEntClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize read-only ent client using mysql config: %w", err)
	}

	imageStore := NewImagesStore(rwSqlConnection, writeEntClient, readEntClient, logger, statter)

	// run the dbstats in the background
	imageStore.runStatsReporter(context.Background(), rwSqlConnection, cfg)

	return imageStore, nil
}

func (istore *ImagesStore) runStatsReporter(ctx context.Context, cxn *sql.DB, cfg *mysql.Config) {
	// run the dbstats in the background
	stats := &dbstats.Reporter{
		Stats:    istore.statter,
		Interval: cfg.DBStatsInterval,
		DB:       cxn,
	}
	go stats.Run(ctx) //nolint:errcheck
}
