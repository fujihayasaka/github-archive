package engines

import (
	"context"
	"fmt"
	"sync"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/internal/monolith"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"go.opentelemetry.io/otel/trace"

	stats "github.com/github/go-stats"
)

type EngineParams struct {
	aqueductClient aqueduct.Client
	cfg            *config.Config
	db             interfaces.Database
	flagger        *vexi.Client
	statter        stats.Client
	tracer         trace.Tracer
	monolithClient *monolith.Client
}

func NewEngineParams(
	aqueductClient aqueduct.Client,
	cfg *config.Config,
	db interfaces.Database,
	flagger *vexi.Client,
	statter stats.Client,
	monolithClient *monolith.Client,
	tracer trace.Tracer,
) *EngineParams {
	return &EngineParams{
		aqueductClient: aqueductClient,
		cfg:            cfg,
		db:             db,
		flagger:        flagger,
		statter:        statter,
		monolithClient: monolithClient,
		tracer:         tracer,
	}
}

func getOrCreateAndCacheUsageTotalForPartitionKey(ctx context.Context, logger log.Logger, pk string, inputDB interfaces.Database, dbTotalsFunc DbTotalsFunc) (*models.Amounts, bool, error) {
	// ideally this cache hitlook up would be a stored procedure on the cosmos side.
	// see https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/stored-procedures-triggers-udfs
	// we get ACID guarantees and can do the cache hit check in a single transaction plus performance is better
	// the cosmos go lib doesn't support stored procedures yet, so we'll do it in go for now
	// i've reached out to the cosmos team to see if they can add support for stored procedures / might make a pr if they don't
	id := models.DocumentIdTotal

	wg := &sync.WaitGroup{}

	var total *models.TotalItem
	var mostRecentItems []*models.CosmosProperties
	var mostRecentEvents []*models.CosmosProperties

	errors := make(chan error, 2)

	wg.Add(2)

	// read total doc if it exists
	go func(errors chan<- error) {
		defer wg.Done()
		// read from 'the cache'
		logger.Debug("getting total for", kvp.String("db.cosmosdb.partition_key", pk), kvp.String("db.cosmosdb.document_id", id))
		x, err := db.NewQuerier[*models.TotalItem](inputDB).ReadItem(ctx, logger, &models.Key{PartitionKey: pk, Id: id}, nil)
		if err != nil {
			errors <- err
			return
		}
		total = x

	}(errors)

	// check latest date from partition to validate cache
	go func(errors chan<- error) {
		defer wg.Done()
		// read from 'the cache'
		query := fmt.Sprintf("SELECT c._ts, c._etag FROM c where c.partitionKey = \"%s\" and NOT IS_DEFINED(c.IsTotal) order by c._ts desc offset 0 limit 1", pk)
		x, err := db.NewQuerier[*models.CosmosProperties](inputDB).QueryItems(ctx, logger, query, pk)
		if err != nil {
			errors <- err
			return
		}
		mostRecentItems = x
	}(errors)

	// wait and collect errors
	wg.Wait()
	close(errors)
	for err := range errors {
		if err != nil {
			return nil, false, err
		}
	}

	// populate the cache if it's expired (which includes empty)
	if checkIsExpired(mostRecentItems, mostRecentEvents, total) {
		logger.Debug("hit expired total",
			kvp.String("db.cosmosdb.partition_key", pk),
			kvp.String("total", fmt.Sprintf("%v", total)),
		)

		usage, err := dbTotalsFunc(ctx, logger, pk)

		if err != nil {
			return nil, false, err
		}

		if usage != nil {
			total := &models.TotalItem{
				AmountsItem: &models.AmountsItem{
					Key:     &models.Key{Id: models.DocumentIdTotal, PartitionKey: pk},
					Amounts: usage,
				},
				IsTotal: true,
			}
			err = inputDB.UpsertWithOptions(ctx, logger, total, nil)
			if err != nil {
				return nil, false, err
			}

			logger.Debug("returning from cache miss", kvp.String("db.cosmosdb.partition_key", pk))
			return usage, false, nil
		}
	}

	// return the cache hit and true to indicate we hit the cache for external callers
	logger.Debug("returning from non expired cache hit", kvp.String("db.cosmosdb.partition_key", pk))
	return total.Amounts, true, nil
}
