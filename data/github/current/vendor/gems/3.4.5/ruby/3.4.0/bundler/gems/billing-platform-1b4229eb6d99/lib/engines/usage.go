package engines

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/internal/featureflags"
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

//go:generate pegomock generate -o ../../testing/fakes/mock_usage_engine.go --self_package=fakes --package=fakes UsageEngineInterface
type UsageEngineInterface interface {
	GetLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error)
	GetUsageLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.UsageItem, error)
	GetAllLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error)
	GetLineItemsForOrgAdmin(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error)
	GroupLineItems(lineItems []*models.UsageItem, groupBy proto.UsageGroupBy, period proto.BillingPeriod) []*models.UsageItem
	GetPaginatedLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, input *proto.GetPaginatedUsageRequest) ([]*models.OrgRepoItem, error)
	CalculateOtherUsages(allUsage []*models.UsageItem, topUsage []*models.UsageItem, period proto.BillingPeriod) []*models.UsageItem
	GetEventItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error)
	GetEventItemsByQuery(ctx context.Context, logger log.Logger, query string, pk string) ([]*models.Item, error)
	GetWatermarkEventRollups(ctx context.Context, logger log.Logger, customerID string, sku string) ([]*models.Item, error)
	GetWatermarkEventTotals(ctx context.Context, logger log.Logger, customerID string, sku string) ([]*models.WatermarkTotalItem, error)
	GetDiscountLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.DiscountItem, error)
	GetDiscountLineItemsForOrgAdmin(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.DiscountItem, error)
	GetLateDiscountLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.DiscountItem, error)
	GetUsageLineItemsForReport(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, orgId int64) ([]*models.Item, error)
	GetAllDiscountLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.DiscountItem, error)
	GetDiscountLineItemsForReport(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, orgId int64) ([]*models.DiscountItem, error)
	GetWatermarkEventRollupsTotal(ctx context.Context, logger log.Logger, customerId, sku string, orgId, repoId int64) (int64, error)
	GetUsageTotal(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, includeQuantity bool) (*models.Amounts, bool, error)
	GetEnterpriseUsageTotalItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, input *proto.GetEnterpriseUsageTotalsRequest) ([]*models.Item, error)
	GetUsageTotalItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, usageEntityId string, year int64, month int64) ([]*models.Item, error)
	GetRepoUsage(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error)
	MakeCostCenterIdNameMap(costCenters []*models.CostCenter) map[string]string
	GetProtoNetUsageLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, costCenters []*models.CostCenter, customerId string) ([]*proto.NetUsageItem, error)
	GetNetUsageLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) (models.PartitionDetailUsageItemResults, error)
	ScheduleWatermarkJobs(ctx context.Context, logger log.Logger, jobRun *models.WatermarkJobRun) error
	SendScheduleZeroOutQuantitiesJob(ctx context.Context, logger log.Logger, payload json.RawMessage) error
	ScheduleHighWatermarkRolloverJobs(ctx context.Context, logger log.Logger, jobRun *models.HighWatermarkRolloverJobRun) error
	GetLineItemsFromPartitionKey(ctx context.Context, logger log.Logger, partitionKey string) ([]*models.Item, error)
	GetDiscountLineItemsFromPartitionKey(ctx context.Context, logger log.Logger, partitionKey string) ([]*models.DiscountItem, error)
	GetActiveUsageItem(ctx context.Context, logger log.Logger, item *models.ActiveUsageItem) (*models.ActiveUsageItem, error)
	UpsertActiveUsageItem(ctx context.Context, logger log.Logger, actUsageItem *models.ActiveUsageItem) (*models.ActiveUsageItem, error)
	WriteActiveUsageItems(ctx context.Context, logger log.Logger, item *models.Item, customer *models.Customer) error
	ScheduleZuoraEmission(ctx context.Context, logger log.Logger, emissionTarget *models.EmissionTarget, skipCache bool) error
	GetActiveUsageItems(ctx context.Context, logger log.Logger, usageDate *models.UsageDate) ([]*models.ActiveUsageItem, error)
	GetTopOrgRepoFromCache(ctx context.Context, logger log.Logger, input *models.UsageRequest) ([]int64, error)
	UpsertTopOrgRepoResponse(ctx context.Context, logger log.Logger, input *models.UsageRequest, resourceIDs []int64) error
	GetZuoraEmissionDailyRollupUsageItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error)
}

type UsageEngine struct {
	*EngineParams
	activeUsageItemQuerier    interfaces.Querier[*models.ActiveUsageItem]
	itemQuerier               interfaces.Querier[*models.Item]
	discountItemQuerier       interfaces.Querier[*models.DiscountItem]
	topOrgRepoItemQuerier     interfaces.Querier[*models.TopOrgRepo]
	watermarkTotalItemQuerier interfaces.Querier[*models.WatermarkTotalItem]
	pricingEngine             PricingEngineInterface
}

func NewUsageEngine(params *EngineParams) UsageEngineInterface {
	return &UsageEngine{
		EngineParams:              params,
		activeUsageItemQuerier:    db.NewQuerier[*models.ActiveUsageItem](params.db),
		itemQuerier:               db.NewQuerier[*models.Item](params.db),
		discountItemQuerier:       db.NewQuerier[*models.DiscountItem](params.db),
		topOrgRepoItemQuerier:     db.NewQuerier[*models.TopOrgRepo](params.db),
		watermarkTotalItemQuerier: db.NewQuerier[*models.WatermarkTotalItem](params.db),
		pricingEngine:             NewPricingEngine(params),
	}
}

func newUsageEngineWithQuerier(
	params *EngineParams,
	activeUsageItemQuerier interfaces.Querier[*models.ActiveUsageItem],
	itemQuerier interfaces.Querier[*models.Item],
	discountItemQuerier interfaces.Querier[*models.DiscountItem],
	topOrgRepoItemQuerier interfaces.Querier[*models.TopOrgRepo],
	watermarkTotalItemQuerier interfaces.Querier[*models.WatermarkTotalItem],
	pricingEngine PricingEngineInterface) *UsageEngine {
	return &UsageEngine{
		EngineParams:              params,
		activeUsageItemQuerier:    activeUsageItemQuerier,
		itemQuerier:               itemQuerier,
		discountItemQuerier:       discountItemQuerier,
		topOrgRepoItemQuerier:     topOrgRepoItemQuerier,
		watermarkTotalItemQuerier: watermarkTotalItemQuerier,
		pricingEngine:             pricingEngine,
	}
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

func newPartitionDetailUsageItemResults(upd *models.UsagePartitionDetail, usageItems []*models.UsageItem) models.PartitionDetailUsageItemResults {
	return models.PartitionDetailUsageItemResults{
		UsagePartitionDetail: upd,
		UsageItems:           usageItems,
	}
}

func (u *UsageEngine) GetLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error) {
	partitionKey := upd.ToGetLineItemsPartitionKey()
	if strings.Contains(partitionKey, "byOrgAndRepo") {
		logger.Info(
			"Unexpected byOrgAndRepo partition query",
			kvp.String(logging.BillingCustomerId, upd.UsageEntityId),
			kvp.String(logging.BillingPlatformProduct, upd.Product),
			kvp.String(logging.BillingPlatformSku, upd.Sku),
			kvp.Int64(logging.RepositoryId, upd.RepoId),
			kvp.Int64(logging.OrganizationId, upd.OrgId),
			kvp.String(logging.BillingPlatformGroupBy, upd.GroupBy),
			kvp.Bool(logging.BillingOrgAdminRequest, upd.IsOrgAdmin),
		)
	}

	usage, err := u.itemQuerier.QueryItems(ctx, logger, db.QueryStringAllNontotal, partitionKey)
	if err != nil {
		return nil, err
	}

	return usage, nil
}

func (u *UsageEngine) GetUsageLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.UsageItem, error) {
	lineItems, err := u.GetLineItems(ctx, logger, upd)
	if err != nil {
		return nil, err
	}

	usageLineItems := make([]*models.UsageItem, 0, len(lineItems))
	for _, lineItem := range lineItems {
		usageLineItems = append(usageLineItems, lineItem.ToUsageItem(nil))
	}

	return usageLineItems, nil
}

func (u *UsageEngine) GetAllLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error) {
	items := make([]*models.Item, 0)

	if upd.IsOrgAdmin {
		retrievedItems, err := u.GetLineItemsForOrgAdmin(ctx, logger, upd)
		if err != nil {
			logger.WithError(err).Error("error getting all line items for org admin")
			return items, err
		}
		items = append(items, retrievedItems...)
	} else {
		retrievedItems, err := u.GetLineItems(ctx, logger, upd)
		if err != nil {
			logger.WithError(err).Error("error getting all line items")
			return items, err
		}
		items = append(items, retrievedItems...)
	}
	return items, nil
}

func (u *UsageEngine) buildOrgAdminSearchQuery(upd *models.UsagePartitionDetail) string {
	query := db.QueryStringAllNontotal

	if upd.Product != "" {
		// This is a product search
		query += fmt.Sprintf(" AND c.Pricing.Product = '%s'", upd.Product)
	}

	if upd.Sku != "" {
		// This is a sku search
		query += fmt.Sprintf(" AND c.Pricing.Sku = '%s'", upd.Sku)
	}

	return query
}

func (u *UsageEngine) GetLineItemsForOrgAdmin(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error) {
	pk := upd.ToGetLineItemsPartitionKey()
	query := u.buildOrgAdminSearchQuery(upd)

	return u.itemQuerier.QueryItems(ctx, logger, query, pk)
}

// groups line items by the specified groupBy and period which is almost exactly the same
// as our front-end grouping logic for the usage chart:
// https://github.com/github/github/blob/14b84ee72feddb07f20dd2e0c28481cc9994ad65/ui/packages/billing-app/utils/group.ts
func (u *UsageEngine) GroupLineItems(lineItems []*models.UsageItem, groupBy proto.UsageGroupBy, period proto.BillingPeriod) []*models.UsageItem {
	groupedData := make(map[string]*models.UsageItem)

	for _, item := range lineItems {
		usageTime := models.NewUsageTimeFromUnixMilli(item.UsageAt)
		usageDateForPeriod := usageTime.GetFormattedDateForPeriod(period)
		groupingKey := fmt.Sprintf("%s-", usageDateForPeriod)

		if groupBy == proto.UsageGroupBy_GroupByRepository {
			groupingKey += strconv.FormatInt(item.RepoId, 10)
		} else {
			groupingKey += strconv.FormatInt(item.OrgId, 10)
		}

		elem, ok := groupedData[groupingKey]
		if !ok {
			groupedData[groupingKey] = item
		} else {
			elem.IncrementAmounts(item)
		}
	}

	// convert the map to a slice
	var groupedLineItems []*models.UsageItem
	for _, lineItem := range groupedData {
		groupedLineItems = append(groupedLineItems, lineItem)
	}

	// sort the grouped usage line items by usage at
	sort.Slice(groupedLineItems, func(i, j int) bool {
		return groupedLineItems[i].UsageAt < groupedLineItems[j].UsageAt
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
func (u *UsageEngine) CalculateOtherUsages(allUsage []*models.UsageItem, topUsage []*models.UsageItem, period proto.BillingPeriod) []*models.UsageItem {
	// other usage is the sum of all usage minus the top usage for each particular usage at time
	allUsageGroupedByDate := make(map[string]*models.UsageItem)
	topUsageGroupedByDate := make(map[string]*models.UsageItem)

	for _, item := range allUsage {
		usageTime := models.NewUsageTimeFromUnixMilli(item.UsageAt)
		usageDateForPeriod := usageTime.GetFormattedDateForPeriod(period)
		groupingKey := usageDateForPeriod.String()

		elem, ok := allUsageGroupedByDate[groupingKey]
		if !ok {
			allUsageGroupedByDate[groupingKey] = item
		} else {
			elem.IncrementAmounts(item)
		}
	}

	for _, item := range topUsage {
		usageTime := models.NewUsageTimeFromUnixMilli(item.UsageAt)
		usageDateForPeriod := usageTime.GetFormattedDateForPeriod(period)
		groupingKey := usageDateForPeriod.String()

		elem, ok := topUsageGroupedByDate[groupingKey]
		if !ok {
			topUsageGroupedByDate[groupingKey] = item
		} else {
			elem.IncrementAmounts(item)
		}
	}

	var otherUsageLineItems []*models.UsageItem
	for _, item := range allUsageGroupedByDate {
		usageTime := models.NewUsageTimeFromUnixMilli(item.UsageAt)
		usageDateForPeriod := usageTime.GetFormattedDateForPeriod(period)
		groupingKey := usageDateForPeriod.String()

		topItem, ok := topUsageGroupedByDate[groupingKey]
		if !ok {
			otherUsageLineItems = append(otherUsageLineItems, item)
		} else {
			item.DecrementAmounts(topItem)
			otherUsageLineItems = append(otherUsageLineItems, item)
		}
	}

	// sort the other usage line items by usage at
	sort.Slice(otherUsageLineItems, func(i, j int) bool {
		return otherUsageLineItems[i].UsageAt < otherUsageLineItems[j].UsageAt
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

func (u *UsageEngine) GetWatermarkEventTotals(ctx context.Context, logger log.Logger, customerID string, sku string) ([]*models.WatermarkTotalItem, error) {
	return u.watermarkTotalItemQuerier.QueryItemsWithOptions(ctx, logger, db.QueryStringTotal, fmt.Sprintf("%s:%s:events:rollups", customerID, sku), 3, nil)
}

func (u *UsageEngine) GetDiscountLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.DiscountItem, error) {
	pk := upd.ToDiscountsPartitionKey()

	return u.discountItemQuerier.QueryItems(ctx, logger, db.QueryStringAllNontotal, pk)
}

func (u *UsageEngine) GetDiscountLineItemsForOrgAdmin(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.DiscountItem, error) {
	// use the same PK as the org admin line items query (e.g. customerID:org:orgId:usageTime:byProductSku) with the discount suffix
	pk := models.GetDiscountPartitionKey(upd.ToGetLineItemsPartitionKey())
	query := u.buildOrgAdminSearchQuery(upd)

	return u.discountItemQuerier.QueryItems(ctx, logger, query, pk)
}

func (u *UsageEngine) GetLateDiscountLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.DiscountItem, error) {

	pk := upd.ToLateDiscountPartitionKey()

	return u.discountItemQuerier.QueryItems(ctx, logger, db.QueryStringAll, pk)
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

func (u *UsageEngine) GetAllDiscountLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.DiscountItem, error) {
	discountItems := make([]*models.DiscountItem, 0)

	if upd.IsOrgAdmin {
		partitionDiscountItems, err := u.GetDiscountLineItemsForOrgAdmin(ctx, logger, upd)
		if err != nil {
			logger.WithError(err).Error("error getting discount line items for org admin")
			return nil, err
		}

		discountItems = append(discountItems, partitionDiscountItems...)
	} else {
		partitionDiscountItems, err := u.GetDiscountLineItems(ctx, logger, upd)
		if err != nil {
			logger.WithError(err).Error("error getting discount line items for product org repo sku")
			return nil, err
		}

		discountItems = append(discountItems, partitionDiscountItems...)
	}

	return discountItems, nil
}

func (u *UsageEngine) GetDiscountLineItemsForReport(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, orgId int64) ([]*models.DiscountItem, error) {
	pk := models.GetDiscountPartitionKey(upd.ToGetLineItemsPartitionKey())

	options := &azcosmos.QueryOptions{
		PageSizeHint: -1,
	}

	query := db.QueryStringAllNontotal
	if orgId > 0 {
		query += fmt.Sprintf(" AND c.id LIKE '%%org:%d:%%'", orgId)
	}

	return u.discountItemQuerier.QueryItemsWithOptions(ctx, logger, query, pk, 0, options)
}

func (u *UsageEngine) GetWatermarkEventRollupsTotal(ctx context.Context, logger log.Logger, customerId, sku string, orgId, repoId int64) (int64, error) {
	lastHour := time.Now().UTC().Add(time.Duration(-1) * time.Hour)
	usageTime := models.NewUsageTimeFromTime(lastHour).ToPartitionKey(models.Hourly)

	costCentersPartitionKey := fmt.Sprintf("customer:%s:costCenters", customerId)
	costCenterQuerier := db.NewQuerier[*models.CostCenter](u.db)
	costCenters, err := costCenterQuerier.QueryItems(ctx, logger, db.QueryStringAllCostCenterIdEqualsUUID, costCentersPartitionKey)
	if err != nil {
		return 0, err
	}

	g, gctx := errgroup.WithContext(ctx)
	var sumForAllCostCenters atomic.Int64

	g.Go(func() error {
		partitionKey := fmt.Sprintf("%s:%s:byOrgRepoProductSku", customerId, usageTime)
		id := fmt.Sprintf("%s:%s:%d:%d:%s", customerId, sku, orgId, repoId, usageTime)

		key := &models.Key{
			Id:           id,
			PartitionKey: partitionKey,
		}

		logger.Info("GetWatermarkEventRollupsTotal for customer",
			kvp.String("db.cosmosdb.id", key.Id),
			kvp.String("db.cosmosdb.partition_key", key.PartitionKey),
		)
		item, err := db.NewQuerier[*models.Item](u.db).ReadItem(gctx, logger, key, nil)
		if err != nil {
			return err
		}

		if item != nil {
			sumForAllCostCenters.Add(item.Quantity)
		}
		return nil
	})

	for _, costCenter := range costCenters {
		g.Go(func() error {
			partitionKey := fmt.Sprintf("%s:%s:byOrgRepoProductSku", costCenter.UUID, usageTime)
			id := fmt.Sprintf("%s:%s:%d:%d:%s", customerId, sku, orgId, repoId, usageTime)

			key := &models.Key{
				Id:           id,
				PartitionKey: partitionKey,
			}

			logger.Info("GetWatermarkEventRollupsTotal for cost center",
				kvp.String("db.cosmosdb.id", key.Id),
				kvp.String("db.cosmosdb.partition_key", key.PartitionKey),
			)

			item, err := db.NewQuerier[*models.Item](u.db).ReadItem(gctx, logger, key, nil)
			if err != nil {
				return err
			}
			if item != nil {
				sumForAllCostCenters.Add(item.Quantity)
			}
			return nil
		})
	}

	retErr := g.Wait()
	if retErr != nil {
		return 0, errors.Wrap(retErr, "failed to get watermark event rollups total for some of the entities")
	}

	return sumForAllCostCenters.Load(), nil
}

func (u *UsageEngine) GetUsageTotal(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, includeQuantity bool) (*models.Amounts, bool, error) {
	if includeQuantity {
		return getOrCreateAndCacheUsageTotalForPartitionKey(ctx, logger, upd.ToPartitionKey(), u.db, u.db.GetUsageTotalsWithQuantity)
	} else {
		return getOrCreateAndCacheUsageTotalForPartitionKey(ctx, logger, upd.ToPartitionKey(), u.db, u.db.GetUsageTotals)
	}
}

func (u *UsageEngine) GetEnterpriseUsageTotalItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, input *proto.GetEnterpriseUsageTotalsRequest) ([]*models.Item, error) {
	query := u.buildEnterpriseUsageTotalQuery(upd, input)
	monthlyDocuments, err := u.itemQuerier.QueryItems(ctx, logger, query, upd.ToGetLineItemsPartitionKey())
	if err != nil {
		return nil, err
	}

	return monthlyDocuments, nil
}

func (u *UsageEngine) GetUsageTotalItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, usageEntityId string, year int64, month int64) ([]*models.Item, error) {
	query := u.buildUsageTotalQuery(usageEntityId, year, month)
	monthlyDocuments, err := u.itemQuerier.QueryItems(ctx, logger, query, upd.ToGetLineItemsPartitionKey())
	if err != nil {
		return nil, err
	}

	return monthlyDocuments, nil
}

func (u *UsageEngine) GetRepoUsage(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error) {
	pk := models.GetRepoPartitionKey(upd.ToPartitionKey())
	return u.itemQuerier.QueryItems(ctx, logger, db.QueryStringAllNontotal, pk)
}

func (u *UsageEngine) MakeCostCenterIdNameMap(costCenters []*models.CostCenter) map[string]string {
	costCenterIdNameMap := make(map[string]string)
	for _, costCenter := range costCenters {
		costCenterIdNameMap[costCenter.Id] = costCenter.Name
	}
	return costCenterIdNameMap
}

func (u *UsageEngine) GetProtoNetUsageLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail, costCenters []*models.CostCenter, customerId string) ([]*proto.NetUsageItem, error) {
	start := time.Now()
	defer func() {
		logger.Info("GetProtoNetUsageLineItems", kvp.Duration("duration", time.Since(start)), kvp.String(logging.BillingCustomerId, upd.UsageEntityId))
	}()

	errs, gctx := errgroup.WithContext(ctx)

	var items []*models.Item
	var discountItems []*models.DiscountItem

	errs.Go(func() error {
		queriedItems, err := u.GetAllLineItems(gctx, logger, upd)
		if err != nil {
			return errors.Wrap(err, "Failed to get line items when querying usage for net usage line items")
		}

		items = append(items, queriedItems...)

		return nil
	})

	errs.Go(func() error {
		queriedDiscountItems, err := u.GetAllDiscountLineItems(gctx, logger, upd)
		if err != nil {
			return errors.Wrap(err, "Failed to get discount line items when querying usage for net usage line items")
		}

		discountItems = append(discountItems, queriedDiscountItems...)

		return nil
	})

	if err := errs.Wait(); err != nil {
		return nil, errors.Wrap(err, "Failed to query net usage line items")
	}

	discountItemsMap := u.buildDiscountItemMap(discountItems)
	costCenterMap := u.MakeCostCenterIdNameMap(costCenters)
	protoNetUsageItems := make([]*proto.NetUsageItem, len(items))
	calculateLicensedFields := u.flagger.IsEnabledWithDefaultValue(ctx, featureflags.BillingProrationForLicensedProducts, false, models.CustomerVexiActor(customerId)) && upd.ActiveType != models.Yearly

	for i, item := range items {
		protoNetUsageItems[i] = item.ToNetUsageItemProto(discountItemsMap[item.Id], calculateLicensedFields)

		// Add cost center name to usage entity id
		if costCenterName, ok := costCenterMap[protoNetUsageItems[i].UsageEntityId]; ok {
			protoNetUsageItems[i].Name = costCenterName
		} else {
			protoNetUsageItems[i].Name = "Enterprise Only"
		}

	}

	return protoNetUsageItems, nil
}

func (u *UsageEngine) GetNetUsageLineItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) (models.PartitionDetailUsageItemResults, error) {
	errs, gctx := errgroup.WithContext(ctx)

	var items []*models.Item
	var discountItems []*models.DiscountItem

	errs.Go(func() error {
		queriedItems, err := u.GetAllLineItems(gctx, logger, upd)
		if err != nil {
			return errors.Wrap(err, "Failed to get line items when querying usage for net usage line items")
		}

		items = append(items, queriedItems...)

		return nil
	})

	errs.Go(func() error {
		queriedDiscountItems, err := u.GetAllDiscountLineItems(gctx, logger, upd)
		if err != nil {
			return errors.Wrap(err, "Failed to get discount line items when querying usage for net usage line items")
		}

		discountItems = append(discountItems, queriedDiscountItems...)

		return nil
	})

	if err := errs.Wait(); err != nil {
		return newPartitionDetailUsageItemResults(upd, nil), errors.Wrap(err, "Failed to query usage for usage chart")
	}

	discountItemsMap := u.buildDiscountItemMap(discountItems)

	protoNetUsageItems := make([]*models.UsageItem, len(items))
	for i, item := range items {
		protoNetUsageItems[i] = item.ToUsageItem(discountItemsMap[item.Id])
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
			Opts: []aqueduct.SendOption{aqueduct.WithJobMaxRedeliveryAttempts(10)},
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

func (u *UsageEngine) ScheduleZuoraEmission(ctx context.Context, logger log.Logger, emissionTarget *models.EmissionTarget, skipCache bool) error {

	logger.Info("ScheduleZuoraEmission Start")
	start := time.Now()

	products, err := u.pricingEngine.GetAllPricing(ctx, logger, skipCache)
	if err != nil {
		logger.WithError(err).Error("error getting all products/skus")
		return err
	}

	var allUsageItems []*models.Item

	for _, product := range products {
		// partitionDetail is expected to be something like "packages_storage:2024:9:1:byZuoraEmission"
		partitionDetail := models.GetPartitionDetailForDailyZuoraEmission(product.Sku, emissionTarget)

		usageItems, err := u.GetZuoraEmissionDailyRollupUsageItems(ctx, logger, partitionDetail)
		if err != nil {
			logger.WithError(err).
				WithFields(
					kvp.String("productSku", product.Sku),
					kvp.Int64("emissionYear", emissionTarget.Year),
					kvp.Int64("emissionMonth", emissionTarget.Month),
					kvp.Int64("emissionDay", emissionTarget.Day),
				).
				Error("error getting line items for partition")
			continue
		}

		allUsageItems = append(allUsageItems, usageItems...)
	}

	itemsGroupedByCustomerID := u.groupItemsByCustomerID(allUsageItems)

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

	// Logging and metrics
	duration := time.Since(start)
	logger.Info("ScheduleZuoraEmission Finished", kvp.Duration("duration", duration))
	u.statter.Timing("usage_engine.schedule_zuora_emission", stats.Tags{}, duration)

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

	isFilteringForCostCenterUsage := input.CostCenterId != ""
	if isFilteringForCostCenterUsage {
		logger.Info("skipping top org repo cache for cost center search request",
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
	// queries for months in the last year are also static and can be read from Cosmos
	if input.BillingPeriod == proto.BillingPeriod_Monthly && (requestedUsageTime.Month() < now.Month() || requestedUsageTime.Year() < now.Year()) {
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

func (u *UsageEngine) GetZuoraEmissionDailyRollupUsageItems(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) ([]*models.Item, error) {
	// This partition key looks at yesterday's date
	pk := upd.ToDailyZuoraEmissionPartitionKey()
	usageItems, err := u.itemQuerier.QueryItems(ctx, logger, db.QueryStringAll, pk)
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

func (u *UsageEngine) buildEnterpriseUsageTotalQuery(upd *models.UsagePartitionDetail, input *proto.GetEnterpriseUsageTotalsRequest) string {
	query := db.QueryStringAllNontotal

	// get documents for the requested year and month. Such document IDs are of the form:
	// "1061737:git_lfs_storage:2024:1"
	// We use a LIKE since the IDs can contain a SKU and we want to match all of them
	query += fmt.Sprintf(" AND c.id LIKE '%s:%%:%d:%d'", upd.UsageEntityId, input.Year, input.Month)

	return query
}

func (u *UsageEngine) buildUsageTotalQuery(usageEntityId string, year int64, month int64) string {
	query := db.QueryStringAllNontotal

	// get documents for the requested year and month. Such document IDs are of the form:
	// "1061737:git_lfs_storage:2024:1"
	// We use a LIKE since the IDs can contain a SKU and we want to match all of them
	query += fmt.Sprintf(" AND c.id LIKE '%s:%%:%d:%d'", usageEntityId, year, month)

	return query
}
