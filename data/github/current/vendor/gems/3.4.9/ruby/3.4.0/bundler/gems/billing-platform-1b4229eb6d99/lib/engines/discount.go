package engines

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	repositories "github.com/github/monolith-twirp-billing/repositories/v1"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"
)

//go:generate pegomock generate -o ../../testing/fakes/mock_discount_engine.go --self_package=fakes --package=fakes DiscountEngineInterface
type DiscountEngineInterface interface {
	CalculateAmountExceedingDiscountState(ctx context.Context, logger log.Logger, customerID string, discount *models.Discount, amount, year, month int64) (int64, error)
	UpdateDiscountState(ctx context.Context, logger log.Logger, payload models.UpdateDiscountStatePayload) error
	GetDiscountState(ctx context.Context, logger log.Logger, discountKey *models.DiscountKey, year, month int64) (*models.DiscountState, error)
	CreateDiscount(ctx context.Context, logger log.Logger, discount *models.Discount) (*models.Discount, error)
	GetCachedRepositoryMetadata(ctx context.Context, logger log.Logger, repoId int64) (*models.Repo, error)
	CacheRepositoryMetadata(ctx context.Context, logger log.Logger, repo *repositories.Repository) error
	PublicRepoDiscountApplicable(ctx context.Context, logger log.Logger, customerId string, sku string, repoId int64, repositoryVisibility proto.RepositoryVisibility, billForPublicRepoUsage bool) (bool, error)
	GetLargestPlanDiscount(ctx context.Context, logger log.Logger, customerId string, item *models.Item, enterpriseInfo *models.EnterpriseInfo, now *models.UsageTime) (*models.Discount, error)
	GetLargestConfiguredDiscount(ctx context.Context, logger log.Logger, customerId string, item *models.Item, now *models.UsageTime) (*models.Discount, models.DiscountType, error)
	GetPlanDiscounts(ctx context.Context, logger log.Logger, item *models.Item, enterpriseInfo *models.EnterpriseInfo, tt models.DiscountTargetType, now *models.UsageTime) ([]*models.Discount, error)
	GetDiscount(ctx context.Context, logger log.Logger, key *proto.DiscountKey) (*models.Discount, error)
	DiscountIsInvalid(ctx context.Context, logger log.Logger, discount *models.Discount, discountState *models.DiscountState) bool
	GetAllDiscounts(ctx context.Context, logger log.Logger, customerId string) ([]*models.Discount, error)
	GetAllDiscountStates(ctx context.Context, logger log.Logger, customer *models.Customer, year, month int64) ([]*proto.DiscountState, error)
	CanProceedWithIncludedDiscounts(ctx context.Context, logger log.Logger, customer *models.Customer, sku string, year, month int64) ([]*models.DiscountState, bool, error)
	GetOrInitDiscountState(ctx context.Context, logger log.Logger, customerID string, discountKey *models.DiscountKey, discount *models.Discount, year, month int64) (*models.DiscountState, error)
	FindLargestDiscount(ctx context.Context, logger log.Logger, discounts []*models.Discount, customerId string, billedAmount int64, now *models.UsageTime) (*models.Discount, models.DiscountType, error)
	GetPlanDiscountStates(ctx context.Context, logger log.Logger, customer *models.Customer) ([]*models.DiscountState, error)
	UpsertDiscountState(ctx context.Context, logger log.Logger, discountState *models.DiscountState) error
	GetDailyDiscountQuantity(ctx context.Context, logger log.Logger, item *models.Item) (float64, error)
	GetDiscountTotal(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) (*models.DiscountAmounts, bool, error)
}

type DiscountEngine struct {
	*EngineParams
	pricingEngine       PricingEngineInterface
	subscriptionsEngine *SubscriptionsEngine
}

func NewDiscountEngine(params *EngineParams, pricingEngine PricingEngineInterface, subscriptionsEngine *SubscriptionsEngine) DiscountEngineInterface {
	return &DiscountEngine{
		EngineParams:        params,
		pricingEngine:       pricingEngine,
		subscriptionsEngine: subscriptionsEngine,
	}
}

func (e *DiscountEngine) CalculateAmountExceedingDiscountState(ctx context.Context, logger log.Logger, customerID string, discount *models.Discount, amount, year, month int64) (int64, error) {
	ctx, sp := e.tracer.Start(ctx, "DiscountEngine.CalculateAmountExceedingDiscountState")
	defer sp.End()

	customer := models.NewCustomer(customerID)
	discountKey := models.NewDiscountKey(customer, discount.Uuid)
	discountState, err := e.GetOrInitDiscountState(ctx, logger, customerID, discountKey, discount, year, month)
	if err != nil {
		return 0, err
	}

	if e.DiscountIsInvalid(ctx, logger, discount, discountState) {
		e.statter.Counter("invalid-discount", stats.Tags{}, int64(1))
		logger.Debug("invalid discount details", kvp.String("discount", discount.Uuid), kvp.String("customer", customerID), kvp.String("discountId", discount.Id))
		return 0, nil
	}

	if discountState.IsFullyApplied {
		logger.Debug("discount fully applied", kvp.String("discount", discount.Uuid), kvp.String("customer", customerID), kvp.String("discountId", discount.Id))
		return 0, nil
	}

	// percentage discounts are never fully applied so the input discount amount will not exceed the target amount
	if discount.IsPercentage() {
		return 0, nil
	}

	var amountExceedingDiscountState int64

	newAmount := discountState.CurrentAmount + amount
	if newAmount >= discountState.TargetAmount {
		amountExceedingDiscountState = newAmount - discountState.TargetAmount
	}

	return amountExceedingDiscountState, nil
}

func (e *DiscountEngine) UpdateDiscountState(ctx context.Context, logger log.Logger, payload models.UpdateDiscountStatePayload) error {
	customer := models.NewCustomer(payload.CustomerId)
	discountKey := models.NewDiscountKey(customer, payload.Discount.Uuid)
	discountState, err := e.GetOrInitDiscountState(ctx, logger, payload.CustomerId, discountKey, payload.Discount, payload.Year, payload.Month)
	if err != nil {
		return err
	}

	isPercentageDiscount := payload.Discount.IsPercentage()

	discountStateOverageAmount := int64(0)
	// over applied discounts are possible when the updated discount amount(current amount + the incoming payload amount) exceeds the target amount
	if discountState.CurrentAmount+payload.Amount > discountState.TargetAmount {
		discountStateOverageAmount = discountState.CurrentAmount + payload.Amount - discountState.TargetAmount
	}

	if discountState.IsNewDocument() {
		discountState.CurrentAmount = payload.Amount

		// this likely won't happen but if the first update to the discount state is >= to the target amount, we should mark it as fully applied
		if discountState.CurrentAmount >= discountState.TargetAmount && !isPercentageDiscount {
			discountState.IsFullyApplied = true
		}

		err := e.db.CreateWithOptions(ctx, logger, discountState, nil)
		if err != nil {
			return err
		}
	} else {
		po := azcosmos.PatchOperations{}
		po.AppendIncrement("/CurrentAmount", payload.Amount)

		if (discountState.CurrentAmount+payload.Amount >= discountState.TargetAmount) && !discountState.IsFullyApplied && !isPercentageDiscount {
			po.AppendReplace("/IsFullyApplied", true)
		}

		err := e.db.PatchWithOptions(ctx, logger, discountState, po, nil)
		if err != nil {
			return err
		}
	}

	e.statter.Counter("discount.state.overage_amount", stats.Tags{}, discountStateOverageAmount)

	return nil
}

func (e *DiscountEngine) GetDiscountState(ctx context.Context, logger log.Logger, discountKey *models.DiscountKey, year, month int64) (*models.DiscountState, error) {
	discountStateKey := discountKey.ToDiscountStateKey(year, month)
	discountState, err := db.NewQuerier[*models.DiscountState](e.db).ReadItemWithRetries(ctx, logger, discountStateKey)
	if err != nil {
		return nil, err
	}

	return discountState, nil
}

func (e *DiscountEngine) GetPlanDiscountStates(ctx context.Context, logger log.Logger, customer *models.Customer) ([]*models.DiscountState, error) {
	logger.Info("GetPlanDiscountStates", kvp.String("gh.customer.id", customer.EnterpriseCustomerId), kvp.String("gh.customer.discount.plan.name", customer.DiscountPlanName))
	planDiscounts := AllPlanDiscounts()[customer.DiscountPlanName]

	errs, gctx := errgroup.WithContext(ctx)
	var discountStateMutex = &sync.Mutex{}
	var discountStates []*models.DiscountState

	// Get each plan discount state, if applicable
	for _, planDiscount := range planDiscounts {
		errs.Go(func() error {
			discountKey := models.NewDiscountKey(customer, planDiscount.Uuid)
			discountState, err := e.GetDiscountState(gctx, logger, discountKey, int64(models.UTCNow().Year()), int64(models.UTCNow().Month()))
			logger.Info("Searching for discount", kvp.String("gh.customer.id", discountKey.CustomerId), kvp.String("gh.customer.discount.key.product", discountKey.GetProductFromPartitionKey()), kvp.String("planDiscount.Uuid", planDiscount.Uuid))
			if err != nil {
				return err
			}
			if discountState != nil {
				// append to shared slice is not thread safe so we need to lock
				discountStateMutex.Lock()
				discountStates = append(discountStates, discountState)
				discountStateMutex.Unlock()
			}
			return nil
		})
	}

	if err := errs.Wait(); err != nil {
		return nil, errors.Wrap(err, "unable to get plan discount states")
	}

	return discountStates, nil
}

type DiscountSearch struct {
	context                  context.Context
	discountQuerier          *db.Querier[*models.Discount]
	lookupQuerier            *db.Querier[*models.DiscountTargetLookup]
	customer                 *models.Customer
	item                     *models.Item
	foundPercentageDiscounts []*models.Discount
	foundDollarDiscounts     []*models.Discount
}

func (e *DiscountEngine) NewDiscountSearch(ctx context.Context, customerID string, item *models.Item) *DiscountSearch {
	return &DiscountSearch{
		context:                  ctx,
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

func (e *DiscountEngine) CreateDiscount(ctx context.Context, logger log.Logger, discount *models.Discount) (*models.Discount, error) {
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

func (e *DiscountEngine) GetCachedRepositoryMetadata(ctx context.Context, logger log.Logger, repoId int64) (*models.Repo, error) {
	return db.NewQuerier[*models.Repo](e.db).ReadItemWithRetries(ctx, logger, models.NewRepoKey(repoId))
}

func (e *DiscountEngine) UpsertDiscountState(ctx context.Context, logger log.Logger, discountState *models.DiscountState) error {
	return e.db.UpsertWithOptions(ctx, logger, discountState, nil)
}

func (e *DiscountEngine) CacheRepositoryMetadata(ctx context.Context, logger log.Logger, repo *repositories.Repository) error {
	return e.db.UpsertWithOptions(ctx, logger, models.NewRepo(int64(repo.Id), repo.IsPublic), nil)
}

func (e *DiscountEngine) PublicRepoDiscountApplicable(ctx context.Context, logger log.Logger, customerId string, sku string, repoId int64, repositoryVisibility proto.RepositoryVisibility, billForPublicRepoUsage bool) (bool, error) {
	logger = logger.WithFields(kvp.String("customerId", customerId), kvp.String("sku", sku), kvp.Int64("repoId", repoId))

	if billForPublicRepoUsage {
		return false, nil
	}

	pricing := e.pricingEngine.GetCurrentPricing(ctx, logger, &models.PricingSelectionData{ProductSku: sku})
	if pricing == nil {
		logger.Info("pricing not found")
		return false, nil
	}

	return repositoryVisibility == proto.RepositoryVisibility_PUBLIC && pricing.GetFreeForPublicRepos(), nil
}

func (e *DiscountEngine) GetLargestPlanDiscount(ctx context.Context, logger log.Logger, customerId string, item *models.Item, enterpriseInfo *models.EnterpriseInfo, now *models.UsageTime) (*models.Discount, error) {
	planDiscounts, err := e.GetPlanDiscounts(ctx, logger, item, enterpriseInfo, models.SkuDiscount, now)
	if err != nil {
		return &models.Discount{}, err
	}

	result, _, err := e.FindLargestDiscount(ctx, logger, planDiscounts, customerId, item.BilledAmount, now)

	return result, err
}

// Of all applicable discounts, we will apply the largest to the usage based on the derived amount.
// Dollar discounts are straight forward - find the largest value and apply it.
// For percent discounts we will calculate the "amount" of the discount based on the percentage against the line item, and compare this to all other discounts.
// See https://github.com/github/gitcoin/issues/11952 for more context.
func (e *DiscountEngine) GetLargestConfiguredDiscount(ctx context.Context, logger log.Logger, customerId string, item *models.Item, now *models.UsageTime) (*models.Discount, models.DiscountType, error) {
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

	return e.FindLargestDiscount(ctx, logger, availableDiscounts, customerId, item.BilledAmount, now)
}

func (e *DiscountEngine) GetPlanDiscounts(ctx context.Context, logger log.Logger, item *models.Item, enterpriseInfo *models.EnterpriseInfo, tt models.DiscountTargetType, now *models.UsageTime) ([]*models.Discount, error) {
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

func (e *DiscountEngine) GetDiscount(ctx context.Context, logger log.Logger, key *proto.DiscountKey) (*models.Discount, error) {
	discountKey := models.NewDiscountKeyFromProto(key)

	discount, err := db.NewQuerier[*models.Discount](e.db).ReadItemWithRetries(ctx, logger, discountKey)
	if err != nil {
		return nil, err
	}

	return discount, nil
}

func (e *DiscountEngine) DiscountIsInvalid(ctx context.Context, logger log.Logger, discount *models.Discount, discountState *models.DiscountState) bool {
	now := models.UTCNow()
	return !discount.IsValidFor(now) && discountState.IsFullyApplied
}

func (e *DiscountEngine) GetAllDiscounts(ctx context.Context, logger log.Logger, customerId string) ([]*models.Discount, error) {
	discountsKey := models.CustomerIdToDiscountsPartitionKey(customerId)

	queryStringAllDiscounts := "SELECT * FROM c WHERE NOT IS_DEFINED(c.Uuids)"
	discounts, err := db.NewQuerier[*models.Discount](e.db).QueryItems(ctx, logger, queryStringAllDiscounts, discountsKey)
	if err != nil {
		return nil, err
	}

	return discounts, nil
}

func (e *DiscountEngine) GetAllDiscountStates(ctx context.Context, logger log.Logger, customer *models.Customer, year, month int64) ([]*proto.DiscountState, error) {
	var discountStates []*proto.DiscountState = []*proto.DiscountState{}

	if customer == nil {
		return discountStates, nil
	}

	discountsKey := models.CustomerIdToDiscountsPartitionKey(customer.GetCustomerId())

	queryStringAllDiscounts := "SELECT * FROM c WHERE NOT IS_DEFINED(c.Uuids)"
	discounts, err := db.NewQuerier[*models.Discount](e.db).QueryItems(ctx, logger, queryStringAllDiscounts, discountsKey)
	if err != nil {
		return nil, err
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

func (e *DiscountEngine) CanProceedWithIncludedDiscounts(ctx context.Context, logger log.Logger, customer *models.Customer, sku string, year, month int64) ([]*models.DiscountState, bool, error) {
	ctx, sp := e.tracer.Start(ctx, "DiscountEngine.CanProceedWithIncludedDiscounts")
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
		Targets:      []string{"actions_linux", "actions_macos", "actions_windows", "actions_linux_arm", "actions_windows_arm"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.ActionsMinutes,
	}

	actionsStandardMinutes3KDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "e8cdc13b-0de4-45f2-afa9-6619209084e5", // Randomly generated
		TargetAmount: 24,                                     // 3,000 minutes * 0.008 per minute
		Targets:      []string{"actions_linux", "actions_macos", "actions_windows", "actions_linux_arm", "actions_windows_arm"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.ActionsMinutes,
	}

	actionsStandardMinutes50KDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "85679075-fe74-461e-9c22-808ac1393944", // Randomly generated
		TargetAmount: 400,                                    // 50,000 minutes * 0.008 per minute
		Targets:      []string{"actions_linux", "actions_macos", "actions_windows", "actions_linux_arm", "actions_windows_arm"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.ActionsMinutes,
	}

	actionsStandardMinutes100KDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "d5a8ca57-3f87-44aa-8cbd-74aa719a7433", // Randomly generated
		TargetAmount: 800,                                    // 100,000 minutes * 0.008 per minute
		Targets:      []string{"actions_linux", "actions_macos", "actions_windows", "actions_linux_arm", "actions_windows_arm"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.ActionsMinutes,
	}

	actionsStorage2GBDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "c36136bd-94b2-474e-b35e-495b8664463c", // Randomly generated
		TargetAmount: 0.5,                                    // 2GB * 0.25 per GB (rounded up from 2GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.ActionsStorage,
	}

	actionsStorage500MBDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "a58e09c8-a68b-4d64-8b93-ff5c3f1fb4a8", // Randomly generated
		TargetAmount: 0.125,                                  // 0.5GB * 0.25 per GB (rounded up from 0.5GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.ActionsStorage,
	}

	actionsStorage50GBDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "1596aea4-44d4-4939-98ba-4ea3bb4749cb", // Randomly generated
		TargetAmount: 12.5,                                   // 50GB * 0.25 per GB (rounded up from 50GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.ActionsStorage,
	}

	actionsStorage100GBDiscount := &models.PlanDiscount{
		// NOTE: be sure to reuse the same UUID when moving to the DB to honor existing discounts
		Uuid:         "65c1966e-68bc-48f0-a3e5-36e1afae7a84", // Randomly generated
		TargetAmount: 25,                                     // 100GB * 0.25 per GB (rounded up from 100GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.ActionsStorage,
	}

	lfsStorage10GiBDiscount := &models.PlanDiscount{
		Uuid:         "5822bcda-3b9b-49b3-b004-4586d8b8c335", // Randomly generated
		TargetAmount: 0.7,                                    // 10GiB-month * 0.07 per GiB-month
		Targets:      []string{"git_lfs_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.LfsStorage,
	}

	lfsStorage250GiBDiscount := &models.PlanDiscount{
		Uuid:         "80688497-f2d5-4969-8550-c6265f7ef0b4", // Randomly generated
		TargetAmount: 17.5,                                   // 250GiB-month * 0.07 per GiB-month
		Targets:      []string{"git_lfs_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.LfsStorage,
	}

	lfsBandwidth10GiBDiscount := &models.PlanDiscount{
		Uuid:         "3adf99e7-cfcb-4060-8a55-3688f3160803", // Randomly generated
		TargetAmount: 0.875,                                  // 10GiB * 0.0875 per GiB
		Targets:      []string{"git_lfs_bandwidth"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.LfsBandwidth,
	}

	lfsBandwidth250GiBDiscount := &models.PlanDiscount{
		Uuid:         "dd97934f-1d5c-48c6-b821-22f98da6acfd", // Randomly generated
		TargetAmount: 21.875,                                 // 250GiB * 0.0875 per GiB
		Targets:      []string{"git_lfs_bandwidth"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.LfsBandwidth,
	}

	packagesStorage500MBDiscount := &models.PlanDiscount{
		Uuid:         "2fd4d08d-42be-4b7b-93c3-12f967498350", // Randomly generated
		TargetAmount: 0.125,                                  // 0.5GB-month * 0.25 per GB (rounded up from 0.5GB * 31 * 0.008 per GB)
		Targets:      []string{"packages_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.PackagesStorage,
	}

	packagesStorage2GBDiscount := &models.PlanDiscount{
		Uuid:         "00245038-b1a0-420c-870c-8a1270978ca7", // Randomly generated
		TargetAmount: 0.5,                                    // 2GB-month * 0.25 per GB (rounded up from 2GB * 31 * 0.008 per GB)
		Targets:      []string{"packages_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.PackagesStorage,
	}

	packagesStorage50GBDiscount := &models.PlanDiscount{
		Uuid:         "a819390d-5e3f-4023-b680-35866c547934", // Randomly generated
		TargetAmount: 12.5,                                   // 50GB-month * 0.25 per GB (rounded up from 50GB * 31 * 0.008 per GB)
		Targets:      []string{"packages_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.PackagesStorage,
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
		Type:         models.PackagesBandwidth,
	}

	packagesBandwidth100GBDiscount := &models.PlanDiscount{
		Uuid:         "ab1221a0-98e4-40a6-ba01-e4e5a19dff25", // Randomly generated
		TargetAmount: 50,                                     // 100GB * 0.50 per GB
		Targets:      []string{"packages_bandwidth"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.PackagesBandwidth,
	}

	actionsPackagesCombinedStorage500MBDiscount := &models.PlanDiscount{
		Uuid:         "7d61fadd-c671-4639-a88a-32d9f8897884", // Randomly generated
		TargetAmount: 0.125,                                  // 2GB-month * 0.25 per GB (rounded up from 2GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage", "packages_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.SharedStorage,
	}

	actionsPackagesCombinedStorage2GBDiscount := &models.PlanDiscount{
		Uuid:         "f6e89a35-e672-4df5-b044-591f5e0d7535", // Randomly generated
		TargetAmount: 0.5,                                    // 2GB-month * 0.25 per GB (rounded up from 2GB * 31 * 0.008 per GB)
		Targets:      []string{"actions_storage", "packages_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.SharedStorage,
	}

	codespacesFreeStorage15GBDiscount := &models.PlanDiscount{
		Uuid:         "e3b0c442-98fc-1c14-9ddf-4b8fba1d4c8e", // Randomly generated
		TargetAmount: 1.05,                                   // 15GB-month * .07 per GB-month
		Targets:      []string{"codespaces_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.CodespacesStorage,
	}

	codespacesProStorage20GBDiscount := &models.PlanDiscount{
		Uuid:         "d4e5f6a7-b8c9-0d1e-2f3a-4b5c6d7e8f9a", // Randomly generated
		TargetAmount: 1.4,                                    // 20GB-month  * .07 per GB-month
		Targets:      []string{"codespaces_storage"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.CodespacesStorage,
	}

	codespacesFree120ComputeHoursDiscount := &models.PlanDiscount{
		Uuid:         "a1b2c3d4-e5f6-7a8b-9c0d-e1f2a3b4c5d6", // Randomly generated
		TargetAmount: 10.8,                                   // 120 codespaces core-hours * .09 per core hour
		Targets:      []string{"codespaces_compute_d2", "codespaces_compute_d4", "codespaces_compute_d8", "codespaces_compute_d16", "codespaces_compute_d32"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.CodespacesCompute,
	}

	codespacesPro180ComputeHoursDiscount := &models.PlanDiscount{
		Uuid:         "1a2b3c4d-5e6f-7a8b-9c0d-e1f2a3b4c5d6", // Randomly generated
		TargetAmount: 16.2,                                   // 180 codespaces core-hours * .09 per core hour
		Targets:      []string{"codespaces_compute_d2", "codespaces_compute_d4", "codespaces_compute_d8", "codespaces_compute_d16", "codespaces_compute_d32"},
		StartDate:    startDate.Unix(),
		EndDate:      endDate.Unix(),
		Type:         models.CodespacesCompute,
	}

	planDiscounts := map[string][]*models.PlanDiscount{
		"free_user": {
			actionsStandardMinutes2KDiscount, // Meuse: 2,000 minutes
			actionsStorage500MBDiscount,      // Meuse: 0.5GB (380,928MB hour / 24 / 31 / 1024)
			lfsStorage10GiBDiscount,
			lfsBandwidth10GiBDiscount,
			packagesStorage500MBDiscount,
			packagesBandwidth1GBDiscount,
			codespacesFreeStorage15GBDiscount,
			codespacesFree120ComputeHoursDiscount,
		},
		"pro": {
			actionsStandardMinutes3KDiscount, // Meuse: 3,000 minutes
			actionsStorage2GBDiscount,        // Meuse: 2GB (1,523,712MB hour / 24 / 31 / 1024)
			lfsStorage10GiBDiscount,
			lfsBandwidth10GiBDiscount,
			packagesStorage2GBDiscount,
			packagesBandwidth10GBDiscount,
			codespacesProStorage20GBDiscount,
			codespacesPro180ComputeHoursDiscount,
		},
		"free_organization": {
			actionsStandardMinutes2KDiscount,            // Meuse: 2,000 minutes
			actionsPackagesCombinedStorage500MBDiscount, // Meuse: 0.5GB (380,928MB hour / 24 / 31 / 1024)
			packagesBandwidth1GBDiscount,
			lfsStorage10GiBDiscount,
			lfsBandwidth10GiBDiscount,
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

func (e *DiscountEngine) GetOrInitDiscountState(ctx context.Context, logger log.Logger, customerID string, discountKey *models.DiscountKey, discount *models.Discount, year, month int64) (*models.DiscountState, error) {
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

func (e *DiscountEngine) FindLargestDiscount(ctx context.Context, logger log.Logger, discounts []*models.Discount, customerId string, billedAmount int64, now *models.UsageTime) (*models.Discount, models.DiscountType, error) {
	year := int64(now.Year())
	month := int64(now.Month())
	customer := models.NewCustomer(customerId)

	var result models.Discount
	var associatedDiscountState models.DiscountState
	discountType := models.NoDiscountType

	for _, discount := range discounts {
		discountKey := models.NewDiscountKey(customer, discount.Uuid)
		discountState, err := e.GetOrInitDiscountState(ctx, logger, customerId, discountKey, discount, year, month)
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

func (h *DiscountEngine) GetDailyDiscountQuantity(ctx context.Context, logger log.Logger, item *models.Item) (float64, error) {
	if item.IsHighWatermarkEvent() {
		result, err := h.subscriptionsEngine.GetHighWatermarkEvent(
			ctx, logger,
			item.GetCustomerId(),
			item.GetSku(),
			item.UsageAt,
		)
		if err != nil {
			return 0.0, err
		}
		if result == nil {
			return 0.0, nil
		}
		return nano.ToDecimalAmount[int64](result.DailyDiscountQuantity), nil
	}

	partitionDetail, err := models.GetPartitionDetailForItemDiscountLookup(item)
	if err != nil {
		return 0, err
	}

	// get discount items
	discountTotals, _, err := h.GetDiscountTotal(ctx, logger, partitionDetail)
	if err != nil {
		return 0, err
	}

	discountQuantity := discountTotals.ToDecimal().Quantity

	// We need to convert from per Hour to per Month for Azure if the meter type is per hour (watermark).
	if item.GetMeterType() == models.PricingMeterPerHourUnitCharge {
		daysInMonth := int64(item.UsageAt.BillableDaysInMonth()) * nano.NanoDivisor
		hoursInDay := int64(24) * nano.NanoDivisor
		convertedDiscountQuantity := nano.NewFromFloat(discountQuantity).Div(nano.NewFromInt(hoursInDay)).Div(nano.NewFromInt(daysInMonth))
		discountQuantity = nano.ToDecimalAmount[int64](convertedDiscountQuantity.Int64())
	}

	logger.Info("Found discount quantity", kvp.Float64("discountQuantity", discountQuantity))

	if discountQuantity < 0 {
		h.statter.Counter("azure-emission-negative-discount", stats.Tags{}, int64(1))
	}

	return discountQuantity, nil
}

func (u *DiscountEngine) GetDiscountTotal(ctx context.Context, logger log.Logger, upd *models.UsagePartitionDetail) (*models.DiscountAmounts, bool, error) {
	pk := models.GetDiscountPartitionKey(upd.ToPartitionKey())

	amounts, hitCache, err := getOrCreateAndCacheUsageTotalForPartitionKey(ctx, logger, pk, u.db, u.db.GetDiscountTotals)
	discountAmounts := &models.DiscountAmounts{
		DiscountAmount:         amounts.BilledAmount,
		Quantity:               amounts.Quantity,
		AppliedCostPerQuantity: amounts.AppliedCostPerQuantity,
	}

	return discountAmounts, hitCache, err
}
