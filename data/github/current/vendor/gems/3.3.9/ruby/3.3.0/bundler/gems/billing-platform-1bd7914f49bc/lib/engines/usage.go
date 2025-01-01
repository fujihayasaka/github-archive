package engines

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/lib/bperrors"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
	"go.uber.org/ratelimit"
	"golang.org/x/sync/errgroup"
)

const (
	// The page size for org/repo groupings used in the db query to limit the number of line items returned
	PageSize             = 15
	OrgRepoCacheDuration = 5 * time.Minute
)

type UsageEngine struct {
	*EngineParams
	activeUsageItemQuerier interfaces.Querier[*models.ActiveUsageItem]
	itemQuerier            interfaces.Querier[*models.Item]
	discountItemQuerier    interfaces.Querier[*models.DiscountItem]
	topOrgRepoItemQuerier  interfaces.Querier[*models.TopOrgRepo]
}

func NewUsageEngine(params *EngineParams) *UsageEngine {
	return &UsageEngine{
		EngineParams:           params,
		activeUsageItemQuerier: db.NewQuerier[*models.ActiveUsageItem](params.db),
		itemQuerier:            db.NewQuerier[*models.Item](params.db),
		discountItemQuerier:    db.NewQuerier[*models.DiscountItem](params.db),
		topOrgRepoItemQuerier:  db.NewQuerier[*models.TopOrgRepo](params.db),
	}
}

func newUsageEngineWithQuerier(
	params *EngineParams,
	activeUsageItemQuerier interfaces.Querier[*models.ActiveUsageItem],
	itemQuerier interfaces.Querier[*models.Item],
	discountItemQuerier interfaces.Querier[*models.DiscountItem],
	topOrgRepoItemQuerier interfaces.Querier[*models.TopOrgRepo]) *UsageEngine {
	return &UsageEngine{
		EngineParams:           params,
		activeUsageItemQuerier: activeUsageItemQuerier,
		itemQuerier:            itemQuerier,
		discountItemQuerier:    discountItemQuerier,
		topOrgRepoItemQuerier:  topOrgRepoItemQuerier,
	}
}

type PartitionDetailUsageItemResults struct {
	UsagePartitionDetail *models.UsagePartitionDetail
	UsageItems           []*models.UsageItem
}

func checkIsExpired(mostRecentItems []*models.CosmosProperties, mostRecentEvents []*models.CosmosProperties, total *models.TotalItem) bool {
	if total == nil {
		return true
	}

	var mostRecent []*models.CosmosProperties

	if len(mostRecentItems) > 0 {
		mostRecent = mostRecentItems
	}

	if len(mostRecentEvents) > 0 {
		mostRecent = append(mostRecent, mostRecentEvents...)
	}

	if len(mostRecent) == 0 {
		return false
	}

	var mostRecentTs int64

	// set mostRecentTs to the max from mostRecentItems
	for _, item := range mostRecent {
		if item.Timestamp > mostRecentTs {
			mostRecentTs = item.Timestamp
		}
	}

	return total.Timestamp <= mostRecentTs
}

type TotalFunc func(ctx context.Context, upd *models.UsagePartitionDetail) (*models.Amounts, bool, error)

type DbTotalsFunc func(ctx context.Context, logger log.Logger, pk string) (*models.Amounts, error)

func newPartitionDetailUsageItemResults(upd *models.UsagePartitionDetail, usageItems []*models.UsageItem) PartitionDetailUsageItemResults {
	return PartitionDetailUsageItemResults{
		UsagePartitionDetail: upd,
		UsageItems:           usageItems,
	}
}

func (u *UsageEngine) GetLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error) {
	usage, err := u.itemQuerier.QueryItems(ctx, logger, db.QueryStringAllNontotal, upd.ToGetLineItemsPartitionKey())
	if err != nil {
		return nil, err
	}

	return usage, nil
}

// groups line items by the specified groupBy and period which is almost exactly the same
// as our front-end grouping logic for the usage chart:
// https://github.com/github/github/blob/14b84ee72feddb07f20dd2e0c28481cc9994ad65/ui/packages/billing-app/utils/group.ts
func (u *UsageEngine) GroupLineItems(lineItems []*models.Item, groupBy proto.UsageGroupBy, period proto.BillingPeriod) []*models.Item {
	groupedData := make(map[string]*models.Item)

	for _, item := range lineItems {
		usageDateForPeriod := item.UsageAt.GetFormattedDateForPeriod(period)
		groupingKey := fmt.Sprintf("%s-", usageDateForPeriod)

		if groupBy == proto.UsageGroupBy_GroupByRepository {
			groupingKey += strconv.FormatInt(item.EntityDetail.RepositoryId, 10)
		} else {
			groupingKey += strconv.FormatInt(item.EntityDetail.OrganizationId, 10)
		}

		elem, ok := groupedData[groupingKey]
		if !ok {
			groupedData[groupingKey] = item
		} else {
			elem.Quantity += item.Quantity
			elem.BilledAmount += item.BilledAmount
		}
	}

	// convert the map to a slice
	var groupedLineItems []*models.Item
	for _, lineItem := range groupedData {
		groupedLineItems = append(groupedLineItems, lineItem)
	}

	// sort the grouped usage line items by usage at
	sort.Slice(groupedLineItems, func(i, j int) bool {
		return groupedLineItems[i].UsageAt.Before(groupedLineItems[j].UsageAt.Time)
	})

	return groupedLineItems
}

func (u *UsageEngine) GetPaginatedLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, input *proto.GetPaginatedUsageRequest) ([]*models.OrgRepoItem, error) {
	paginatedLineItemsQuery := u.buildPaginatedLineItemsQuery(input)

	usage, err := db.NewQuerier[*models.OrgRepoItem](u.db).QueryItems(ctx, logger, paginatedLineItemsQuery, upd.ToGetLineItemsPartitionKey())
	if err != nil {
		return nil, fmt.Errorf("error fetching paginated usage line items: %w", err)
	}

	return usage, nil
}

func (u *UsageEngine) buildPaginatedLineItemsQuery(input *proto.GetPaginatedUsageRequest) string {
	page := input.Page
	groupBy := input.GroupBy
	isOrgAdminRequest := len(input.OrganizationIds) > 0

	if page < 1 {
		page = 1
	}

	offset := (page - 1) * PageSize

	groupByField := ""
	if groupBy == proto.UsageGroupBy_GroupByOrganization {
		groupByField = "c.EntityDetail.OrganizationId"
	} else if groupBy == proto.UsageGroupBy_GroupByRepository {
		groupByField = "c.EntityDetail.RepositoryId"
	}

	var paginatedLineItemsQuery string
	if isOrgAdminRequest {
		organizationIdString := ""
		for index, orgId := range input.OrganizationIds {
			if index == len(input.OrganizationIds)-1 {
				organizationIdString += fmt.Sprintf("%d", orgId)
			} else {
				organizationIdString += fmt.Sprintf("%d,", orgId)
			}
		}

		paginatedLineItemsQuery = fmt.Sprintf(
			`
				SELECT
					SUM(c.BilledAmount) as BilledAmount,
					%s
				FROM c
				WHERE c.EntityDetail.OrganizationId IN (%s) AND %s != ""
				GROUP BY %s
				OFFSET %d LIMIT %d
			`, groupByField, organizationIdString, groupByField, groupByField, offset, PageSize,
		)
	} else {
		paginatedLineItemsQuery = fmt.Sprintf(
			`
				SELECT
					SUM(c.BilledAmount) as BilledAmount,
					%s
				FROM c
				WHERE %s != ""
				GROUP BY %s
				OFFSET %d LIMIT %d
			`, groupByField, groupByField, groupByField, offset, PageSize,
		)
	}

	return paginatedLineItemsQuery
}

// Calculate what the "other" usage would be for the top org and repo usage by
// subtracting the top usage from the total usage for each time period.
func (u *UsageEngine) CalculateOtherUsages(allUsage []*models.Item, topUsage []*models.Item, period proto.BillingPeriod) []*models.Item {
	// other usage is the sum of all usage minus the top usage for each particular usage at time
	allUsageGroupedByDate := make(map[string]*models.Item)
	topUsageGroupedByDate := make(map[string]*models.Item)

	for _, item := range allUsage {
		usageDateForPeriod := item.UsageAt.GetFormattedDateForPeriod(period)
		groupingKey := usageDateForPeriod.String()

		elem, ok := allUsageGroupedByDate[groupingKey]
		if !ok {
			allUsageGroupedByDate[groupingKey] = item
		} else {
			elem.Quantity += item.Quantity
			elem.BilledAmount += item.BilledAmount
		}
	}

	for _, item := range topUsage {
		usageDateForPeriod := item.UsageAt.GetFormattedDateForPeriod(period)
		groupingKey := usageDateForPeriod.String()

		elem, ok := topUsageGroupedByDate[groupingKey]
		if !ok {
			topUsageGroupedByDate[groupingKey] = item
		} else {
			elem.Quantity += item.Quantity
			elem.BilledAmount += item.BilledAmount
		}
	}

	var otherUsageLineItems []*models.Item
	for _, item := range allUsageGroupedByDate {
		usageDateForPeriod := item.UsageAt.GetFormattedDateForPeriod(period)
		groupingKey := usageDateForPeriod.String()

		topItem, ok := topUsageGroupedByDate[groupingKey]
		if !ok {
			otherUsageLineItems = append(otherUsageLineItems, item)
		} else {
			item.Quantity -= topItem.Quantity
			item.BilledAmount -= topItem.BilledAmount
			otherUsageLineItems = append(otherUsageLineItems, item)
		}
	}

	// sort the other usage line items by usage at
	sort.Slice(otherUsageLineItems, func(i, j int) bool {
		return otherUsageLineItems[i].UsageAt.Before(otherUsageLineItems[j].UsageAt.Time)
	})

	return otherUsageLineItems
}

func (u *UsageEngine) GetEventItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error) {
	return u.itemQuerier.QueryItems(ctx, logger, db.QueryStringAllNontotal, upd.ToEventPartitionKeyWithYearMonth())
}

func (u *UsageEngine) GetEventItemsByQuery(ctx context.Context, logger log.Logger, query string, pk string) ([]*models.Item, error) {
	return u.itemQuerier.QueryItems(ctx, logger, query, pk)
}

func (u *UsageEngine) GetWatermarkEventRollups(ctx context.Context, logger log.Logger, customerID string, sku string) ([]*models.Item, error) {
	return u.itemQuerier.QueryItemsWithOptions(ctx, logger, db.QueryStringAllNontotal, fmt.Sprintf("%s:%s:events:rollups", customerID, sku), 3, nil)
}

func (u *UsageEngine) GetDiscountLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.DiscountItem, error) {
	// we don't have discount items for all partitions, so we return nil early  in these cases to avoid an unnecessary db query.
	if !upd.DiscountDataAvailable() {
		return nil, nil
	}
	pk := upd.ToDiscountsPartitionKey()

	return u.discountItemQuerier.QueryItems(ctx, logger, db.QueryStringAllNontotal, pk)
}

func (u *UsageEngine) GetUsageLineItemsForReport(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, orgId int64) ([]*models.Item, error) {
	pk := upd.ToGetLineItemsPartitionKey()

	options := &azcosmos.QueryOptions{
		PageSizeHint: -1,
	}

	query := db.QueryStringAllNontotal
	if orgId > 0 {
		query += fmt.Sprintf(" AND c.EntityDetail.OrganizationId = %d", orgId)
	}

	return u.itemQuerier.QueryItemsWithOptions(ctx, logger, query, pk, 0, options)
}

func (u *UsageEngine) GetDiscountLineItemsForReport(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, orgId int64) ([]*models.DiscountItem, error) {
	pk := models.GetDiscountPartitionKey(upd.ToGetLineItemsPartitionKey())

	options := &azcosmos.QueryOptions{
		PageSizeHint: -1,
	}

	query := db.QueryStringAllNontotal
	if orgId > 0 {
		query += fmt.Sprintf(" AND c.EntityDetail.OrganizationId = %d", orgId)
	}

	return u.discountItemQuerier.QueryItemsWithOptions(ctx, logger, query, pk, 0, options)
}

func (u *UsageEngine) GetWatermarkEventRollupsTotal(ctx context.Context, logger log.Logger, pk string, orgId, repoId int64) (*models.Amounts, error) {
	query := "SELECT sum(c.Quantity) as Quantity FROM c WHERE NOT IS_DEFINED(c.IsTotal)"
	if orgId > 0 {
		query += fmt.Sprintf(" AND c.EntityDetail.OrganizationId = %d", orgId)
	}

	if repoId > 0 {
		query += fmt.Sprintf(" AND c.EntityDetail.RepositoryId = %d", repoId)
	}

	logger.Info("GetWatermarkEventRollupsTotal",
		kvp.String("db.cosmosdb.query", query),
		kvp.String("db.cosmosdb.partition_key", pk),
	)

	return u.db.GetTotals(ctx, logger, query, pk)
}

func (u *UsageEngine) GetDiscountTotal(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) (*models.DiscountAmounts, bool, error) {
	pk := models.GetDiscountPartitionKey(upd.ToPartitionKey())

	amounts, hitCache, err := u.GetOrCreateAndCacheUsageTotalForPartitionKey(ctx, logger, pk, u.db.GetDiscountTotals)
	discountAmounts := &models.DiscountAmounts{
		DiscountAmount:         amounts.BilledAmount,
		Quantity:               amounts.Quantity,
		AppliedCostPerQuantity: amounts.AppliedCostPerQuantity,
	}

	return discountAmounts, hitCache, err
}

func (u *UsageEngine) GetUsageTotal(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, includeQuantity bool) (*models.Amounts, bool, error) {
	if includeQuantity {
		return u.GetOrCreateAndCacheUsageTotalForPartitionKey(ctx, logger, upd.ToPartitionKey(), u.db.GetUsageTotalsWithQuantity)
	} else {
		return u.GetOrCreateAndCacheUsageTotalForPartitionKey(ctx, logger, upd.ToPartitionKey(), u.db.GetUsageTotals)
	}
}

func (u *UsageEngine) GetRepoUsage(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error) {
	pk := models.GetRepoPartitionKey(upd.ToPartitionKey())
	return u.itemQuerier.QueryItems(ctx, logger, db.QueryStringAllNontotal, pk)
}

func (u *UsageEngine) GetOrCreateAndCacheUsageTotalForPartitionKey(ctx context.Context, logger log.Logger, pk string, dbTotalsFunc DbTotalsFunc) (*models.Amounts, bool, error) {
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
		x, err := db.NewQuerier[*models.TotalItem](u.db).ReadItem(ctx, logger, &models.Key{PartitionKey: pk, Id: id}, nil)
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
		x, err := db.NewQuerier[*models.CosmosProperties](u.db).QueryItems(ctx, logger, query, pk)
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
			err = u.db.UpsertWithOptions(ctx, logger, total, nil)
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

func (u *UsageEngine) MakeCostCenterIdNameMap(costCenters []*models.CostCenter) map[string]string {
	costCenterIdNameMap := make(map[string]string)
	for _, costCenter := range costCenters {
		costCenterIdNameMap[costCenter.Id] = costCenter.Name
	}
	return costCenterIdNameMap
}

func (u *UsageEngine) GetProtoNetUsageLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, costCenters []*models.CostCenter) ([]*proto.NetUsageItem, error) {
	var items []*models.Item
	discountItems := make([]*models.DiscountItem, 0)
	items, err := u.GetLineItems(ctx, logger, upd)
	if err != nil {
		logger.WithError(err).Error("error getting line items")
		return nil, err
	}

	// we don't currently have discount items for all partitions
	discountDataAvailable := upd.DiscountDataAvailable()

	if discountDataAvailable {
		partitionDiscountItems, err := u.GetDiscountLineItems(ctx, logger, upd)
		if err != nil {
			logger.WithError(err).Error("error getting discount line items")
			return nil, err
		}

		discountItems = append(discountItems, partitionDiscountItems...)
	}
	discountItemsMap := u.buildDiscountItemMap(discountItems)

	costCenterMap := u.MakeCostCenterIdNameMap(costCenters)

	protoNetUsageItems := make([]*proto.NetUsageItem, len(items))
	for i, item := range items {
		protoNetUsageItems[i] = item.ToNetUsageItemProto(discountItemsMap[item.Id], discountDataAvailable)

		// Add cost center name to usage entity id
		if costCenterName, ok := costCenterMap[protoNetUsageItems[i].UsageEntityId]; ok {
			protoNetUsageItems[i].Name = costCenterName
		} else {
			protoNetUsageItems[i].Name = "Enterprise Only"
		}

	}

	return protoNetUsageItems, nil
}

func (u *UsageEngine) GetNetUsageLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) (PartitionDetailUsageItemResults, error) {
	var items []*models.Item
	discountItems := make([]*models.DiscountItem, 0)
	items, err := u.GetLineItems(ctx, logger, upd)
	if err != nil {
		logger.WithError(err).Error("error getting line items")
		return newPartitionDetailUsageItemResults(upd, nil), err
	}

	// we don't currently have discount items for all partitions
	discountDataAvailable := upd.DiscountDataAvailable()

	if discountDataAvailable {
		partitionDiscountItems, err := u.GetDiscountLineItems(ctx, logger, upd)
		if err != nil {
			logger.WithError(err).Error("error getting discount line items")
			return newPartitionDetailUsageItemResults(upd, nil), err
		}

		discountItems = append(discountItems, partitionDiscountItems...)
	}
	discountItemsMap := u.buildDiscountItemMap(discountItems)

	protoNetUsageItems := make([]*models.UsageItem, len(items))
	for i, item := range items {
		protoNetUsageItems[i] = item.ToUsageItem(discountItemsMap[item.Id], discountDataAvailable)
	}

	return newPartitionDetailUsageItemResults(upd, protoNetUsageItems), nil
}

func (u *UsageEngine) ScheduleWatermarkJobs(ctx context.Context, logger log.Logger, jobRun *models.WatermarkJobRun) error {
	// Custom logger to namespace all subsequent log messages and to include the job run details
	logger = logger.Named("ScheduleWatermarkJobs").WithFields(kvp.Any("job_run", jobRun))
	logger.Info("ScheduleWatermarkJobs Start")
	start := time.Now()

	activeCustomerQuery := db.QueryStringAllOnlyKey
	if jobRun.CustomerId != "" {
		activeCustomerQuery += fmt.Sprintf(" WHERE c.id = \"%s\"", jobRun.CustomerId)
	}

	// Perform an async query to retrieve all active event customers
	partitionKey := fmt.Sprintf(models.PartitionKeyActiveEvent, jobRun.Sku)
	keysCh, errCh := db.NewQuerier[*models.Key](u.db).QueryItemsAsyncBatch(ctx, logger, activeCustomerQuery, partitionKey)
	g, gctx := errgroup.WithContext(ctx)
	success := true
	partitionDetail := models.GetPartitionDetailForDailyWatermarkRollup(jobRun)
	rateLimiter := ratelimit.New(13) // customer keys per second

	// Receive and process batches of active customer keys until we've processed all of them
	for keys := range keysCh {
		_ = rateLimiter.Take()

		batch := keys
		g.Go(func() error {
			u.statter.Counter("watermark_dispatcher.queried_active_customers", stats.Tags{}, int64(len(batch)))
			if err := u.createWatermarkJobs(gctx, logger, batch, partitionDetail, jobRun); err != nil {
				success = false
			}
			// Always return nil so that the errgroup doesn't stop processing due to one bad batch
			return nil
		})
	}

	// Check for query errors; errCh is closed at this point so receiving from it will not block
	if err := <-errCh; err != nil {
		logger.WithError(err).Error("QueryItemsAsyncBatch failed")
		success = false
	}

	// Wait for all processing goroutines to finish
	if err := g.Wait(); err != nil {
		logger.WithError(err).Error("error while processing a batch of keys")
		success = false
	}

	// Logging and metrics
	duration := time.Since(start)
	logger.WithFields(kvp.Bool("success", success), kvp.Duration("duration", duration)).Info("ScheduleWatermarkJobs Finished")
	u.statter.Timing("usage_engine.schedule_watermark_jobs", stats.Tags{"success": strconv.FormatBool(success)}, duration)

	return nil
}

// createWatermarkJobs takes a list of active customer keys and publishes a batch of watermark jobs to Aqueduct
func (u *UsageEngine) createWatermarkJobs(ctx context.Context, logger log.Logger, keys []*models.Key, partitionDetail *models.UsagePartitionDetail, jobRun *models.WatermarkJobRun) error {
	app := u.cfg.AqueductApplication()
	queue := messaging.GetQueueName(models.WorkerTypeWatermarkHandler, u.cfg.OverrideQueuePrefix)
	keyCount := len(keys)
	logger = logger.WithFields(
		kvp.String("aqueduct.job.app", app),
		kvp.String("aqueduct.job.queue", queue),
		kvp.Int("messaging.batch.message_count", keyCount),
	)

	logger.Info("createWatermarkJobs start")
	start := time.Now()

	// Convert the keys into batch items for Aqueduct
	batch := make([]aqueduct.BatchItem, 0, keyCount)
	var payloadSize int64

	for _, key := range keys {
		// Convert each active customer key into a watermark job
		watermarkJob := models.WatermarkJob{
			ActiveCustomer:  key,
			PartitionDetail: partitionDetail,
			JobRun:          jobRun,
		}

		// Serialize the watermark job into a JSON payload
		payload, err := json.Marshal(watermarkJob)
		if err != nil {
			logger.WithError(err).Error("error serializing watermark job", kvp.Any("watermarkJob", watermarkJob))
			continue
		}

		// Add the payload to the batch and track the total payload size
		payloadSize += int64(len(payload))
		batch = append(batch, aqueduct.BatchItem{
			Job: aqueduct.Job{
				App:     app,
				Queue:   queue,
				Payload: payload,
			},
			Opts: messaging.MessageSenderOptions(),
		})
	}

	// Send the batch
	batchSize := len(batch)
	_, err := u.aqueductClient.SendBatch(ctx, batch)
	if err != nil {
		logger.WithError(err).Error("error dispatching watermark jobs")
	} else {
		u.statter.Counter("watermark_dispatcher.send_event_to_handler", stats.Tags{"product-sku": jobRun.Sku}, int64(batchSize))
	}

	// Logging and metrics
	duration := time.Since(start)
	logger.Info("createWatermarkJobs finished",
		kvp.Bool("success", err == nil),
		kvp.Duration("duration", duration),
		kvp.Int64("messaging.batch.message_count", int64(batchSize)),
		kvp.Int64("messaging.message.payload_size_bytes", payloadSize),
	)
	u.statter.Timing("usage_engine.create_watermark_jobs", stats.Tags{"product-sku": jobRun.Sku, "success": strconv.FormatBool(err == nil)}, duration)

	// Return an error if the number of dispatched jobs does not match the number of keys provided
	if batchSize != keyCount {
		return errors.New("some watermark jobs failed to dispatch")
	}

	return nil
}

func (u *UsageEngine) SendScheduleZeroOutQuantitiesJob(ctx context.Context, logger log.Logger, payload json.RawMessage) error {
	app := u.cfg.AqueductApplication()
	queue := messaging.GetQueueName(models.WorkerTypeZeroOutQuantities, u.cfg.OverrideQueuePrefix)
	logger = logger.WithFields(
		kvp.String("aqueduct.job.app", app),
		kvp.String("aqueduct.job.queue", queue),
	)

	job := aqueduct.Job{
		App:     app,
		Queue:   queue,
		Payload: payload,
	}

	_, err := u.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)

	if err != nil {
		logger.WithError(err).Error("error dispatching zero out quantities jobs")
	}

	return nil
}

func (u *UsageEngine) ScheduleHighWatermarkRolloverJobs(ctx context.Context, logger log.Logger, jobRun *models.HighWatermarkRolloverJobRun) error {
	logger = logger.Named("ScheduleHighWatermarkRolloverJobs").WithFields(kvp.Any("job_run", jobRun))
	logger.Info("ScheduleHighWatermarkRolloverJobs Start")
	start := time.Now()

	activeCustomerQuery := db.QueryStringAllOnlyKey
	if jobRun.CustomerId != "" {
		activeCustomerQuery += fmt.Sprintf(" WHERE c.id = \"%s\"", jobRun.CustomerId)
	}
	customerPartitionKey := fmt.Sprintf(models.PartitionKeyActiveEvent, jobRun.Sku)
	success := u.scheduleHwRolloverByPartition(ctx, logger, jobRun, activeCustomerQuery, customerPartitionKey)

	// Logging and metrics
	duration := time.Since(start)
	logger.WithFields(kvp.Bool("success", success), kvp.Duration("duration", duration)).Info("ScheduleHighWatermarkRolloverJobs Finished")
	u.statter.Timing("usage_engine.schedule_high_watermark_rollover_jobs", stats.Tags{"success": strconv.FormatBool(success)}, duration)
	return nil
}

func (u *UsageEngine) scheduleHwRolloverByPartition(ctx context.Context, logger log.Logger, jobRun *models.HighWatermarkRolloverJobRun, customerQuery string, pk string) bool {
	g, gctx := errgroup.WithContext(ctx)

	keysCh, errCh := db.NewQuerier[*models.Key](u.db).QueryItemsAsyncBatch(gctx, logger, customerQuery, pk)
	success := true
	// Receive and process batches of active customer keys until we've processed all of them
	for keys := range keysCh {
		batch := keys
		g.Go(func() error {
			u.statter.Counter("high_watermark.queried_active_hwb_customers", stats.Tags{}, int64(len(batch)))
			if err := u.createHighWatermarkRolloverJobs(gctx, logger, batch, jobRun); err != nil {
				success = false
			}
			// Always return nil so that the errgroup doesn't stop processing due to one bad batch
			return nil
		})
	}
	// Check for query errors; errCh is closed at this point so receiving from it will not block
	if err := <-errCh; err != nil {
		logger.WithError(err).Error("QueryItemsAsyncBatch failed")
		success = false
	}

	// Wait for all processing goroutines to finish
	if err := g.Wait(); err != nil {
		logger.WithError(err).Error("error while processing a batch of keys")
		success = false
	}

	return success
}

// createHighWatermarkRolloverJobs takes a list of active customer keys and publishes a batch of high watermark jobs to Aqueduct
func (u *UsageEngine) createHighWatermarkRolloverJobs(ctx context.Context, logger log.Logger, keys []*models.Key, jobRun *models.HighWatermarkRolloverJobRun) error {
	app := u.cfg.AqueductApplication()
	queue := messaging.GetQueueName(models.WorkerTypeHighWatermarkRolloverHandler, u.cfg.OverrideQueuePrefix)
	keyCount := len(keys)
	logger = logger.WithFields(
		kvp.String("aqueduct.job.app", app),
		kvp.String("aqueduct.job.queue", queue),
		kvp.Int("messaging.batch.message_count", keyCount),
	)

	logger.Info("createHighWatermarkRolloverJobs start")
	start := time.Now()
	// Convert the keys into batch items for Aqueduct
	batch := make([]aqueduct.BatchItem, 0, keyCount)
	var payloadSize int64
	for _, key := range keys {
		// Convert each active customer key into a high watermark rollover job
		customerJobRun := jobRun.WithCustomerId(key.Id)
		highWatermarkRolloverJob := models.HighWatermarkRolloverJob{
			ActiveCustomer: key,
			JobRun:         customerJobRun,
		}

		// Serialize the high watermark rollover job into a JSON payload
		payload, err := json.Marshal(highWatermarkRolloverJob)

		if err != nil {
			logger.WithError(err).Error("error serializing high watermark rollover job", kvp.Any("highWatermarkRolloverJob", highWatermarkRolloverJob))
			continue
		}

		// Add the payload to the batch and track the total payload size
		payloadSize += int64(len(payload))
		batch = append(batch, aqueduct.BatchItem{
			Job: aqueduct.Job{
				App:     app,
				Queue:   queue,
				Payload: payload,
			},
			Opts: messaging.MessageSenderOptions(),
		})
	}

	// Send the batch
	batchSize := len(batch)
	_, err := u.aqueductClient.SendBatch(ctx, batch)
	if err != nil {
		logger.WithError(err).Error("error dispatching high watermark rollover jobs")
	} else {
		u.statter.Counter("high_watermark_rollover.send_event_to_handler", stats.Tags{"product-sku": jobRun.Sku}, int64(batchSize))
	}

	// Logging and metrics
	duration := time.Since(start)
	logger.Info("highWatermarkRolloverJobs finished",
		kvp.Bool("success", err == nil),
		kvp.Duration("duration", duration),
		kvp.Int64("messaging.batch.message_count", int64(batchSize)),
		kvp.Int64("messaging.message.payload_size_bytes", payloadSize),
	)
	u.statter.Timing("usage_engine.create_high_watermark_rollover_jobs", stats.Tags{"product-sku": jobRun.Sku, "success": strconv.FormatBool(err == nil)}, duration)

	// Return an error if the number of dispatched jobs does not match the number of keys provided
	if batchSize != keyCount {
		return errors.New("some high watermark rollover jobs failed to dispatch")
	}
	return nil
}

func (u *UsageEngine) GetLineItemsFromPartitionKey(ctx context.Context, logger log.Logger, partitionKey string) ([]*models.Item, error) {
	usage, err := u.itemQuerier.QueryItems(ctx, logger, db.QueryStringAllNontotal, partitionKey)
	if err != nil {
		return nil, err
	}

	return usage, nil
}

func (u *UsageEngine) GetDiscountLineItemsFromPartitionKey(ctx context.Context, logger log.Logger, partitionKey string) ([]*models.DiscountItem, error) {
	discountItems, err := u.discountItemQuerier.QueryItems(ctx, logger, db.QueryStringAllNontotal, partitionKey)
	if err != nil {
		return nil, err
	}

	return discountItems, nil
}

func (u *UsageEngine) GetActiveUsageItem(ctx context.Context, logger log.Logger, item *models.ActiveUsageItem) (*models.ActiveUsageItem, error) {
	queriedItem, err := db.NewQuerier[*models.ActiveUsageItem](u.db).ReadItemWithRetries(ctx, logger, item.Key)
	return queriedItem, err
}

// Save the Usage Item key under the active usage item partition key (e.g. activeUsageItems:2020:12:22)
func (u *UsageEngine) UpsertActiveUsageItem(ctx context.Context, logger log.Logger, actUsageItem *models.ActiveUsageItem) (*models.ActiveUsageItem, error) {
	err := u.db.UpsertWithOptions(ctx, logger, actUsageItem, nil)
	if err != nil {
		return nil, err
	}

	return actUsageItem, err
}

func (u *UsageEngine) WriteActiveUsageItems(ctx context.Context, logger log.Logger, item *models.Item, customer *models.Customer) error {
	actUsageItemPartition, err := models.NewActiveUsageItem(item, customer)
	if err != nil {
		logger.WithError(err).Error("failed to get new active usage item")
		return bperrors.NewError(bperrors.Internal, err)
	}

	// check if the active usage item already exists to minimize RUs on this "hot partition"
	// as upserts have a high number of RUs where read/get is a max of 1
	actUsageItem, err := u.GetActiveUsageItem(ctx, logger, actUsageItemPartition)
	if err != nil {
		logger.WithError(err).Error("failed to load active usage item")
		return bperrors.NewError(bperrors.Internal, err)

	}
	if actUsageItem != nil && actUsageItem.Target == actUsageItemPartition.Target {
		return nil
	}

	// Update the active usage item target or create a new one if it doesn't exist
	// to track daily usage
	_, err = u.UpsertActiveUsageItem(ctx, logger, actUsageItemPartition)
	if err != nil {
		return bperrors.NewError(bperrors.Internal, err)
	}
	return nil
}

func (u *UsageEngine) ScheduleZuoraEmission(ctx context.Context, logger log.Logger, emissionTarget *models.EmissionTarget) error {
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		u.statter.Timing("emission_dispatcher_job", stats.Tags{}, duration)
	}()

	partitionDetail, err := models.GetPartitionDetailForDailyZuoraEmission(emissionTarget)
	if err != nil {
		logger.WithError(err).Error("error creating usage partition detail")
		return err
	}

	logger.Info("created partition detail for zuora emission usages", kvp.Any("partitionDetail", partitionDetail))

	// assume all usage that comes from this partition can be emitted to Zuora
	usageItems, err := u.GetZuoraUsageItems(ctx, logger, partitionDetail)
	if err != nil {
		logger.WithError(err).Error("error getting line items for partition", kvp.Any("partitionDetail", partitionDetail))
		return err
	}

	// Group the usage items by customer ID.
	itemsGroupedByCustomerID := u.groupItemsByCustomerID(usageItems)

	// Create and send a job for each customer’s usages group to the emission handler
	for customerID, customerItems := range itemsGroupedByCustomerID {
		payload, err := json.Marshal(customerItems)
		if err != nil {
			logger.WithError(err).Error("error serializing customer usage items", kvp.Any("customerItems", customerItems))
			continue
		}

		job := aqueduct.Job{
			App:     u.cfg.AqueductApplication(),
			Queue:   messaging.GetQueueName(models.WorkerTypeEmissionHandler, u.cfg.OverrideQueuePrefix),
			Payload: payload,
		}
		_, err = u.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)

		// Logging and metrics
		l := logger.WithFields(
			kvp.String("aqueduct.job.app", job.App),
			kvp.String("aqueduct.job.queue", job.Queue),
			kvp.String("aqueduct.job.payload", string(job.Payload)),
		)
		if err != nil {
			l.WithError(err).Error("error submitting emission dispatcher job")
			continue
		}

		l.Info("submitted emission job for customer usages items", kvp.String("customer_Id", customerID))
		u.statter.Counter("published_emission_dispatcher_job", stats.Tags{}, int64(1))
	}

	logger.Info("emission dispatcher job finished")

	return nil
}

func (u *UsageEngine) GetActiveUsageItems(ctx context.Context, logger log.Logger, usageDate *models.UsageDate) ([]*models.ActiveUsageItem, error) {
	usageTime := models.GetUsageTimeFromUsageDate(usageDate)
	usageItems, err := u.activeUsageItemQuerier.QueryItems(ctx, logger, db.QueryStringAll, models.NewActiveUsageItemPartitionKey(usageTime))
	if err != nil {
		return nil, errors.Wrap(err, "error querying active usage items by date")
	}

	return usageItems, nil
}

// Use Cosmos as a caching mechanism for the top org and repo usage queries
func (u *UsageEngine) GetTopOrgRepoFromCache(ctx context.Context, logger log.Logger, input *models.UsageRequest) ([]int64, error) {
	// Skip the cache for organization admin requests until we gather
	// metrics on usage patterns and best path to caching such requests
	if len(input.FilteredOrgs) > 0 {
		logger.Info("skipping top org repo cache for organization admin request",
			kvp.Int64s("gh.billing_platform.org_ids", input.FilteredOrgs),
			kvp.Int64(logging.BillingCustomerId, input.CustomerId),
			kvp.String(logging.BillingPlatformCostCenterUUID, input.CostCenterId),
		)
		return nil, nil
	}

	key := models.NewTopOrgRepoCacheKey(input)

	queriedDoc, err := u.topOrgRepoItemQuerier.ReadItem(ctx, logger, key, nil)
	if err != nil {
		return nil, err
	} else if queriedDoc == nil {
		logger.Info("No data in cached document", kvp.Any("cacheKey", key), kvp.Any("UsageRequest", input))
		return nil, nil
	}

	requestedUsageTime := models.NewUsageTime().WithYear(input.Year).WithMonthInt(input.Month).WithDay(int(input.Day)).WithHour(int(input.Hour))
	now := models.NewUsageTimeFromTime(time.Now().UTC())

	// queries for last years usage can always be read from Cosmos since the data is now static
	if input.BillingPeriod == proto.BillingPeriod_Yearly && requestedUsageTime.Year() < now.Year() {
		return queriedDoc.ResourceIDs, nil
	}

	// queries for last months usage can always be read from Cosmos since the data is now static
	if input.BillingPeriod == proto.BillingPeriod_Monthly && requestedUsageTime.Month() < now.Month() {
		return queriedDoc.ResourceIDs, nil
	}

	// For current month, don't return the queried data if the document is expired
	documentTime := time.Unix(queriedDoc.Timestamp, 0)
	if time.Since(documentTime) > OrgRepoCacheDuration {
		return nil, nil
	}

	return queriedDoc.ResourceIDs, nil
}

func (u *UsageEngine) UpsertTopOrgRepoResponse(ctx context.Context, logger log.Logger, input *models.UsageRequest, resourceIDs []int64) error {
	topOrgRepo := &models.TopOrgRepo{
		Key:         models.NewTopOrgRepoCacheKey(input),
		ResourceIDs: resourceIDs,
	}

	return u.db.UpsertWithOptions(ctx, logger, topOrgRepo, nil)
}

func (u *UsageEngine) buildDiscountItemMap(discountItems []*models.DiscountItem) map[string]*models.DiscountItem {
	discountItemsMap := make(map[string]*models.DiscountItem)
	for _, discountItem := range discountItems {
		commonId := strings.Replace(discountItem.Id, ":discount", "", 1) // handles non-hourly partitions
		discountItemsMap[commonId] = discountItem
	}
	return discountItemsMap
}

func (u *UsageEngine) GetZuoraUsageItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error) {
	// This partition key looks at yesterday's date
	usageTimePK := upd.UsageTime.ToPartitionKey(upd.ActiveType)
	usageItems, err := u.itemQuerier.QueryItems(ctx, logger, db.QueryStringAllNontotal, fmt.Sprintf("%s:%s", usageTimePK, "byZuoraEmission"))
	if err != nil {
		return nil, errors.Wrap(err, "error querying usage items by zuora emission")
	}

	return usageItems, nil
}

func (u *UsageEngine) groupItemsByCustomerID(usages []*models.Item) map[string][]*models.Item {
	usagesByCustomerID := make(map[string][]*models.Item)

	// Group usages by customer ID
	for _, usage := range usages {
		customerID := usage.GetCustomerId()
		if customerID == "" {
			continue
		}
		usagesByCustomerID[customerID] = append(usagesByCustomerID[customerID], usage)
	}

	return usagesByCustomerID
}
