// Azure Org Creation Locking
//
// For each repo in each environment we want only a single Azure organisation. To ensure only a single attempt
// will create an org, regardless of concurrent receipt of requests or which processes they hit, we lock the
// (entity_id, env) row by callID with the following scheme:
//
// 1. clear stale rows via UPDATE
// 2. attempt to insert a row with locked_by=callID, using ON DUPLICATE KEY UPDATE to take over a stale row if present
// 3. SELECT for the lock with locked_by=callID
// 4. if the row is found, attempt insert
//   - on success, store the resources
//   - on failure (after retries), clear the lock
//
// Created rows will retain the callID and lock time as of #1697.
package deployer

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"time"

	"github.com/github/go-kvp"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	errs "github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

const entityIDColumnName = "entity_id"

type CreateHandler = func(context.Context) (*azptypes.BackingResources, error)

type AzpResourcesRepository interface {
	GetOrCreate(ctx context.Context, entityID types.GlobalID, createHandler CreateHandler) (*azptypes.BackingResources, OrgCreationOutcome, error)
	TryGet(ctx context.Context, entityID types.GlobalID) (*azptypes.BackingResources, error)

	GetDataForAbuseHydro(ctx context.Context, tenantIDs []string) (*AbuseHydroDBData, error)
	ArchiveEntity(ctx context.Context, entityID types.GlobalID) (int64, error)
}

type lockState struct {
	state     lockStateFlag
	resources *azptypes.BackingResources
}
type lockStateFlag int

const (
	presentState lockStateFlag = iota
	holdingLockState
	otherHoldingLockState
	unknownLockState
)

func (ls lockStateFlag) String() string {
	switch ls {
	case presentState:
		return "present"
	case holdingLockState:
		return "holdingLock"
	case otherHoldingLockState:
		return "otherHoldingLock"
	default:
		return "unknownLock"
	}
}

type OrgCreationOutcome string

const (
	OrgCreationSuccess     OrgCreationOutcome = "success"
	OrgCreationUnknown     OrgCreationOutcome = "unknown"
	OrgCreationError       OrgCreationOutcome = "error"
	OrgCreationUnnecessary OrgCreationOutcome = "unnecessary"
	OrgCreationIgnore      OrgCreationOutcome = "ignore"
)

func NewAZPResourcesRepo(
	db *asql.SQL,
	environment launchconfig.AppEnv,
	obs *observability.Observability,
	lockPollFreq time.Duration,
	lockDuration time.Duration,
	gidMigrator GlobalIDMigrator,
	ghTwirpClient ghtwirp.Client,
) AzpResourcesRepository {
	return &azpResourcesRepository{
		db:            db,
		environment:   environment,
		obs:           obs,
		lockPollFreq:  lockPollFreq,
		lockDuration:  lockDuration,
		gidMigrator:   gidMigrator,
		ghTwirpClient: ghTwirpClient,
	}
}

type azpResourcesRepository struct {
	db            *asql.SQL
	environment   launchconfig.AppEnv
	obs           *observability.Observability
	lockPollFreq  time.Duration
	lockDuration  time.Duration
	gidMigrator   GlobalIDMigrator
	ghTwirpClient ghtwirp.Client
}

func (r *azpResourcesRepository) GetOrCreate(ctx context.Context, entityID types.GlobalID, createHandler CreateHandler) (*azptypes.BackingResources, OrgCreationOutcome, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	// these are set in the polling loop
	var err error
	var res *azptypes.BackingResources
	var lock *lockState

	callID := uuid.New().String()

	// First, check if the tenant is already setup and not locked
	lock, err = r.getState(ctx, entityID, callID)
	if err == nil && lock.state == presentState {
		r.obs.Debug(ctx, "tenant already setup")
		res = lock.resources
	} else {
		safetyMargin := 2.0
		maxPollAttempts := int(math.Ceil(float64(r.lockDuration)/float64(r.lockPollFreq)) * safetyMargin)

		// We use a UUID for the call to ensure only a single call can have the lock. This ensures mutual exclusion
		// over concurrent requests, and duplicate delivery of a single request (vs using request ID)
		pollCount := 0
		for ; pollCount < maxPollAttempts; pollCount++ {
			err = r.attemptWriteLock(ctx, entityID, callID)
			if err != nil {
				break
			}
			lock, err = r.getState(ctx, entityID, callID)
			if err != nil {
				break
			}

			if lock.state == presentState {
				res = lock.resources
				break
			} else if lock.state == holdingLockState {
				// Row is locked, we have the lock
				res, err = r.create(ctx, entityID, createHandler, callID)
				break
			}

			// Row is locked, not by us. Wait.
			time.Sleep(r.lockPollFreq)
		}
		if pollCount == maxPollAttempts {
			err = errs.New("Waited maximum number of times to poll")
		}
	}

	outcome := OrgCreationUnknown
	if err != nil {
		span.RecordError(err)
		outcome = OrgCreationError
		r.unlockOnError(ctx, entityID, callID)
	} else if res != nil {
		if lock.state == presentState {
			outcome = OrgCreationUnnecessary
		} else {
			outcome = OrgCreationSuccess
		}
	}

	span.SetAttributes(attribute.String("gh.launch.tenant_creation_outcome", string(outcome)))
	mw.TagStatsWith(ctx, reqmeta.Tags{"org_creation_outcome": string(outcome)})

	return res, outcome, err
}

func (r *azpResourcesRepository) TryGet(ctx context.Context, entityID types.GlobalID) (rs *azptypes.BackingResources, err error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	const nullLockKey = "lock state unimportant, only present rows matter"
	lock, err := r.getState(ctx, entityID, nullLockKey)
	if err != nil {
		return nil, err
	}

	if lock.state != presentState {
		r.obs.Debug(ctx, "unable to obtain lock for azp resources",
			kvp.String("deployment.environment", r.environment.String()),
			kvp.String("gh.repo.global_id", entityID.String()),
			kvp.String("gh.launch.lock.state", lock.state.String()),
		)
		return nil, NewGetAzpResourcesError(entityID)
	}

	return lock.resources, nil
}

func (r *azpResourcesRepository) ArchiveEntity(ctx context.Context, entityID types.GlobalID) (int64, error) {
	r.obs.Log(ctx, "archiving entity from azp_resources", kvp.String("gh.launch.entity.global_id", entityID.String()))

	entityNextID, entityNextIDColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, entityID.String(), entityIDColumnName)
	if err != nil {
		return 0, errors.Wrap(err, "Failed to get next entity id and column for azpResourcesRepository")
	}
	// The environment name is changed on the tenant mapping to soft-delete the entity
	// On repository restoration dotcom & launch don't have a matching record
	// and a new ServiceHost gets created in actions-dotnet
	query := fmt.Sprintf(`UPDATE azp_resources
			SET environment = CONCAT(environment, ?)
			WHERE %s = ?
			AND environment IN (?,?,?,?)`, entityNextIDColumn)
	deletedTimestamp := time.Now().Unix()
	deleteEnvPostfixTimestamp := fmt.Sprintf("-deleted-%d", deletedTimestamp)

	dbRes, err := r.db.ExecContextWith(
		ctx,
		query,
		asql.WithName("ArchiveEntity"),
		deleteEnvPostfixTimestamp,
		entityNextID.String(),
		launchconfig.ProductionAppEnv.String(),
		launchconfig.LabAppEnv.String(),
		launchconfig.DevelopmentAppEnv.String(),
		launchconfig.TestAppEnv.String(),
	)

	if err != nil {
		return 0, err
	}

	numRows, err := dbRes.RowsAffected()
	if err != nil {
		return 0, errs.Wrap(err, "error calculating rows affected")
	}
	return numRows, nil
}

func (r *azpResourcesRepository) create(ctx context.Context, entityID types.GlobalID, createHandler CreateHandler, callID string) (rs *azptypes.BackingResources, err error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	resources, err := createHandler(ctx)
	if err != nil {
		return nil, errs.Wrap(err, "failed to create AZP resources")
	}

	entityNextID, entityNextIDColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, entityID.String(), entityIDColumnName)
	if err != nil {
		return nil, errors.Wrap(err, "Failed to get next entity id and column for azpResourcesRepository")
	}

	var pipelinesScaleUnitID, artifactCacheScaleUnitID, runnerScaleUnitID types.ScaleUnitID
	if resources.PipelinesScaleUnitID != "" {
		pipelinesScaleUnitID, err = types.ParseScaleUnitID(resources.PipelinesScaleUnitID)
		if err != nil {
			return nil, errors.Wrap(err, fmt.Sprintf("Failed to parse pipelines scale unit id for value: %s", resources.PipelinesScaleUnitID))
		}
	}

	if resources.ArtifactCacheScaleUnitID != "" {
		artifactCacheScaleUnitID, err = types.ParseScaleUnitID(resources.ArtifactCacheScaleUnitID)
		if err != nil {
			return nil, errors.Wrap(err, fmt.Sprintf("Failed to parse artifact cache scale unit id for value: %s", resources.ArtifactCacheScaleUnitID))
		}
	}

	if resources.RunnerScaleUnitID != "" {
		runnerScaleUnitID, err = types.ParseScaleUnitID(resources.RunnerScaleUnitID)
		if err != nil {
			return nil, errors.Wrap(err, fmt.Sprintf("Failed to parse runner scale unit id for value: %s", resources.RunnerScaleUnitID))
		}
	}

	// update the previously locked row to store the resources
	query := fmt.Sprintf(`UPDATE
			azp_resources
		SET
			tenant_id=?,
			tenant_name=?,
			project_name=?,
			pipeline_id=?,
			client_id=?,
			private_key=?,
			pipelines_scale_unit_id=?,
			artifact_cache_scale_unit_id=?,
			runner_scale_unit_id=?
		WHERE
			locked_by=?
			AND %s=?
			AND environment=?
			AND tenant_name IS NULL -- invariant: we should not have resources for this row yet
			`, entityNextIDColumn)
	affected, err := r.db.ExecContextWith(ctx, query,
		asql.WithName("resources_create"),
		resources.TenantID,
		resources.TenantName,
		resources.ProjectName,
		resources.PipelineID,
		resources.ClientID,
		string(resources.EncryptedPrivateKey),
		pipelinesScaleUnitID,
		artifactCacheScaleUnitID,
		runnerScaleUnitID,
		callID,
		entityNextID.String(),
		r.environment.String(),
	)
	if err != nil {
		return nil, errs.Wrap(err, fmt.Sprintf("failed to write row for callID: %q", callID))
	}
	c, err := affected.RowsAffected()
	if err != nil {
		return nil, errs.Wrap(err, fmt.Sprintf("failed get rows affected for callID: %q", callID))
	} else if c == 0 {
		// if we didn't write, this is bad news: we created remote resources but can't safely store a reference to them
		return nil, errs.New(fmt.Sprintf("failed to write resources created by callID: %q", callID))
	}
	return resources, nil
}

func (r *azpResourcesRepository) attemptWriteLock(ctx context.Context, entityID types.GlobalID, lockKey string) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	entityNextID, entityNextIDColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, entityID.String(), entityIDColumnName)
	if err != nil {
		return errors.Wrap(err, "Failed to get next entity id and column for azpResourcesRepository")
	}
	_, err = mysqldb.WithDeadlockRetry(ctx, "attemptWriteLock_update", nil, func() (sql.Result, error) {
		// take lock if there's an existing stale, non-created row
		unlock := fmt.Sprintf(`UPDATE azp_resources
		SET
			locked_by = ?,
			locked_at = ?
		WHERE
			%s = ?
			AND environment = ?
			AND locked_at < ?
			AND tenant_name IS NULL -- do not affect created rows
		`, entityNextIDColumn)

		return r.db.ExecContextWith(ctx,
			unlock,
			asql.WithName("resources_attemptWriteLock_update"),
			lockKey,
			time.Now().UTC(),
			entityNextID.String(),
			r.environment.String(),
			time.Now().UTC().Add(-r.lockDuration),
		)
	})
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "error updating lock"))
	}

	// Log if legacy global ID is being updated
	if entityNextID != entityID {
		r.obs.Counter(ctx, "global_ids.replace_azp_resources_legacy_id", statter.Tags{"operation": "GetOrCreate", "column": "entity_id"}, 1)
		r.obs.Debug(ctx, "Replacing legacy global id with next value for azp_resources column",
			kvp.String("gh.launch.column", "entity_id"),
			kvp.String("gh.launch.legacy_global_id", entityID.String()),
			kvp.String("gh.launch.next_global_id", entityNextID.String()))
	}

	_, err = mysqldb.WithDeadlockRetry(ctx, "attemptWriteLock_insert", nil, func() (sql.Result, error) {
		// attempt to insert a row for cases where we're the first, ignoring duplicate key errors: we'll find out the state later in getState
		const query = `INSERT INTO azp_resources
		SET
			entity_id=?,
			entity_next_id=?,
			environment=?,
			locked_by=?,
			locked_at=?,
			created_at=?
		ON DUPLICATE KEY UPDATE
			id=id`
		return r.db.ExecContextWith(ctx,
			query,
			asql.WithName("resources_attemptWriteLock_insert"),
			entityNextID.String(),
			entityNextID.String(),
			r.environment.String(),
			lockKey,
			time.Now().UTC(),
			time.Now().UTC(),
		)
	})
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "error inserting lock"))
	}

	return nil
}

func (r *azpResourcesRepository) getState(ctx context.Context, entityID types.GlobalID, lockKey string) (*lockState, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	entityNextID, entityNextIDColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, entityID.String(), entityIDColumnName)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "Failed to get next entity id and column for azpResourcesRepository"))
	}

	query := fmt.Sprintf(`SELECT
			locked_at,
			locked_by,
			tenant_id,
			tenant_name,
			project_name,
			pipeline_id,
			client_id,
			private_key,
			created_at,
			pipelines_scale_unit_id,
			artifact_cache_scale_unit_id,
			runner_scale_unit_id
		FROM
			azp_resources
		WHERE
			%s = ?
			AND environment = ?`, entityNextIDColumn)

	var createdAt, lockedAt *time.Time
	var pipelineID sql.NullInt64
	var tenantName, tenantID, projectName, clientID, privateKey, lockedBy sql.NullString
	var pipelinesScaleUnitID, artifactCacheScaleUnitID, runnerScaleUnitID types.ScaleUnitID
	err = r.db.QueryScanWith(
		ctx,
		query,
		asql.WithName("resources_getState"),
		asql.Params(entityNextID, r.environment.String()),
		&lockedAt,
		&lockedBy,
		&tenantID,
		&tenantName,
		&projectName,
		&pipelineID,
		&clientID,
		&privateKey,
		&createdAt,
		&pipelinesScaleUnitID,
		&artifactCacheScaleUnitID,
		&runnerScaleUnitID)
	if err != nil {
		if err == sql.ErrNoRows {
			r.obs.Debug(ctx, "org not found", kvp.String("gh.repo.global_id", entityID.String()), kvp.String("deployment.environment", r.environment.String()))
			return &lockState{
				state: unknownLockState,
			}, nil
		}

		return nil, err
	}

	if tenantName.Valid {
		var pipelinesScaleUnitIDString, artifactCacheScaleUnitIDString, runnerScaleUnitIDString string
		if pipelinesScaleUnitID != types.NilScaleUnitID {
			pipelinesScaleUnitIDString = pipelinesScaleUnitID.String()
		}
		if artifactCacheScaleUnitID != types.NilScaleUnitID {
			artifactCacheScaleUnitIDString = artifactCacheScaleUnitID.String()
		}
		if runnerScaleUnitID != types.NilScaleUnitID {
			runnerScaleUnitIDString = runnerScaleUnitID.String()
		}
		r.obs.Debug(ctx, "org valid", kvp.String("gh.launch.tenant.name", tenantName.String), kvp.String("gh.launch.project.name", projectName.String))
		return &lockState{
			state: presentState,
			resources: &azptypes.BackingResources{
				CreationResult: azptypes.CreationResult{
					EntityID:                 entityID,
					TenantID:                 tenantID.String,
					TenantName:               tenantName.String,
					ProjectName:              projectName.String,
					PipelineID:               pipelineID.Int64,
					ClientID:                 clientID.String,
					PipelinesScaleUnitID:     pipelinesScaleUnitIDString,
					ArtifactCacheScaleUnitID: artifactCacheScaleUnitIDString,
					RunnerScaleUnitID:        runnerScaleUnitIDString,
				},
				CreatedAt:           createdAt,
				EncryptedPrivateKey: []byte(privateKey.String),
				Environment:         r.environment.String(),
			},
		}, nil
	}

	if lockedBy.Valid {
		state := otherHoldingLockState
		if lockedBy.String == lockKey {
			state = holdingLockState
		}
		return &lockState{
			state: state,
		}, nil
	}

	return &lockState{
		state: unknownLockState,
	}, nil
}

func (r *azpResourcesRepository) unlockOnError(ctx context.Context, entityID types.GlobalID, lockKey string) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	entityNextID, entityNextIDColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, entityID.String(), entityIDColumnName)
	if err != nil {
		r.obs.Report(ctx, errors.Wrap(err, "Failed to get next entity id and column for azpResourcesRepository"))
		entityNextID = entityID
		entityNextIDColumn = entityIDColumnName
	}

	query := fmt.Sprintf(`DELETE
		FROM
			azp_resources
		WHERE
			%s = ?
			AND environment = ?
			AND locked_by = ?
	`, entityNextIDColumn)

	_, err = r.db.ExecContextWith(
		ctx,
		query,
		asql.WithName("resources_unlockOnError"),
		entityNextID.String(),
		r.environment.String(),
		lockKey,
	)

	if err != nil {
		r.obs.Report(ctx, errs.Wrap(err, "failed to unlock on error"))
	}
}

// GetAzpResourcesError represents an error loading resources for a repository.
type GetAzpResourcesError struct {
	err error
}

func (e *GetAzpResourcesError) Context() *kvp.KVP {
	type contexter interface {
		Context() *kvp.KVP
	}

	ctxer, ok := e.err.(contexter)
	if !ok {
		return nil
	}

	return ctxer.Context()
}

func (e *GetAzpResourcesError) Error() string {
	return e.err.Error()
}

// NewGetAzpResourcesError returns a new GetAzpResourcesError
func NewGetAzpResourcesError(entityID types.GlobalID) *GetAzpResourcesError {
	err := kvperrors.With("failed to get AZP resources", kvp.Any("gh.launch.entity.global_id", entityID))
	return &GetAzpResourcesError{err}
}
