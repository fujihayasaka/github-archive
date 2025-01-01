package engines

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	repositories "github.com/github/monolith-twirp-billing/repositories/v1"
	"github.com/pkg/errors"

	//nolint:staticcheck
	"golang.org/x/sync/errgroup"
)

type CustomerEngine struct {
	*EngineParams
}

func NewCustomerEngine(params *EngineParams) *CustomerEngine {
	return &CustomerEngine{
		EngineParams: params,
	}
}

func (e *CustomerEngine) Upsert(ctx context.Context, logger log.Logger, customer *models.Customer) error {
	err := e.db.UpsertWithOptions(ctx, logger, customer, nil)
	return err
}

func (e *CustomerEngine) PatchCustomer(ctx context.Context, logger log.Logger, customer *models.Customer, toPatch *proto.Customer) error {

	type patchFunc func(*azcosmos.PatchOperations, string, any)

	// Patch operation functions,
	appendSet := func(p *azcosmos.PatchOperations, path string, value any) {
		p.AppendSet(path, value)
	}

	appendAdd := func(p *azcosmos.PatchOperations, path string, value any) {
		p.AppendAdd(path, value)
	}

	// Op allows us to specify which operation (specified above) to perform
	type PatchOp struct {
		Path  string
		Value any
		Op    patchFunc // Operation function
	}

	po := []PatchOp{}

	po = append(po, PatchOp{"/BillingTarget", models.BillingTarget(toPatch.BillingTarget), appendSet})
	po = append(po, PatchOp{"/AzureAccountId", toPatch.AzureAccountId, appendSet})
	po = append(po, PatchOp{"/ZuoraAccountNumber", toPatch.ZuoraAccountNumber, appendSet})
	po = append(po, PatchOp{"/DiscountPlanName", toPatch.DiscountPlanName, appendSet})
	po = append(po, PatchOp{"/EnabledProducts", toPatch.EnabledProducts, appendSet})
	po = append(po, PatchOp{"/HasPaymentMethod", toPatch.HasPaymentMethod, appendSet})
	po = append(po, PatchOp{"/HasZuoraSubscription", toPatch.HasZuoraSubscription, appendSet})
	po = append(po, PatchOp{"/IsBillingLocked", toPatch.IsBillingLocked, appendSet})
	po = append(po, PatchOp{"/IsStaffOwned", toPatch.IsStaffOwned, appendSet})

	// empty array of EnabledProducts essentially means that the customer is not active on billing platform
	// mark it as active by setting the EffectiveAt if there is at least one enabled product
	if (len(customer.EnabledProducts) == 0) && (len(toPatch.EnabledProducts) > 0) {
		po = append(po, PatchOp{"/EffectiveAt", time.Now().Unix(), appendSet})
	}

	if toPatch.TradeScreening != nil {
		po = append(po, PatchOp{"/TradeScreening", toPatch.TradeScreening, appendAdd})
	}

	assign := func(batch *azcosmos.TransactionalBatch) error {
		// CosmosDB has a limit of 10 operations per batch
		limit := 10
		patchItem := azcosmos.PatchOperations{}
		for i, op := range po {
			// Adds chosen operation to patchItem
			op.Op(&patchItem, op.Path, op.Value)
			batchSize := i + 1
			// Limit reached or last item
			if batchSize%limit == 0 || batchSize == len(po) {
				batch.PatchItem(customer.Id, patchItem, nil)
				patchItem = azcosmos.PatchOperations{}
			}
		}
		return nil
	}

	_, _, err := e.db.Batch(ctx, customer, nil, assign)
	return err
}

type DiscountSearch struct {
	context                  context.Context
	customerEngine           *CustomerEngine
	discountQuerier          *db.Querier[*models.Discount]
	lookupQuerier            *db.Querier[*models.DiscountTargetLookup]
	customer                 *models.Customer
	item                     *models.Item
	foundPercentageDiscounts []*models.Discount
	foundDollarDiscounts     []*models.Discount
}

func (e *CustomerEngine) NewDiscountSearch(ctx context.Context, customerID string, item *models.Item) *DiscountSearch {
	return &DiscountSearch{
		context:                  ctx,
		customerEngine:           e,
		discountQuerier:          db.NewQuerier[*models.Discount](e.db),
		lookupQuerier:            db.NewQuerier[*models.DiscountTargetLookup](e.db),
		customer:                 models.NewCustomer(customerID),
		item:                     item,
		foundPercentageDiscounts: make([]*models.Discount, 0),
		foundDollarDiscounts:     make([]*models.Discount, 0),
	}
}

func (ds *DiscountSearch) GetDiscountsByTargetType(logger log.Logger, tt models.DiscountTargetType, now *models.UsageTime) (*DiscountSearch, error) {
	copy := *ds

	targetId := tt.GetTargetIdByTargetType(copy.item)
	if targetId == "" {
		return nil, fmt.Errorf("can't build targetId for target type (targetType=%s, customerId=%s, itemId=%s)", tt.String(), copy.customer.GetCustomerId(), copy.item.Id)
	}

	dt := &models.DiscountTarget{
		Id:   targetId,
		Type: tt,
	}
	key := models.ToTargetLookupKey(copy.customer.ToDiscountsPartitionKey(), dt)

	discountTargetLookup, err := copy.lookupQuerier.ReadItemWithRetries(copy.context, logger, key)
	if err != nil {
		return nil, err
	}

	if discountTargetLookup == nil {
		return &copy, nil
	}

	for _, uuid := range discountTargetLookup.Uuids {
		discountKey := models.NewDiscountKey(copy.customer, uuid)
		discount, err := copy.discountQuerier.ReadItemWithRetries(copy.context, logger, discountKey)
		if err != nil {
			return nil, err
		}
		if discount.IsValidFor(now) {
			if discount.IsPercentage() {
				copy.foundPercentageDiscounts = append(copy.foundPercentageDiscounts, discount)
			} else {
				copy.foundDollarDiscounts = append(copy.foundDollarDiscounts, discount)
			}
		}
	}

	return &copy, nil
}

func (e *CustomerEngine) CreateDiscount(ctx context.Context, logger log.Logger, discount *models.Discount) (*models.Discount, error) {
	success, results, err := e.db.Batch(ctx, discount, nil, func(batch *azcosmos.TransactionalBatch) error {
		marshalledDiscount, err := json.Marshal(discount)
		if err != nil {
			return errors.Wrap(err, "unable to marshal discount")
		}

		batch.UpsertItem(marshalledDiscount, nil)

		for _, target := range discount.Targets {
			targetLookup := discount.AsTargetLookup(target)
			existingTargetLookup, err := db.NewQuerier[*models.DiscountTargetLookup](e.db).ReadItemWithRetries(ctx, logger, targetLookup)
			if err != nil {
				return err
			}

			if existingTargetLookup != nil {
				targetLookup.Uuids = append(targetLookup.Uuids, existingTargetLookup.Uuids...)
			}

			marshalledTarget, err := json.Marshal(targetLookup)
			if err != nil {
				return errors.Wrap(err, "unable to marshal target lookup")
			}
			batch.UpsertItem(marshalledTarget, nil)
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	if !success {
		for index, result := range results {
			if result.StatusCode == http.StatusConflict {
				return nil, db.ItemConflictError
			} else if result.StatusCode != http.StatusFailedDependency {
				return nil, fmt.Errorf("transaction failed due to operation %v which failed with status code %v", index, result.StatusCode)
			}
		}
	}

	return nil, nil
}

func (e *CustomerEngine) GetCachedRepositoryMetadata(ctx context.Context, logger log.Logger, repoId int64) (*models.Repo, error) {
	return db.NewQuerier[*models.Repo](e.db).ReadItemWithRetries(ctx, logger, models.NewRepoKey(repoId))
}

func (e *CustomerEngine) CacheRepositoryMetadata(ctx context.Context, logger log.Logger, repo *repositories.Repository) error {
	return e.db.UpsertWithOptions(ctx, logger, models.NewRepo(int64(repo.Id), repo.IsPublic), nil)
}

func (e *CustomerEngine) PublicRepoDiscountApplicable(ctx context.Context, logger log.Logger, customerId string, sku string, repoId int64, billForPublicRepoUsage bool) (bool, error) {
	logger = logger.WithFields(kvp.String("customerId", customerId), kvp.String("sku", sku), kvp.Int64("repoId", repoId))

	if billForPublicRepoUsage {
		return false, nil
	}

	pricingEngine := NewPricingEngine(e.EngineParams)
	pricing := pricingEngine.GetCurrentPricing(ctx, logger, &PricingSelectionData{ProductSku: sku})
	if pricing == nil {
		logger.Info("pricing not found")
		return false, nil
	}

	var repoMetadata models.RepoMetadata

	repo, err := e.GetCachedRepositoryMetadata(ctx, logger, repoId)
	if (repo == nil) || (err != nil) {
		resp, err := e.monolithClient.RepositoryAPI.GetRepositoryMetadata(ctx, &repositories.GetRepositoryMetadataRequest{Id: uint64(repoId)})
		if err != nil {
			logger.WithError(err).Info("repo not found")
			return false, nil
		}

		err = e.CacheRepositoryMetadata(ctx, logger, resp.Repository)
		if err != nil {
			logger.WithError(err).Info("unable to cache repo metadata")
		}

		repoMetadata = resp.Repository
	} else {
		repoMetadata = repo
	}

	return repoMetadata.GetIsPublic() && pricing.GetFreeForPublicRepos(), nil
}

func (e *CustomerEngine) GetLargestPlanDiscount(ctx context.Context, logger log.Logger, customerId string, item *models.Item, enterpriseInfo *models.EnterpriseInfo, now *models.UsageTime) (*models.Discount, error) {
	planDiscounts, err := e.GetPlanDiscounts(ctx, logger, item, enterpriseInfo, models.SkuDiscount, now)
	if err != nil {
		return &models.Discount{}, err
	}

	result, _, err := e.findLargestDiscount(ctx, logger, planDiscounts, customerId, item.BilledAmount, now)

	return result, err
}

// Of all applicable discounts, we will apply the largest to the usage based on the derived amount.
// Dollar discounts are straight forward - find the largest value and apply it.
// For percent discounts we will calculate the "amount" of the discount based on the percentage against the line item, and compare this to all other discounts.
// See https://github.com/github/gitcoin/issues/11952 for more context.
func (e *CustomerEngine) GetLargestConfiguredDiscount(ctx context.Context, logger log.Logger, customerId string, item *models.Item, now *models.UsageTime) (*models.Discount, models.DiscountType, error) {
	var err error
	discountSearch := e.NewDiscountSearch(ctx, customerId, item)

	for _, tt := range models.DiscountTargetsFor(item) {
		discountSearch, err = discountSearch.GetDiscountsByTargetType(logger, tt, now)
		if err != nil {
			logger.Debug("failed to get discounts by target type", kvp.String("customer", customerId))
			return &models.Discount{}, models.NoDiscountType, err
		}
	}

	availableDiscounts := discountSearch.foundPercentageDiscounts
	availableDiscounts = append(availableDiscounts, discountSearch.foundDollarDiscounts...)

	return e.findLargestDiscount(ctx, logger, availableDiscounts, customerId, item.BilledAmount, now)
}

func (e *CustomerEngine) findLargestDiscount(ctx context.Context, logger log.Logger, discounts []*models.Discount, customerId string, billedAmount int64, now *models.UsageTime) (*models.Discount, models.DiscountType, error) {
	year := int64(now.Year())
	month := int64(now.Month())
	customer := models.NewCustomer(customerId)

	var result models.Discount
	var associatedDiscountState models.DiscountState
	discountType := models.NoDiscountType

	for _, discount := range discounts {
		discountKey := models.NewDiscountKey(customer, discount.Uuid)
		discountState, err := e.getOrInitDiscountState(ctx, logger, customerId, discountKey, discount, year, month)
		if err != nil {
			logger.Debug("failed to get discount state", kvp.String("discount", discount.Uuid), kvp.String("customer", customerId), kvp.String("discountId", discount.Id))
			continue
		}

		if discountState.IsFullyApplied {
			logger.Debug("discount state fully applied", kvp.String("discount", discount.Uuid), kvp.String("customer", customerId), kvp.String("discountId", discount.Id))
			continue
		}

		discountAmount := discount.AsDollarValue(billedAmount, discountState.CurrentAmount)
		largestDiscountAmount := result.AsDollarValue(billedAmount, associatedDiscountState.CurrentAmount)

		if discountAmount > largestDiscountAmount {
			result = *discount
			associatedDiscountState = *discountState
			if discount.IsPercentage() {
				discountType = models.PercentageDiscountType
			} else {
				discountType = models.DollarDiscountType
			}
		}
	}

	return &result, discountType, nil
}

func (e *CustomerEngine) GetPlanDiscounts(ctx context.Context, logger log.Logger, item *models.Item, enterpriseInfo *models.EnterpriseInfo, tt models.DiscountTargetType, now *models.UsageTime) ([]*models.Discount, error) {
	foundDiscounts := make([]*models.Discount, 0)
	planDiscounts, ok := AllPlanDiscounts()[enterpriseInfo.DiscountPlanName]
	if ok {
		for _, planDiscount := range planDiscounts {
			// Only include the plan discounts available for the given sku
			if !planDiscountContains(planDiscount.Targets, item.GetSku()) {
				continue
			}

			discount := models.NewPlanDiscountForSku(planDiscount)

			if discount.IsValidFor(now) {
				foundDiscounts = append(foundDiscounts, discount)
				e.statter.Counter("plan-discount-applied", stats.Tags{"discount-plan-name": enterpriseInfo.DiscountPlanName}, int64(1))
			} else {
				logger.Info("GetPlanDiscounts invalid timeframe")
			}
		}
	} else {
		e.statter.Counter("plan-discount-not-applied", stats.Tags{"discount-plan-name": enterpriseInfo.DiscountPlanName, "reason": "discount-not-found"}, int64(1))
	}

	return foundDiscounts, nil
}

func (e *CustomerEngine) GetDiscount(ctx context.Context, logger log.Logger, key *proto.DiscountKey) (*models.Discount, error) {
	discountKey := models.NewDiscountKeyFromProto(key)

	discount, err := db.NewQuerier[*models.Discount](e.db).ReadItemWithRetries(ctx, logger, discountKey)
	if err != nil {
		return nil, err
	}

	return discount, nil
}

func (e *CustomerEngine) DiscountIsInvalid(ctx context.Context, logger log.Logger, discount *models.Discount, discountState *models.DiscountState) bool {
	now := models.UTCNow()
	discountTotal, _ := e.db.GetDiscountTotals(ctx, logger, discount.PartitionKey)
	isInvalidDiscount := !discount.IsValidFor(now) && discountState.IsFullyApplied && discountState.TargetAmount != discountTotal.BilledAmount

	return isInvalidDiscount
}

func (e *CustomerEngine) GetAllDiscounts(ctx context.Context, logger log.Logger, customerId string) ([]*models.Discount, error) {
	discountsKey := models.CustomerIdToDiscountsPartitionKey(customerId)

	queryStringAllDiscounts := "SELECT * FROM c WHERE NOT IS_DEFINED(c.Uuids)"
	discounts, err := db.NewQuerier[*models.Discount](e.db).QueryItems(ctx, logger, queryStringAllDiscounts, discountsKey)
	if err != nil {
		return nil, err
	}

	return discounts, nil
}

func (e *CustomerEngine) GetAllDiscountStates(ctx context.Context, logger log.Logger, customerId string, year, month int64) ([]*proto.DiscountState, error) {
	discountsKey := models.CustomerIdToDiscountsPartitionKey(customerId)

	queryStringAllDiscounts := "SELECT * FROM c WHERE NOT IS_DEFINED(c.Uuids)"
	discounts, err := db.NewQuerier[*models.Discount](e.db).QueryItems(ctx, logger, queryStringAllDiscounts, discountsKey)
	if err != nil {
		return nil, err
	}

	var discountStates []*proto.DiscountState = []*proto.DiscountState{}

	customer, err := e.Get(ctx, logger, customerId)
	if err != nil {
		return nil, err
	}

	if customer == nil {
		return discountStates, nil
	}

	var planDiscounts []*models.PlanDiscount = AllPlanDiscounts()[customer.DiscountPlanName]
	for _, planDiscount := range planDiscounts {
		discounts = append(discounts, models.NewPlanDiscountForSku(planDiscount))
	}

	for _, discount := range discounts {
		customerDiscountKey := models.NewDiscountKey(customer, discount.Uuid)
		discountState, err := e.GetDiscountState(ctx, logger, customerDiscountKey, year, month)

		if err != nil {
			return nil, err
		}

		if discountState != nil {
			discountStates = append(discountStates, models.ToProtoDiscountState(discountState.IsFullyApplied, discountState.CurrentAmount, discount.TargetAmount, discount.Percentage, discount.Uuid, discount.Targets))
		} else {
			// presumably, if discountState is nil for plan discounts then the customer has not incurred any usage yet for those skus
			discountStates = append(discountStates, models.ToProtoDiscountState(false, 0, discount.TargetAmount, discount.Percentage, discount.Uuid, discount.Targets))
		}
	}

	// the UUID for the free for public repos discount is static, so its discount state can be queried directly
	publicReposDiscountKey := models.NewDiscountKey(customer, models.PublicRepo100PercentDiscountUUID)
	publicReposDiscountState, err := e.GetDiscountState(ctx, logger, publicReposDiscountKey, year, month)

	if err != nil {
		return nil, err
	}

	if publicReposDiscountState != nil {
		discountStates = append(
			discountStates,
			models.ToProtoDiscountState(
				publicReposDiscountState.IsFullyApplied,
				publicReposDiscountState.CurrentAmount,
				publicReposDiscountState.TargetAmount,
				100,
				models.PublicRepo100PercentDiscountUUID,
				[]*models.DiscountTarget{},
			),
		)
	}

	return discountStates, nil
}

func (e *CustomerEngine) GetDiscountState(ctx context.Context, logger log.Logger, discountKey *models.DiscountKey, year, month int64) (*models.DiscountState, error) {
	discountStateKey := discountKey.ToDiscountStateKey(year, month)
	discountState, err := db.NewQuerier[*models.DiscountState](e.db).ReadItemWithRetries(ctx, logger, discountStateKey)
	if err != nil {
		return nil, err
	}

	return discountState, nil
}

func (e *CustomerEngine) getOrInitDiscountState(ctx context.Context, logger log.Logger, customerID string, discountKey *models.DiscountKey, discount *models.Discount, year, month int64) (*models.DiscountState, error) {
	existingDiscountState, err := e.GetDiscountState(ctx, logger, discountKey, year, month)
	if err != nil {
		logger.Debug("failed to get discount state", kvp.String("discount", discount.Uuid), kvp.String("customer", customerID), kvp.String("discountId", discount.Id))
		return nil, err
	}

	if existingDiscountState == nil {
		return models.NewDiscountState(customerID, discountKey, discount, year, month), nil
	} else {
		return existingDiscountState, nil
	}
}

func (e *CustomerEngine) UpdateDiscountState(ctx context.Context, logger log.Logger, item *models.Item, customerID string, discount *models.Discount, amount int64, year, month int64) (int64, error) {
	customer := models.NewCustomer(customerID)
	discountKey := models.NewDiscountKey(customer, discount.Uuid)
	discountState, err := e.getOrInitDiscountState(ctx, logger, customerID, discountKey, discount, year, month)
	if err != nil {
		return 0, err
	}

	if e.DiscountIsInvalid(ctx, logger, discount, discountState) {
		e.statter.Counter("invalid-discount", stats.Tags{}, int64(1))
		logger.Debug("invalid discount details", kvp.String("discount", discount.Uuid), kvp.String("customer", customerID), kvp.String("discountId", discount.Id))
	}

	if discountState.IsFullyApplied {
		logger.Debug("discount fully applied", kvp.String("discount", discount.Uuid), kvp.String("customer", customerID), kvp.String("discountId", discount.Id))
		return 0, nil
	}

	var amountExceedingBudget int64
	newAmount := discountState.CurrentAmount + amount
	if discount.IsPercentage() { // never fully applied, so we only need to track the CurrentAmount
		discountState.CurrentAmount = newAmount
	} else {
		if newAmount >= discountState.TargetAmount {
			discountState.IsFullyApplied = true
			discountState.CurrentAmount = discountState.TargetAmount
			amountExceedingBudget = newAmount - discountState.TargetAmount
		} else {
			discountState.CurrentAmount = newAmount
		}
	}

	success, results, err := e.db.Batch(ctx, discountState, nil, func(batch *azcosmos.TransactionalBatch) error {
		marshalledDiscountState, err := json.Marshal(discountState)
		if err != nil {
			return errors.Wrap(err, "unable to marshal discount state")
		}

		if discountState.IsNewDocument() {
			batch.UpsertItem(marshalledDiscountState, nil)
		} else {
			po := azcosmos.PatchOperations{}

			// This pre-condition ensures that we don't update the discount state if it has been fully applied since the last time we read it.
			// More on this feature here: https://learn.microsoft.com/en-us/azure/cosmos-db/partial-document-update#supported-modes
			preConditionQuery := "from c where c.IsFullyApplied <> true"
			po.SetCondition(preConditionQuery)

			po.AppendReplace("/CurrentAmount", discountState.CurrentAmount)
			po.AppendReplace("/IsFullyApplied", discountState.IsFullyApplied)
			batch.PatchItem(discountState.Id, po, nil)
		}

		discountTrackItem := models.NewDiscountTrackItem(item, discountState, amount-amountExceedingBudget)
		marshalledDiscountTrackItem, err := json.Marshal(discountTrackItem)
		if err != nil {
			return errors.Wrap(err, "unable to marshal discount track item")
		}

		batch.UpsertItem(marshalledDiscountTrackItem, nil)

		return nil
	})

	if err != nil {
		return 0, err
	}

	if !success {
		for index, result := range results {
			switch {
			case result.StatusCode == http.StatusConflict:
				return 0, db.ItemConflictError
			case result.StatusCode == http.StatusPreconditionFailed:
				logger.Info("***DISCOUNT_STATE IS STALE!!!****", kvp.String("customer", customerID), kvp.String("discountStateEtag", discountState.CosmosProperties.ETag))
				e.statter.Counter("stale-discountState", stats.Tags{}, int64(1))
				return 0, nil
			case result.StatusCode != http.StatusFailedDependency:
				return 0, fmt.Errorf("transaction failed due to operation %v which failed with status code %v", index, result.StatusCode)
			}
		}
	}

	return amountExceedingBudget, nil
}

func (e *CustomerEngine) FindBudgetsFor(ctx context.Context, logger log.Logger, product string, sku string, entity *models.EntityDetail, year, month int64) ([]*models.Budget, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.FindBudgetsFor")
	defer sp.End()

	foundBudgets := make([]*models.Budget, 0)

	querier := db.NewQuerier[*models.Budget](e.db)

	// ensure we are using the parent customer id and not a cost center uuid to look up budgets
	enterpriseCustomerId := entity.EnterpriseId()

	// use the v2 implementation for Avocado Corp. or GitHubInc.
	if entity.IsGitHubOwned() {
		return e.FindBudgetsForV2(ctx, logger, product, entity)
	}

	if entity.ActorId != 0 {
		actorBudgets, err := e.GetBudgetsByEntityType(ctx, logger, querier, enterpriseCustomerId, models.User, fmt.Sprintf("%d", entity.ActorId), product, sku)
		if err != nil {
			return nil, err
		}
		foundBudgets = append(foundBudgets, actorBudgets...)
	}

	if entity.RepositoryId != 0 {
		repositoryBudgets, err := e.GetBudgetsByEntityType(ctx, logger, querier, enterpriseCustomerId, models.Repository, fmt.Sprintf("%d", entity.RepositoryId), product, sku)
		if err != nil {
			return nil, err
		}
		foundBudgets = append(foundBudgets, repositoryBudgets...)
	}

	if entity.OrganizationId != 0 {
		orgBudgets, err := e.GetBudgetsByEntityType(ctx, logger, querier, enterpriseCustomerId, models.OwningEntity, fmt.Sprintf("%d", entity.OrganizationId), product, sku)
		if err != nil {
			return nil, err
		}
		foundBudgets = append(foundBudgets, orgBudgets...)
	}

	if entity.IsCostCenterProxy() {
		// if we are a cost center proxy, we need to get the budgets for the cost center
		// and add them to the list of budgets we have found.
		costCenterBudgets, err := e.GetBudgetsByEntityType(ctx, logger, querier, enterpriseCustomerId, models.CostCenterResource, entity.CustomerId, product, sku)
		if err != nil {
			return nil, err
		}
		foundBudgets = append(foundBudgets, costCenterBudgets...)
	}

	customerBudgets, err := e.GetBudgetsByEntityType(ctx, logger, querier, enterpriseCustomerId, models.CustomerResource, enterpriseCustomerId, product, sku)
	if err != nil {
		return nil, err
	}
	foundBudgets = append(foundBudgets, customerBudgets...)

	// For legacy support, we include budgets with an "enterprise" entity type
	enterpriseBudgets, err := e.GetBudgetsByEntityType(ctx, logger, querier, enterpriseCustomerId, models.Enterprise, enterpriseCustomerId, product, sku)
	if err != nil {
		return nil, err
	}
	foundBudgets = append(foundBudgets, enterpriseBudgets...)

	return foundBudgets, nil
}

// FindBudgetsForV2 returns a list of budgets for the given entity, product, and sku.
// This is a newer efficient implementation that uses a single query to get all budgets for the entity.
// The filtering of the data happens after the query is made. This is in contrast to the FindBudgetsFor
// method which uses a query per budget key.
func (e *CustomerEngine) FindBudgetsForV2(ctx context.Context, logger log.Logger, product string, entity *models.EntityDetail) ([]*models.Budget, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.FindBudgetsForV2")
	defer sp.End()
	logger.Debug("FindBudgetsForV2", kvp.String("entity", entity.CustomerId))
	// ensure we are using the parent customer id and not a cost center uuid to look up budgets
	enterpriseCustomerId := entity.EnterpriseId()

	// query all budgets for the enterprise
	foundBudgets, err := e.GetAllBudgetsWithoutInfo(ctx, logger, enterpriseCustomerId)

	if err != nil {
		return nil, err
	}

	// if we have no budgets, return an empty list
	if len(foundBudgets) == 0 {
		return []*models.Budget{}, nil
	}

	filteredBudgets := make([]*models.Budget, 0)

	// filter budget based on entities
	for _, each := range foundBudgets {
		bProduct := each.BudgetKey.GetProductFromKeyId()
		// add budget if it is applicable to the entity
		if each.BudgetKey.TargetType == models.User && fmt.Sprintf("%d", entity.ActorId) == each.TargetId && bProduct == product {
			filteredBudgets = append(filteredBudgets, each)
		}
		if each.BudgetKey.TargetType == models.Repository && fmt.Sprintf("%d", entity.RepositoryId) == each.TargetId && bProduct == product {
			filteredBudgets = append(filteredBudgets, each)
		}
		if each.BudgetKey.TargetType == models.OwningEntity && fmt.Sprintf("%d", entity.OrganizationId) == each.TargetId && bProduct == product {
			filteredBudgets = append(filteredBudgets, each)
		}
		if each.BudgetKey.TargetType == models.CostCenterResource && entity.IsCostCenterProxy() && entity.CustomerId == each.TargetId && bProduct == product {
			filteredBudgets = append(filteredBudgets, each)
		}
		if each.BudgetKey.TargetType == models.CustomerResource && entity.CustomerId == enterpriseCustomerId && bProduct == product {
			filteredBudgets = append(filteredBudgets, each)
		}
		if each.BudgetKey.TargetType == models.Enterprise && entity.EnterpriseId() != "" && bProduct == product {
			filteredBudgets = append(filteredBudgets, each)
		}
	}

	return filteredBudgets, nil
}

func (e *CustomerEngine) GetBudgetsByEntityType(
	ctx context.Context,
	logger log.Logger,
	querier *db.Querier[*models.Budget],
	customerId string,
	entityType models.ResourceType,
	entityId string,
	product string,
	sku string) ([]*models.Budget, error) {

	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.GetBudgetsByEntityType")
	defer sp.End()

	// TODO some of these budget Keys do not make sense anymore and we should likely remove them in the future
	keys := []*models.BudgetKey{
		models.NewBudgetKeyFromCustomer(customerId, entityType, entityId, models.NoPricingTarget, ""), // possibly obsolete (we don't technically create budgets this way)
		models.NewBudgetKeyFromCustomer(customerId, entityType, entityId, models.ProductPricing, product),
		models.NewBudgetKeyFromCustomer(customerId, entityType, entityId, models.SkuPricing, sku), // possibly obsolete(there are no budgets that can be created on SKU)
	}

	budgets := make([]*models.Budget, 0)
	for _, key := range keys {
		budget, err := e.GetBudgetByKey(ctx, logger, querier, key)
		if err != nil {
			return nil, err
		}
		if budget != nil {
			budgets = append(budgets, budget)
		}
	}

	return budgets, nil
}

func (e *CustomerEngine) GetBudgetByKey(ctx context.Context, logger log.Logger, querier *db.Querier[*models.Budget], key *models.BudgetKey) (*models.Budget, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.GetBudgetByKey")
	defer sp.End()

	budget, err := querier.ReadItemWithRetries(ctx, logger, key)
	if err != nil {
		return nil, err
	}

	return budget, nil
}

func (e *CustomerEngine) GetBudgetByUuid(ctx context.Context, logger log.Logger, customerId string, uuid string) (*models.Budget, error) {
	pk := models.CustomerIdToBudgetsPartitionKey(customerId)
	query := fmt.Sprintf("%s WHERE c.Uuid = \"%s\"", db.QueryStringAll, uuid)

	budgets, err := db.NewQuerier[*models.Budget](e.db).QueryItems(ctx, logger, query, pk)
	if err != nil {
		return nil, err
	}

	if len(budgets) == 0 {
		return nil, nil
	} else {
		return budgets[0], nil
	}

}

func (e *CustomerEngine) Get(ctx context.Context, logger log.Logger, customerId string) (*models.Customer, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.Get")
	defer sp.End()

	customerKey := models.NewCustomerKey(customerId)

	// Our default consistency level is session, but we want to read from the cache so we need to lax the
	// consistency level to eventual. The alternative would be to pass and manually manage the session token
	// ourselves which is not ideal and the Go SDK does not do this automatically as Azure documentation suggests.
	options := &interfaces.QueryOptions{
		ConsistencyLevel: azcosmos.ConsistencyLevelEventual.ToPtr(),
	}
	customer, err := db.NewGatewayQuerier[*models.Customer](e.db).ReadItem(ctx, logger, customerKey, options) // uses the item cache
	return customer, err
}

func (e *CustomerEngine) UpsertBudget(ctx context.Context, logger log.Logger, budget *models.Budget) error {
	customer, err := e.Get(ctx, logger, budget.CustomerId)
	if err != nil {
		return err
	}
	if customer.IsOnTrial() {
		return errors.New("Customers on trial cannot create budgets")
	}

	err = e.db.UpsertWithOptions(ctx, logger, budget, nil)
	if err != nil {
		return err
	}

	// update the TargetAmount on the budget state
	now := models.UTCNow()
	year := int64(now.Year())
	month := int64(now.Month())
	budgetState, err := e.GetBudgetState(ctx, logger, budget, year, month)
	if err != nil {
		return err
	}

	budgetState.TargetAmount = budget.TargetAmount
	budgetState.IsFullyFunded = budgetState.CurrentAmount >= budgetState.TargetAmount

	err = e.UpsertBudgetState(ctx, logger, budgetState)
	if err != nil {
		return err
	}

	return nil
}

func (e *CustomerEngine) DeleteBudget(ctx context.Context, logger log.Logger, customerId string, uuid string) error {
	budgetToDelete, err := e.GetBudgetByUuid(ctx, logger, customerId, uuid)
	if err != nil {
		return err
	}

	if budgetToDelete == nil {
		return nil
	}

	key := budgetToDelete.GetKey()
	err = e.db.DeleteWithOptions(ctx, logger, key, nil)
	if err != nil {
		return err
	}

	now := models.UTCNow()
	year := int64(now.Year())
	month := int64(now.Month())
	currentBudgetState, err := e.GetBudgetState(ctx, logger, budgetToDelete, year, month)
	if err != nil {
		return err
	}

	err = e.db.DeleteWithOptions(ctx, logger, currentBudgetState.Key, nil)

	return err
}

func (e *CustomerEngine) GetBudget(ctx context.Context, logger log.Logger, budgetKey *models.BudgetKey) (*models.Budget, error) {
	budget, err := db.NewQuerier[*models.Budget](e.db).ReadItemWithRetries(ctx, logger, budgetKey)
	if err != nil {
		return nil, err
	}

	return budget, nil
}

// GetAllBudgetsWithoutInfo returns all budgets for a customer without the budget state info (useful for minimal calls).
func (e *CustomerEngine) GetAllBudgetsWithoutInfo(ctx context.Context, logger log.Logger, customerId string) ([]*models.Budget, error) {
	budgetsKey := models.CustomerIdToBudgetsPartitionKey(customerId)
	budgets, err := db.NewQuerier[*models.Budget](e.db).QueryItems(ctx, logger, db.QueryStringAll, budgetsKey)
	if err != nil {
		return nil, err
	}

	return budgets, nil
}

// GetAllBudgets returns all budgets for a customer with the budget state info (useful for CRUD operations).
func (e *CustomerEngine) GetAllBudgets(ctx context.Context, logger log.Logger, customerId string) ([]*models.BudgetInfo, error) {
	budgetsKey := models.CustomerIdToBudgetsPartitionKey(customerId)
	budgets, err := db.NewQuerier[*models.Budget](e.db).QueryItems(ctx, logger, db.QueryStringAll, budgetsKey)
	if err != nil {
		return nil, err
	}
	budgetInfos := make([]*models.BudgetInfo, 0)
	now := models.UTCNow()
	year := int64(now.Year())
	month := int64(now.Month())
	g, gctx := errgroup.WithContext(ctx)

	for _, budget := range budgets {
		b := budget
		g.Go(func() error {
			budgetState, err := e.GetBudgetState(gctx, logger, b, year, month)
			if err != nil {
				return err
			}
			budgetInfos = append(budgetInfos, &models.BudgetInfo{
				Budget:      b,
				BudgetState: budgetState,
			})
			return nil
		})
	}

	if err := g.Wait(); err != nil {
		return nil, errors.Wrap(err, "error getting budget state")
	}

	return budgetInfos, nil
}

func (e *CustomerEngine) PatchBudgetState(ctx context.Context, logger log.Logger, budget *models.Budget, amounts *models.Amounts, year int64, month int64, sku string) (*models.BudgetState, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.PatchBudgetState")
	defer sp.End()

	logger.Info("updating budget state", kvp.String("budgetPK", budget.PartitionKey), kvp.String("budgetID", budget.Id))

	retryCount := 10
	// add a little jitter to the retry loop
	sleep := 200 * time.Millisecond
	for i := 0; i < retryCount; i++ {
		budgetStatePatch := &models.BudgetState{
			Key: &models.Key{
				PartitionKey: budget.ToPartitionKey(year, month),
				Id:           "budgetState",
			},
			Quantity:      amounts.Quantity,
			CurrentAmount: uint64(amounts.BilledAmount),
			TargetAmount:  budget.TargetAmount,
			IsFullyFunded: uint64(amounts.BilledAmount) >= budget.TargetAmount,
		}

		budgetState, err := db.NewQuerier[*models.BudgetState](e.db).ReadItem(ctx, logger, budgetStatePatch.Key, nil)
		if err != nil {
			return nil, fmt.Errorf("failed to query budget state %v", err)
		}

		if budgetState == nil {
			err := e.db.CreateWithOptions(ctx, logger, budgetStatePatch, nil)

			// retry on 409 conflict errors since we may run into a race condition here where it was created by another process
			if db.Is409Conflict(err) {
				e.statter.Counter(
					"budget_state.race_condition",
					stats.Tags{
						"type": "create",
					},
					int64(1),
				)
				continue
			} else if err != nil {
				return nil, err
			}

			return budgetStatePatch, nil
		}

		newBudgetState := &models.BudgetState{
			Key:           budgetStatePatch.Key,
			Quantity:      (budgetState.Quantity + budgetStatePatch.Quantity),
			CurrentAmount: (budgetState.CurrentAmount + budgetStatePatch.CurrentAmount),
			TargetAmount:  budget.TargetAmount,
			// check if the new current amount exceeds the budget target amount
			IsFullyFunded: (budgetState.CurrentAmount + budgetStatePatch.CurrentAmount) >= (budget.TargetAmount),
		}

		err = e.db.UpsertWithOptions(ctx, logger, newBudgetState,
			&interfaces.QueryOptions{
				IfMatchEtag: budgetState.ETag,
				RetryCount:  20,
			},
		)

		// if the error is a 412, then we ran into a race condition and should retry the update logic
		if db.Is412PreconditionError(err) {
			e.statter.Counter(
				"budget_state.race_condition",
				stats.Tags{
					"type": "upsert",
				},
				int64(1),
			)
			// add a little jitter to the retry loop
			jitter := time.Duration(rand.Int63n(int64(sleep)))
			time.Sleep(sleep + jitter)
			continue
		} else if err != nil {
			return nil, err
		}

		return newBudgetState, nil
	}

	e.statter.Counter("patch_budget_state.retries_exhausted", stats.Tags{"sku": sku}, int64(1))
	return nil, fmt.Errorf("failed to update budget state after %d retries", retryCount)
}

func (e *CustomerEngine) PublishBudgetStateThresholdMessage(logger log.Logger, hydroPublisher interfaces.HydroPublisher, budget *models.Budget, budgetState *models.BudgetState) error {
	budgetState.ThresholdMet = *budgetState.GetThresholdMet()
	budgetThresholdMet := budgetState.ThresholdMet
	if budgetThresholdMet.Alertable {
		logger.Info("alerting budget threshold met", kvp.Any("BudgetKey", budget.BudgetKey), kvp.String("ThresholdName", budgetThresholdMet.Name))
		// NOTE: The BudgetThresholdNotification schema still uses floats, we should probably update that now that we're moving away.
		// I just cast the existing values to floats to avoid a breaking change for now.
		budgetThresholdNotification := hydroSchema.BudgetThresholdNotification{
			Budget: &hydroSchemaEntities.Budget{
				Key: &hydroSchemaEntities.BudgetKey{
					CustomerId:        budget.BudgetKey.CustomerId,
					TargetType:        hydroSchemaEntities.BudgetKey_ResourceType(budget.BudgetKey.TargetType),
					TargetId:          budget.BudgetKey.TargetId,
					PricingTargetType: hydroSchemaEntities.BudgetKey_PricingTargetType(budget.BudgetKey.PricingTargetType),
					PricingTargetId:   budget.BudgetKey.PricingTargetId,
				},
				TargetAmount: models.ToDecimalAmount(budget.TargetAmount),
				BudgetAlerting: &hydroSchemaEntities.Budget_BudgetAlerting{
					WillAlert:        budget.BudgetAlerting.WillAlert,
					RecipientUserIds: budget.RecipientUserIDs,
				},
				BudgetLimitType: hydroSchemaEntities.Budget_BudgetLimitType(budget.BudgetLimitType),
				Uuid:            budget.Uuid,
			},
			BudgetState: &hydroSchemaEntities.BudgetState{
				IsFullyFunded: budgetState.IsFullyFunded,
				CurrentAmount: models.ToDecimalAmount(budgetState.CurrentAmount),
				TargetAmount:  models.ToDecimalAmount(budgetState.TargetAmount),
				Quantity:      float64(budgetState.Quantity),
				ThresholdMet: &hydroSchemaEntities.BudgetState_BudgetThreshold{
					Name:                   budgetThresholdMet.Name,
					Alertable:              budgetThresholdMet.Alertable,
					MinimumUsagePercentage: float64(budgetThresholdMet.MinimumUsagePercentage),
				},
			},
		}

		err := hydroPublisher.Publish(&budgetThresholdNotification)
		if err != nil {
			logger.WithError(err).Error("failed to publish budget threshold notification",
				kvp.Any("BudgetKey", budget.BudgetKey),
				kvp.String("ThresholdName", budgetThresholdMet.Name),
				kvp.String("BudgetStateId", budgetState.Id),
				kvp.String("BudgetStatePartitionKey", budgetState.PartitionKey),
			)
			return fmt.Errorf("failed to publish budget threshold notification %v", err)
		} else {
			logger.Info("published budget threshold notification",
				kvp.Any("BudgetKey", budget.BudgetKey),
				kvp.String("ThresholdName", budgetThresholdMet.Name),
				kvp.String("BudgetStateId", budgetState.Id),
				kvp.String("BudgetStatePartitionKey", budgetState.PartitionKey),
			)
		}
	}

	return nil
}

func (e *CustomerEngine) UpsertBudgetState(ctx context.Context, logger log.Logger, budgetState *models.BudgetState) error {
	err := e.db.UpsertWithOptions(ctx, logger, budgetState, nil)
	return err
}

func (e *CustomerEngine) GetBudgetState(ctx context.Context, logger log.Logger, budget *models.Budget, year, month int64) (*models.BudgetState, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.GetBudgetState")
	defer sp.End()

	budgetStateKey := budget.BudgetKey.ToBudgetStateKey(year, month, models.DocumentIdBudgetState)
	// get the running total from budget:<id> / runningTotal
	budgetState, err := db.NewQuerier[*models.BudgetState](e.db).ReadItemWithRetries(ctx, logger, budgetStateKey)
	if err != nil {
		return nil, err
	}

	if budgetState != nil {
		budgetState.ThresholdMet = *budgetState.GetThresholdMet()
	} else {
		budgetState = models.NewBudgetState(budget, year, month)
		if budget.TargetAmount == 0 {
			budgetState.IsFullyFunded = true
		}
	}

	return budgetState, nil
}

func (e *CustomerEngine) CanProceedWithIncludedDiscounts(ctx context.Context, logger log.Logger, customer *models.Customer, sku string, year, month int64) ([]*models.DiscountState, bool, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.CanProceedWithIncludedDiscounts")
	defer sp.End()

	planDiscountStates := make([]*models.DiscountState, 0)
	planDiscounts, ok := AllPlanDiscounts()[customer.DiscountPlanName]
	if !ok {
		return planDiscountStates, false, fmt.Errorf("plan discount not found for plan '%s'", customer.DiscountPlanName)
	}

	hasApplicableDiscount := false
	for _, planDiscount := range planDiscounts {
		var applicable bool
		for _, targetSku := range planDiscount.Targets {
			if targetSku == sku {
				applicable = true
				hasApplicableDiscount = true
				break
			}
		}
		if applicable {
			discountKey := models.NewDiscountKey(customer, planDiscount.Uuid)
			discountState, err := e.GetDiscountState(ctx, logger, discountKey, year, month)
			if err != nil {
				return planDiscountStates, false, err
			}

			planDiscountStates = append(planDiscountStates, discountState)

			// This is breaking the loop on the first occurence of !canProceed.
			// It's OK for now since we have a single plan discount per SKU, but we should revisit this if that changes.
			canProceed := (discountState == nil) || !discountState.IsFullyApplied
			if !canProceed {
				e.statter.Counter("can_proceed_with_usage.included_discounts_exceeded", stats.Tags{"customerId": customer.GetCustomerId()}, int64(1))
				return planDiscountStates, false, nil
			}
		}
	}

	if hasApplicableDiscount {
		return planDiscountStates, true, nil
	} else {
		return planDiscountStates, false, nil
	}
}

func (e *CustomerEngine) GetEnterpriseInfoFromItem(ctx context.Context, logger log.Logger, item *models.Item) (*models.EnterpriseInfo, error) {
	billingCustomer, parentCustomer, err := e.GetBillingAndParentCustomersFromItem(ctx, logger, item)
	if err != nil {
		return nil, err
	}

	if billingCustomer == nil {
		return nil, errors.New("customer not found")
	}

	if parentCustomer == nil {
		return nil, errors.New("enterprise customer not found")
	}

	return e.GetEnterpriseInfoFromBillingAndParentCustomers(ctx, logger, billingCustomer, parentCustomer), nil
}

func (e *CustomerEngine) GetEnterpriseInfoFromCustomerId(ctx context.Context, logger log.Logger, customerId string) (*models.EnterpriseInfo, *models.Customer, error) {
	billingCustomer, parentCustomer, err := e.GetBillingAndParentCustomersFromCustomerId(ctx, logger, customerId)
	if err != nil {
		return nil, nil, err
	}

	if billingCustomer == nil {
		return nil, nil, errors.New("customer not found")
	}

	if parentCustomer == nil {
		return nil, nil, errors.New("enterprise customer not found")
	}

	return e.GetEnterpriseInfoFromBillingAndParentCustomers(ctx, logger, billingCustomer, parentCustomer), parentCustomer, nil
}

func (e *CustomerEngine) GetBillingAndParentCustomersFromItem(ctx context.Context, logger log.Logger, item *models.Item) (*models.Customer, *models.Customer, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.GetBillingAndParentCustomersFromItem")
	defer sp.End()

	customerId := item.GetCustomerId()
	return e.GetBillingAndParentCustomersFromCustomerId(ctx, logger, customerId)
}

func (e *CustomerEngine) GetBillingAndParentCustomersFromCustomerId(ctx context.Context, logger log.Logger, customerId string) (*models.Customer, *models.Customer, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.GetBillingAndParentCustomersFromCustomerId")
	defer sp.End()

	billingCustomer, err := e.Get(ctx, logger, customerId)
	if err != nil {
		return nil, nil, err
	}

	if billingCustomer == nil {
		// The billing customer (or cost center proxy) is not found
		// Customer is not yet onboarded to vNext
		// return nil error. We shouldn't retry this event
		return nil, nil, nil
	}

	parentCustomer := billingCustomer
	if billingCustomer.IsCostCenterProxy {
		parentCustomer, err = e.Get(ctx, logger, billingCustomer.EnterpriseCustomerId)
		if err != nil {
			return nil, nil, err
		}

		if parentCustomer == nil {
			// The cost center is found but the parent customer is not found
			// Maybe the parent customer was somehow deleted. We shouldn't retry this event
			return nil, nil, nil
		}
	}

	return billingCustomer, parentCustomer, nil
}

func (e *CustomerEngine) GetEnterpriseInfoFromBillingAndParentCustomers(ctx context.Context, logger log.Logger, billingCustomer *models.Customer, parentCustomer *models.Customer) *models.EnterpriseInfo {
	_, sp := e.tracer.Start(ctx, "CustomerEngine.GetEnterpriseInfoFromBillingAndParentCustomers")
	defer sp.End()

	if billingCustomer == nil || parentCustomer == nil {
		return nil
	}

	enterpriseInfo := models.EnterpriseInfo{
		EnabledProducts:        billingCustomer.EnabledProducts,
		EnterpriseCustomerId:   billingCustomer.GetCustomerId(),
		DiscountPlanName:       billingCustomer.DiscountPlanName,
		AzureAccountId:         billingCustomer.AzureAccountId,
		BillingTarget:          billingCustomer.BillingTarget,
		BillForPublicRepoUsage: billingCustomer.BillForPublicRepoUsage,
		HasPaymentMethod:       billingCustomer.HasPaymentMethod,
		HasZuoraSubscription:   billingCustomer.HasZuoraSubscription,
		IsBillingLocked:        billingCustomer.IsBillingLocked,
		TradeScreening:         billingCustomer.TradeScreening,
		ZuoraAccountNumber:     billingCustomer.ZuoraAccountNumber,
	}

	if billingCustomer.IsCostCenterProxy {
		// cost centers can be created without a target ID (azure subscription ID in this case). If the cost center customer
		// record does not have an account account ID we should bill them with their parent enterprise's account ID.
		if enterpriseInfo.AzureAccountId == "" {
			enterpriseInfo.AzureAccountId = parentCustomer.AzureAccountId
		}

		if enterpriseInfo.ZuoraAccountNumber == "" {
			enterpriseInfo.ZuoraAccountNumber = parentCustomer.ZuoraAccountNumber
		}

		enterpriseInfo.EnabledProducts = parentCustomer.EnabledProducts
		enterpriseInfo.EnterpriseCustomerId = parentCustomer.GetCustomerId()
		enterpriseInfo.DiscountPlanName = parentCustomer.DiscountPlanName
		enterpriseInfo.BillForPublicRepoUsage = parentCustomer.BillForPublicRepoUsage
		// billingCustomer here is the cost center customer object
		enterpriseInfo.CostCenterUUID = billingCustomer.GetCustomerId()
	}

	return &enterpriseInfo
}

// TODO move to DB
func AllPlanDiscounts() map[string][]*models.PlanDiscount {
	// Reference for actions minutes and storage:
	// https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions#included-storage-and-minutes
	//
	// Complete list of Meuse entitlements for comparison:
	// https://meuse.githubapp.com/entitlements

	startDate := time.Date(2023, 6, 1, 0, 0, 0, 0, time.UTC)
	endDate := startDate.AddDate(9999, 0, 0) // _Never_ expire

	actionsStandardMinutes2KDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "e7000b30-6953-45d8-aef5-dffd4ca8a46f", // Randomly generated
		TargetAmount: 16,                                     // 2,000 minutes * 0.008 per minute
		Targets:      []string{"actions_linux", "actions_macos", "actions_windows"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	actionsStandardMinutes3KDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "e8cdc13b-0de4-45f2-afa9-6619209084e5", // Randomly generated
		TargetAmount: 24,                                     // 3,000 minutes * 0.008 per minute
		Targets:      []string{"actions_linux", "actions_macos", "actions_windows"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	actionsStandardMinutes50KDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "85679075-fe74-461e-9c22-808ac1393944", // Randomly generated
		TargetAmount: 400,                                    // 50,000 minutes * 0.008 per minute
		Targets:      []string{"actions_linux", "actions_macos", "actions_windows"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	actionsStandardMinutes100KDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "d5a8ca57-3f87-44aa-8cbd-74aa719a7433", // Randomly generated
		TargetAmount: 800,                                    // 100,000 minutes * 0.008 per minute
		Targets:      []string{"actions_linux", "actions_macos", "actions_windows"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	actionsStorage2GBDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "c36136bd-94b2-474e-b35e-495b8664463c", // Randomly generated
		TargetAmount: 0.5,                                    // 2GB * 0.25 per GB (rounded up from 2GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	actionsStorage500MBDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "a58e09c8-a68b-4d64-8b93-ff5c3f1fb4a8", // Randomly generated
		TargetAmount: 0.125,                                  // 0.5GB * 0.25 per GB (rounded up from 0.5GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	actionsStorage50GBDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "1596aea4-44d4-4939-98ba-4ea3bb4749cb", // Randomly generated
		TargetAmount: 12.5,                                   // 50GB * 0.25 per GB (rounded up from 50GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	actionsStorage100GBDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "65c1966e-68bc-48f0-a3e5-36e1afae7a84", // Randomly generated
		TargetAmount: 25,                                     // 100GB * 0.25 per GB (rounded up from 100GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	lfsStorage10GiBDiscount := &models.PlanDiscount{
		Uuid:         "5822bcda-3b9b-49b3-b004-4586d8b8c335", // Randomly generated
		TargetAmount: 0.7,                                    // 10GiB-month * 0.07 per GiB-month
		Targets:      []string{"git_lfs_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	lfsStorage250GiBDiscount := &models.PlanDiscount{
		Uuid:         "80688497-f2d5-4969-8550-c6265f7ef0b4", // Randomly generated
		TargetAmount: 17.5,                                   // 250GiB-month * 0.07 per GiB-month
		Targets:      []string{"git_lfs_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	lfsBandwidth10GiBDiscount := &models.PlanDiscount{
		Uuid:         "3adf99e7-cfcb-4060-8a55-3688f3160803", // Randomly generated
		TargetAmount: 0.875,                                  // 10GiB * 0.0875 per GiB
		Targets:      []string{"git_lfs_bandwidth"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	lfsBandwidth250GiBDiscount := &models.PlanDiscount{
		Uuid:         "dd97934f-1d5c-48c6-b821-22f98da6acfd", // Randomly generated
		TargetAmount: 21.875,                                 // 250GiB * 0.0875 per GiB
		Targets:      []string{"git_lfs_bandwidth"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	packagesStorage500MBDiscount := &models.PlanDiscount{
		Uuid:         "2fd4d08d-42be-4b7b-93c3-12f967498350", // Randomly generated
		TargetAmount: 0.125,                                  // 0.5GB-month * 0.25 per GB (rounded up from 0.5GB * 31 * 0.008 per GB)
		Targets:      []string{"packages_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	packagesStorage2GBDiscount := &models.PlanDiscount{
		Uuid:         "00245038-b1a0-420c-870c-8a1270978ca7", // Randomly generated
		TargetAmount: 0.5,                                    // 2GB-month * 0.25 per GB (rounded up from 2GB * 31 * 0.008 per GB)
		Targets:      []string{"packages_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	packagesStorage50GBDiscount := &models.PlanDiscount{
		Uuid:         "a819390d-5e3f-4023-b680-35866c547934", // Randomly generated
		TargetAmount: 12.5,                                   // 50GB-month * 0.25 per GB (rounded up from 50GB * 31 * 0.008 per GB)
		Targets:      []string{"packages_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	packagesBandwidth1GBDiscount := &models.PlanDiscount{
		Uuid:         "9302319d-70b2-4d6b-8d59-afb4deb1245c", // Randomly generated
		TargetAmount: 0.5,                                    // 1GB * 0.50 per GB
		Targets:      []string{"packages_bandwidth"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	packagesBandwidth10GBDiscount := &models.PlanDiscount{
		Uuid:         "29897fd5-2744-4a2b-9878-228f17075e94", // Randomly generated
		TargetAmount: 5,                                      // 10GB * 0.50 per GB
		Targets:      []string{"packages_bandwidth"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	packagesBandwidth100GBDiscount := &models.PlanDiscount{
		Uuid:         "ab1221a0-98e4-40a6-ba01-e4e5a19dff25", // Randomly generated
		TargetAmount: 50,                                     // 100GB * 0.50 per GB
		Targets:      []string{"packages_bandwidth"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	actionsPackagesCombinedStorage500MBDiscount := &models.PlanDiscount{
		Uuid:         "7d61fadd-c671-4639-a88a-32d9f8897884", // Randomly generated
		TargetAmount: 0.125,                                  // 2GB-month * 0.25 per GB (rounded up from 2GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage", "packages_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	actionsPackagesCombinedStorage2GBDiscount := &models.PlanDiscount{
		Uuid:         "f6e89a35-e672-4df5-b044-591f5e0d7535", // Randomly generated
		TargetAmount: 0.5,                                    // 2GB-month * 0.25 per GB (rounded up from 2GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage", "packages_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
	}

	planDiscounts := map[string][]*models.PlanDiscount{
		"free_user": {
			actionsStandardMinutes2KDiscount, // Meuse: 2,000 minutes
			actionsStorage500MBDiscount,      // Meuse: 0.5GB (380,928MB hour / 24 / 31 / 1024)
			lfsStorage10GiBDiscount,
			lfsBandwidth10GiBDiscount,
			packagesStorage500MBDiscount,
			packagesBandwidth1GBDiscount,
		},
		"pro": {
			actionsStandardMinutes3KDiscount, // Meuse: 3,000 minutes
			actionsStorage2GBDiscount,        // Meuse: 2GB (1,523,712MB hour / 24 / 31 / 1024)
			lfsStorage10GiBDiscount,
			lfsBandwidth10GiBDiscount,
			packagesStorage2GBDiscount,
			packagesBandwidth10GBDiscount,
		},
		"free_organization": {
			actionsStandardMinutes2KDiscount,            // Meuse: 2,000 minutes
			actionsPackagesCombinedStorage500MBDiscount, // Meuse: 0.5GB (380,928MB hour / 24 / 31 / 1024)
			packagesBandwidth1GBDiscount,
		},
		"team": {
			actionsStandardMinutes3KDiscount, // Meuse: 3,000 minutes
			lfsStorage250GiBDiscount,
			lfsBandwidth250GiBDiscount,
			packagesBandwidth10GBDiscount,
			// reference for combined usage discussion: https://github.com/github/gitcoin/issues/16448#issuecomment-2404171034
			actionsPackagesCombinedStorage2GBDiscount, // Meuse: 2GB (1,523,712MB hour / 24 / 31 / 1024)
		},
		"enterprise": {
			actionsStandardMinutes50KDiscount, // Meuse: 50,000 minutes
			actionsStorage50GBDiscount,        // Meuse: 50GB (38,092,800MB hour / 24 / 31 / 1024)
			lfsStorage250GiBDiscount,
			lfsBandwidth250GiBDiscount,
			packagesStorage50GBDiscount,
			packagesBandwidth100GBDiscount,
		},
		"enterprise_trial": {
			actionsStandardMinutes3KDiscount, // Meuse: 3,000 minutes
			actionsStorage50GBDiscount,       // Meuse: 50GB (38,092,800MB hour / 24 / 31 / 1024)
			lfsStorage250GiBDiscount,
			lfsBandwidth250GiBDiscount,
			packagesStorage50GBDiscount,
			packagesBandwidth100GBDiscount,
		},
		"education_essential": {
			actionsStandardMinutes50KDiscount, // Meuse: 50,000 minutes
			actionsStorage50GBDiscount,        // Meuse: 50GB (38,092,800MB hour / 24 / 31 / 1024)
			packagesStorage50GBDiscount,
			packagesBandwidth100GBDiscount,
		},
		"education_plus": {
			actionsStandardMinutes100KDiscount, // Meuse: 100,000 minutes
			actionsStorage100GBDiscount,        // Meuse: 100GB (76,185,600MB hour / 24 / 31 / 1024)
			packagesStorage50GBDiscount,
			packagesBandwidth100GBDiscount,
		},
	}
	return planDiscounts
}

func planDiscountContains(targets []string, sku string) bool {
	for _, value := range targets {
		if value == sku {
			return true
		}
	}
	return false
}
