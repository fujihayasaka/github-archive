package db

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/Azure/azure-sdk-for-go/sdk/tracing/azotel"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/utils"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/trace"

	stats "github.com/github/go-stats"
)

const (
	QueryStringAllOnlyKey                = "SELECT c.id, c.partitionKey FROM c"
	QueryStringAllNontotal               = "SELECT * FROM c where NOT IS_DEFINED(c.IsTotal)"
	QueryStringAll                       = "SELECT * FROM c"
	QueryStringAllNotProcessed           = "SELECT * FROM c where c.IsProcessed = false"
	QueryStringAllCostCenterIdEqualsUUID = "SELECT * FROM c where c.id = c.UUID"
)

type Database struct {
	connection        interfaces.CosmosConnection
	gatewayConnection *Connection
	statter           stats.Client
	tracer            trace.Tracer
}

// ItemConflictError represents a 409 conflict from Cosmos and is used
// to provide error data to consumers
var ItemConflictError = errors.New("item already exists")

func NewReadOnlyDatabaseForCI(cfg *config.Config, logger log.Logger, statter stats.Client, tracer trace.Tracer) (interfaces.Database, error) {
	connection, err := newConnection(cfg.ReadOnlyDatabaseKey, cfg.ReadOnlyDatabaseEndPoint, cfg.DatabaseName, cfg.ContainerName)
	if err != nil {
		return nil, errors.Wrap(err, "failed to initialize the connection")
	}

	return &Database{
		connection: connection,
		statter:    statter,
		tracer:     tracer,
	}, nil
}

func NewReadOnlyDatabase(cfg *config.Config, logger log.Logger, statter stats.Client, tracer trace.Tracer) (interfaces.Database, error) {
	cc, _ := azidentity.NewClientSecretCredential(cfg.DBReadOnlySPNTenantID, cfg.DBReadOnlySPNClientID, cfg.DBReadOnlySPNClientSecret, nil)

	options := &azcosmos.ClientOptions{ClientOptions: azcore.ClientOptions{
		TracingProvider: azotel.NewTracingProvider(otel.GetTracerProvider(), nil),
	}}
	client, err := azcosmos.NewClient(cfg.DatabaseEndPoint, cc, options)
	if err != nil {
		return nil, errors.Wrap(err, "failed to initialize Cosmos client")
	}

	database, err := client.NewDatabase(cfg.DatabaseName)
	if err != nil {
		return nil, errors.Wrap(err, "failed to initialize Cosmos database")
	}

	container, err := database.NewContainer(cfg.ContainerName)
	if err != nil {
		return nil, errors.Wrap(err, "failed to initialize Cosmos container")
	}

	connection := &Connection{
		ContainerClient: container,
		Client:          client,
		DatabaseClient:  database,
	}

	return &Database{
		connection: connection,
		statter:    statter,
		tracer:     tracer,
	}, nil
}

func NewDatabase(cfg *config.Config, logger log.Logger, statter stats.Client, tracer trace.Tracer) interfaces.Database {
	connection, gatewayConnection, err := NewDBConnections(cfg)

	if err != nil {
		logger.WithError(err).Error("Failed to create database connection")
		return nil
	}

	if cfg.DatabaseEndPoint == cfg.GatewayDatabaseEndPoint {
		if cfg.DisableCache {
			logger.Info("Cosmos cache disabled, using direct connection for all Cosmos queries.")
		} else {
			logger.Info("Using direct connection for all Cosmos queries due to a Gateway Connection string issue.")
			if cfg.DBGatewayConnectionString == "" {
				logger.Info("DBGatewayConnectionString is empty, using DBConnectionString for Cosmoso connection.")
			}
		}
	}

	if cfg.EnsureCollection {
		sm := NewSchemaManagement(cfg, connection)
		if err := sm.EnsureCollectionExists(context.Background(), cfg.ContainerName); err != nil {
			logger.WithError(err).Error("Failed to create collection", kvp.String("db.cosmosdb.container", cfg.ContainerName))
		}
	}

	return &Database{
		connection:        connection,
		gatewayConnection: gatewayConnection,
		statter:           statter,
		tracer:            tracer,
	}
}

func (db *Database) GetConnection() interfaces.CosmosConnection {
	return db.connection
}

func (db *Database) GetGatewayConnection() interfaces.CosmosConnection {
	return db.gatewayConnection
}

func (db *Database) GetTracer() trace.Tracer {
	return db.tracer
}

func (db *Database) GetStatter() stats.Client {
	return db.statter
}

func (db *Database) SetStatterTags(tags stats.Tags) {
	statter := db.statter.WithTags(tags)
	db.statter = statter
}

func (db *Database) Batch(
	ctx context.Context,
	item models.ItemKey,
	opts *interfaces.QueryOptions,
	doBatchItems func(*azcosmos.TransactionalBatch) error) (bool, []azcosmos.TransactionalBatchResult, error) {

	ctx, sp := db.tracer.Start(ctx, "Database.Batch")
	defer sp.End()

	k := item.GetKey()
	partitionKey := azcosmos.NewPartitionKeyString(k.PartitionKey)

	batch := db.connection.NewTransactionalBatch(partitionKey)

	err := doBatchItems(&batch)
	if err != nil {
		return false, nil, err
	}

	response, err := db.connection.ExecuteTransactionalBatch(ctx, batch, nil)
	if err != nil {
		return false, nil, errors.Wrap(err, "failed to execute batch")
	}

	if response.Success {
		return true, nil, nil
	}

	return false, response.OperationResults, nil
}

func (db *Database) GetTotals(ctx context.Context, logger log.Logger, query, pk string) (*models.Amounts, error) {
	ctx, sp := db.tracer.Start(ctx, "Database.GetTotals")
	defer sp.End()

	querier := NewQuerier[*models.Amounts](db)
	totals, err := querier.QueryItems(ctx, logger, query, pk)

	if err != nil {
		return nil, err
	}

	if len(totals) != 1 {
		return nil, errors.Errorf("Expected 1 total, got %d", len(totals))
	}

	return totals[0], nil
}

func (db *Database) GetUsageTotals(ctx context.Context, logger log.Logger, pk string) (*models.Amounts, error) {
	ctx, sp := db.tracer.Start(ctx, "Database.GetUsageTotals")
	defer sp.End()

	query := "SELECT sum(c.BilledAmount) as BilledAmount FROM c where NOT IS_DEFINED(c.IsTotal)"
	return db.GetTotals(ctx, logger, query, pk)
}

func (db *Database) GetUsageTotalsWithQuantity(ctx context.Context, logger log.Logger, pk string) (*models.Amounts, error) {
	ctx, sp := db.tracer.Start(ctx, "Database.GetUsageTotals")
	defer sp.End()

	query := "SELECT sum(c.Quantity) as Quantity, sum(c.BilledAmount) as BilledAmount FROM c where NOT IS_DEFINED(c.IsTotal)"
	return db.GetTotals(ctx, logger, query, pk)
}

func (db *Database) GetDiscountTotals(ctx context.Context, logger log.Logger, pk string) (*models.Amounts, error) {
	ctx, sp := db.tracer.Start(ctx, "Database.GetDiscountTotals")
	defer sp.End()

	query := "SELECT sum(c.Quantity) as Quantity, sum(c.DiscountAmount) as BilledAmount, max(c.AppliedCostPerQuantity) as AppliedCostPerQuantity FROM c where NOT IS_DEFINED(c.IsTotal)"
	return db.GetTotals(ctx, logger, query, pk)
}

func (db *Database) Exists(ctx context.Context, logger log.Logger, key models.ItemKey, opts *interfaces.QueryOptions) (bool, error) {
	ctx, sp := db.tracer.Start(ctx, "Database.Exists")
	defer sp.End()

	item, err := NewQuerier[*models.Amounts](db).ReadItem(ctx, logger, key, opts)

	return item != nil, err
}

func (db *Database) DeleteAsync(ctx context.Context, logger log.Logger, key models.ItemKey, wg *sync.WaitGroup, errors chan<- error) {
	ctx, sp := db.tracer.Start(ctx, "Database.DeleteAsync")
	defer func() {
		wg.Done()
		sp.End()
	}()

	err := db.DeleteWithOptions(ctx, logger, key, nil)
	if err != nil {
		errors <- fmt.Errorf("error deleting %v: %w", key, err)
	}
}
func (db *Database) DeleteWithOptions(ctx context.Context, logger log.Logger, key models.ItemKey, options *interfaces.QueryOptions) error {
	ctx, sp := db.tracer.Start(ctx, "Database.DeleteWithOptions")
	defer sp.End()

	k := key.GetKey()
	partitionKey := azcosmos.NewPartitionKeyString(k.PartitionKey)

	logger = logger.WithFields(k.GetLoggerFields()...)

	_, retryCount := parseOptions(options)

	var returnError error
	for i := 0; i <= retryCount; i++ {
		if ctx.Err() != nil {
			return errors.Wrap(ctx.Err(), "context error")
		}

		start := time.Now()
		itemResponse, err := db.connection.DeleteItem(ctx, partitionKey, k.Id, nil)
		elapsed := time.Since(start)
		logger = logger.WithFields(GetItemResponseLoggerFields(itemResponse, elapsed, err)...)

		captureCosmosDBMetrics(ctx, db.statter, "delete_with_options", k, itemResponse.RequestCharge, elapsed, err)

		// only log fist error in retry loop to reduce error noise
		if err != nil && i == 0 {
			logger.WithError(err).Error("DeleteWithOptions failed")
		}

		if err == nil {
			logger.Info("DeleteWithOptions success")
			return nil
		}

		// Don't retry on 404 errors as well, as it's a not found it won't resolve itself
		if Is404NotFound(err) {
			return err
		}

		db.statter.Counter(
			"db.retry",
			stats.Tags{
				"type":               "delete_with_options",
				"retry_count":        strconv.Itoa(i + 1),
				"status_code":        strconv.Itoa(GetErrorStatusCode(err)),
				"partition_template": k.GetPartitionTemplate(),
			},
			int64(1),
		)

		returnError = err
		utils.WaitForThrottling(i+1, false)
	}

	logger.WithError(returnError).Error("DeleteWithOptions failed, retries exhausted")
	db.statter.Counter(
		"db.retries_exhausted",
		stats.Tags{
			"type":        "delete_with_options",
			"status_code": strconv.Itoa(GetErrorStatusCode(returnError)),
		},
		int64(1),
	)

	return returnError
}

func (db *Database) UpsertAsync(ctx context.Context, logger log.Logger, item models.ItemKey, wg *sync.WaitGroup, opts *interfaces.QueryOptions, errors chan<- error) {
	ctx, sp := db.tracer.Start(ctx, "Database.UpsertAsync")
	defer func() {
		wg.Done()
		sp.End()
	}()

	err := db.UpsertWithOptions(ctx, logger, item, opts)
	if err != nil {
		errors <- fmt.Errorf("error upserting %v: %w", item, err)
	}
}

func (db *Database) UpsertWithOptions(ctx context.Context, logger log.Logger, item models.ItemKey, options *interfaces.QueryOptions) error {
	ctx, sp := db.tracer.Start(ctx, "Database.UpsertWithOptions")
	defer sp.End()

	key := item.GetKey()
	partitionKey := azcosmos.NewPartitionKeyString(key.PartitionKey)

	logger = logger.WithFields(key.GetLoggerFields()...)

	b, err := json.Marshal(item)
	if err != nil {
		return errors.Wrap(err, "failed to marshal item")
	}

	o, retryCount := parseOptions(options)

	var returnError error
	for i := 0; i <= retryCount; i++ {
		if ctx.Err() != nil {
			return errors.Wrap(ctx.Err(), "context error")
		}

		start := time.Now()
		itemResponse, err := db.connection.UpsertItem(ctx, partitionKey, b, o)
		elapsed := time.Since(start)
		logger = logger.WithFields(GetItemResponseLoggerFields(itemResponse, elapsed, err)...)

		captureCosmosDBMetrics(ctx, db.statter, "upsert_with_options", key, itemResponse.RequestCharge, elapsed, err)

		// only log fist error in retry loop to reduce error noise
		if err != nil && i == 0 {
			logger.WithError(err).Error("UpsertWithOptions failed")
		}

		if err == nil {
			logger.Info("UpsertWithOptions success")
			return nil
		}

		// don't retry on precondition errors, this can happen when passing the
		// IfMatchEtag option and the item has been updated since the etag was
		// last retrieved
		if Is412PreconditionError(err) {
			db.statter.Counter(
				"db.precondition_error",
				stats.Tags{
					"type": "upsert_with_options",
				},
				int64(1),
			)
			return err
		}

		db.statter.Counter(
			"db.retry",
			stats.Tags{
				"type":               "upsert_with_options",
				"retry_count":        strconv.Itoa(i + 1),
				"status_code":        strconv.Itoa(GetErrorStatusCode(err)),
				"partition_template": key.GetPartitionTemplate(),
			},
			int64(1),
		)

		returnError = err
		utils.WaitForThrottling(i+1, true)
	}

	logger.WithError(returnError).Error("UpsertWithOptions failed, retries exhausted")
	db.statter.Counter(
		"db.retries_exhausted",
		stats.Tags{
			"type":        "upsert_with_options",
			"status_code": strconv.Itoa(GetErrorStatusCode(returnError)),
		},
		int64(1),
	)

	return returnError
}

func (db *Database) CreateAsync(ctx context.Context, logger log.Logger, item models.ItemKey, wg *sync.WaitGroup, opts *interfaces.QueryOptions, errors chan<- error) {
	ctx, sp := db.tracer.Start(ctx, "Database.CreateAsync")
	defer func() {
		wg.Done()
		sp.End()
	}()

	err := db.CreateWithOptions(ctx, logger, item, opts)
	if err != nil {
		errors <- fmt.Errorf("error creating %v: %w", item, err)
	}
}

func (db *Database) CreateIfNotExists(ctx context.Context, logger log.Logger, item models.ItemKey) (bool, error) {
	ctx, sp := db.tracer.Start(ctx, "Database.CreateIfNotExists")
	defer sp.End()

	err := db.CreateWithOptions(ctx, logger, item, nil)
	if err != nil {
		if Is409Conflict(err) {
			return false, nil
		}
		return false, err
	}

	return true, nil
}

func (db *Database) CreateIfNotExistAsync(ctx context.Context, logger log.Logger, item models.ItemKey, wg *sync.WaitGroup, opts *interfaces.QueryOptions, errors chan<- error) {
	ctx, sp := db.tracer.Start(ctx, "Database.CreateIfNotExistAsync")
	defer func() {
		wg.Done()
		sp.End()
	}()

	exists, err := db.Exists(ctx, logger, item, opts)
	if err != nil {
		errors <- err
	} else if !exists {
		err := db.CreateWithOptions(ctx, logger, item, opts)
		if err != nil {
			errors <- err
		}
	}
}

func (db *Database) CreateWithOptions(ctx context.Context, logger log.Logger, item models.ItemKey, options *interfaces.QueryOptions) error {
	ctx, sp := db.tracer.Start(ctx, "Database.CreateWithOptions")
	defer sp.End()

	key := item.GetKey()
	partitionKey := azcosmos.NewPartitionKeyString(key.PartitionKey)

	logger = logger.WithFields(key.GetLoggerFields()...)

	b, err := json.Marshal(item)
	if err != nil {
		return errors.Wrap(err, "failed to marshal item")
	}

	o, retryCount := parseOptions(options)

	var returnError error
	for i := 0; i <= retryCount; i++ {
		if ctx.Err() != nil {
			return errors.Wrap(ctx.Err(), "context error")
		}

		start := time.Now()
		itemResponse, err := db.connection.CreateItem(ctx, partitionKey, b, o)
		elapsed := time.Since(start)
		logger = logger.WithFields(GetItemResponseLoggerFields(itemResponse, elapsed, err)...)

		captureCosmosDBMetrics(ctx, db.statter, "create_with_options", key, itemResponse.RequestCharge, elapsed, err)

		// only log fist error in retry loop to reduce error noise
		if err != nil && i == 0 {
			logger.WithError(err).Error("CreateWithOptions failed")
		}

		if !ShouldRaiseError(err, options) {
			logger.Info("CreateWithOptions success")
			return nil
		}

		// Don't retry on 409 errors as well, as it's a conflict it won't resolve itself
		if Is409Conflict(err) {
			return err
		}

		// Don't retry on 403 errors as well, as it's a forbidden it won't resolve itself
		// As of now we know this can happen when a partition hits the 20GB limit
		if Is403Forbidden(err) {
			return err
		}

		db.statter.Counter(
			"db.retry",
			stats.Tags{
				"type":               "create_with_options",
				"retry_count":        strconv.Itoa(i + 1),
				"status_code":        strconv.Itoa(GetErrorStatusCode(err)),
				"partition_template": key.GetPartitionTemplate(),
			},
			int64(1),
		)

		returnError = err
		utils.WaitForThrottling(i+1, true)
	}

	// Adding the partition key mostly to debug "Partition key reached maximum
	// size of 20 GB" errors. They return 403 status code on creates.
	// More context: https://github.com/github/gitcoin/issues/13664
	logger.WithError(returnError).Error("CreateWithOptions failed, retries exhausted")
	db.statter.Counter(
		"db.retries_exhausted",
		stats.Tags{
			"type":          "create_with_options",
			"status_code":   strconv.Itoa(GetErrorStatusCode(returnError)),
			"partition_key": key.PartitionKey,
		},
		int64(1),
	)

	return returnError
}

type PatchOps = azcosmos.PatchOperations

func (db *Database) PatchWithOptions(ctx context.Context, logger log.Logger, item models.ItemKey, patchOps PatchOps, options *interfaces.QueryOptions) error {
	ctx, sp := db.tracer.Start(ctx, "Database.PatchWithOptions")
	defer sp.End()

	key := item.GetKey()
	partitionKey := azcosmos.NewPartitionKeyString(key.PartitionKey)
	logger = logger.WithFields(key.GetLoggerFields()...)
	ops := azcosmos.PatchOperations(patchOps)

	o, retryCount := parseOptions(options)

	var returnError error
	for i := 0; i <= retryCount; i++ {
		if ctx.Err() != nil {
			return errors.Wrap(ctx.Err(), "context error")
		}

		start := time.Now()
		itemResponse, err := db.connection.PatchItem(ctx, partitionKey, key.Id, ops, o)
		elapsed := time.Since(start)
		logger = logger.WithFields(GetItemResponseLoggerFields(itemResponse, elapsed, err)...)

		captureCosmosDBMetrics(ctx, db.statter, "patch_with_options", key, itemResponse.RequestCharge, elapsed, err)

		// only log fist error in retry loop to reduce error noise
		if err != nil && i == 0 {
			logger.WithError(err).Error("PatchWithOptions failed")
		}

		if !ShouldRaiseError(err, options) {
			logger.Info("PatchWithOptions success")
			return nil
		}

		if Is404NotFound(err) {
			return errors.Wrap(err, "PatchWithOptions not found")
		}

		// Don't retry on 409 errors as well, as it's a conflict it won't resolve itself
		if Is409Conflict(err) {
			return errors.Wrap(err, "PatchWithOptions conflict")
		}

		db.statter.Counter(
			"db.retry",
			stats.Tags{
				"type":               "patch_with_options",
				"retry_count":        strconv.Itoa(i + 1),
				"status_code":        strconv.Itoa(GetErrorStatusCode(err)),
				"partition_template": key.GetPartitionTemplate(),
			},
			int64(1),
		)

		returnError = err
		utils.WaitForThrottling(i+1, true)
	}

	logger.WithError(returnError).Error("PatchWithOptions failed, retries exhausted")
	db.statter.Counter(
		"db.retries_exhausted",
		stats.Tags{
			"type":        "patch_with_options",
			"status_code": strconv.Itoa(GetErrorStatusCode(returnError)),
		},
		int64(1),
	)

	return returnError
}

func parseOptions(opts *interfaces.QueryOptions) (*azcosmos.ItemOptions, int) {
	var o *azcosmos.ItemOptions
	retryCount := 4 // default retry count
	if opts != nil {
		o = &azcosmos.ItemOptions{}
		o.PostTriggers = []string{}
		if opts.IncludeTotalStoredProcedure {
			o.PostTriggers = append(o.PostTriggers, "totals")
		}
		if opts.IncludeBudgetStoredProcedure {
			o.PostTriggers = append(o.PostTriggers, "budget")
		}
		if opts.IfMatchEtag != nil {
			o.IfMatchEtag = opts.IfMatchEtag
		}
		if opts.ConsistencyLevel != nil {
			o.ConsistencyLevel = opts.ConsistencyLevel
		}

		retryCount = opts.RetryCount
	}

	return o, retryCount
}

func ShouldRaiseError(err error, options *interfaces.QueryOptions) bool {
	return err != nil && !(options != nil && Is409Conflict(err) && options.IgnoreExistingDocumentError)
}

func captureCosmosDBMetrics(ctx context.Context, statter stats.Client, operation string, key *models.Key, requestCharge float32, elapsed time.Duration, err error) {
	statusCode := 200
	if err != nil {
		statusCode = GetErrorStatusCode(err)
	}

	config.IncrementApiLevelRequestUsage(ctx, requestCharge)

	statter = statter.WithTags(stats.Tags{
		"operation":          operation,
		"success":            strconv.FormatBool(err == nil),
		"status_code":        strconv.Itoa(statusCode),
		"partition_template": key.GetPartitionTemplate(),
		"partition_product":  key.GetProductFromPartitionKey(),
		"partition_sku":      key.GetProductSkuFromPartitionKey(),
	})

	statter.Counter("db.cosmosdb.request_count", stats.Tags{}, int64(1))
	statter.Timing("db.cosmosdb.request_duration", stats.Tags{}, elapsed)
	statter.Distribution("db.cosmosdb.request_charge", stats.Tags{}, float64(requestCharge))
}
