package api

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/services"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/trace"
)

type CustomerApi struct {
	customerEngine   engines.CustomerEngineInterface
	discountEngine   engines.DiscountEngineInterface
	pricingEngine    engines.PricingEngineInterface
	costCenterEngine engines.CostCenterEngineInterface
	budgetEngine     engines.BudgetEngineInterface
	customerService  services.CustomerServiceInterface
	logger           log.Logger
	statter          stats.Client
	tracer           trace.Tracer
	flagger          *vexi.Client
}

func NewCustomerAPI(customerEngine engines.CustomerEngineInterface, discountEngine engines.DiscountEngineInterface, pricingEngine engines.PricingEngineInterface, costCenterEngine engines.CostCenterEngineInterface, budgetEngine engines.BudgetEngineInterface, customerService services.CustomerServiceInterface, logger log.Logger, statter stats.Client, tracer trace.Tracer, flagger *vexi.Client) *CustomerApi {
	return &CustomerApi{
		customerEngine:   customerEngine,
		discountEngine:   discountEngine,
		pricingEngine:    pricingEngine,
		costCenterEngine: costCenterEngine,
		budgetEngine:     budgetEngine,
		customerService:  customerService,
		logger:           logger.Named("CustomerApi"),
		statter:          statter,
		tracer:           tracer,
		flagger:          flagger,
	}
}

func (api *CustomerApi) GetDiscount(ctx context.Context, request *proto.GetDiscountRequest) (*proto.GetDiscountResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}

	if request.Key == nil {
		return nil, twirp.RequiredArgumentError("key")
	}

	if request.Key.CustomerId == "" {
		return nil, twirp.InvalidArgumentError("key.customerId", "must be present")
	}

	if request.Key.Uuid == "" {
		return nil, twirp.InvalidArgumentError("key.uuid", "must be present")
	}

	discount, err := api.discountEngine.GetDiscount(ctx, api.logger, request.Key)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.GetDiscountResponse{
		Discount: discount.ToProto(),
	}, nil
}

func (api *CustomerApi) GetAllDiscounts(ctx context.Context, request *proto.GetAllDiscountsRequest) (*proto.GetAllDiscountsResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}

	if request.CustomerId == "" {
		return nil, twirp.RequiredArgumentError("customerId")
	}

	discounts, err := api.discountEngine.GetAllDiscounts(ctx, api.logger, request.CustomerId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	var discountsProto []*proto.Discount
	for _, discount := range discounts {
		discountsProto = append(discountsProto, discount.ToProto())
	}

	return &proto.GetAllDiscountsResponse{
		Discounts: discountsProto,
	}, nil
}

func (api *CustomerApi) GetAllDiscountStates(ctx context.Context, request *proto.GetAllDiscountStatesRequest) (*proto.GetAllDiscountStatesResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}

	if request.CustomerId == "" {
		return nil, twirp.RequiredArgumentError("customerId")
	}

	if request.Month < 1 || request.Month > 12 {
		return nil, twirp.InvalidArgumentError("month", "Month must be between 1 and 12")
	}

	if request.Year <= 0 {
		return nil, twirp.InvalidArgumentError("year", "Year must be above 0")
	}

	customer, err := api.customerEngine.Get(ctx, api.logger, request.CustomerId, false)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}
	if customer == nil {
		return &proto.GetAllDiscountStatesResponse{
			Discounts: []*proto.DiscountState{},
		}, nil
	}

	discountStates, err := api.discountEngine.GetAllDiscountStates(ctx, api.logger, customer, request.Year, request.Month)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.GetAllDiscountStatesResponse{
		Discounts: discountStates,
	}, nil
}

func (api *CustomerApi) CreateDiscount(ctx context.Context, request *proto.CreateDiscountRequest) (*proto.CreateDiscountResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}

	if request.Discount == nil {
		return nil, twirp.RequiredArgumentError("discount")
	}

	percentage := request.Discount.Percentage
	targetAmount := request.Discount.TargetAmount

	if percentage == 0 && targetAmount == 0 {
		return nil, twirp.InvalidArgumentError("percentage|targetAmount", "either percentage or targetAmount must be > 0")
	}

	switch {
	case targetAmount > 0:
		percentage = 0
	case targetAmount < 0:
		return nil, twirp.InvalidArgumentError("targetAmount", "must be > 0")
	case targetAmount == 0 && percentage != 0:
		if percentage < 0 || percentage > 100 {
			return nil, twirp.InvalidArgumentError("percentage", "must be between 0 and 100")
		}
	}

	now := models.UTCNow().StartOfDay().Unix()
	startDate := models.NewUsageTimeFromProto(request.Discount.StartDate).StartOfDay().Unix()
	endDate := models.NewUsageTimeFromProto(request.Discount.EndDate).StartOfDay().Unix()

	if endDate < now {
		return nil, twirp.InvalidArgumentError("endDate", "must be in greater than or equal to today's date")
	}

	if startDate > endDate {
		return nil, twirp.InvalidArgumentError("startDate", "must be less than or equal to endDate")
	}

	discount := models.NewDiscount(request.Discount.CustomerId, request.Discount.Targets, percentage, targetAmount, startDate, endDate)
	_, err := api.discountEngine.CreateDiscount(ctx, api.logger, discount)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.CreateDiscountResponse{
		Uuid: discount.Uuid,
	}, nil
}

func (api *CustomerApi) GetDiscountState(ctx context.Context, request *proto.GetDiscountStateRequest) (*proto.GetDiscountStateResponse, error) {
	discountKey := models.NewDiscountKeyFromProto(request.Key)
	discountState, err := api.discountEngine.GetDiscountState(ctx, api.logger, discountKey, request.Year, request.Month)
	if err != nil {
		return nil, err
	}

	if discountState == nil {
		return &proto.GetDiscountStateResponse{}, nil
	}

	return &proto.GetDiscountStateResponse{
		DiscountState: discountState.ToProto(),
	}, nil
}

func (api *CustomerApi) CanProceedWithUsage(ctx context.Context, request *proto.CanProceedWithUsageRequest) (*proto.CanProceedWithUsageResponse, error) {
	ctx, sp := api.tracer.Start(ctx, "CustomerApi.CanProceedWithUsage")
	defer sp.End()

	statsKey := "can_proceed_with_usage"

	if request.UsageKey == nil {
		api.statter.Counter(fmt.Sprintf("%s.error", statsKey), stats.Tags{"error": "usage_key_is_nil"}, int64(1))
		return nil, twirp.RequiredArgumentError("usageKey")
	}
	usageKey := request.UsageKey
	if usageKey.EntityDetail == nil {
		api.statter.Counter(fmt.Sprintf("%s.error", statsKey), stats.Tags{"error": "entity_detail_is_nil"}, int64(1))
		return nil, twirp.RequiredArgumentError("entityDetail")
	}

	now := models.UTCNow()
	if usageKey.UsageAt != 0 {
		now = models.NewUsageTimeFromProto(usageKey.UsageAt)
	}
	year := int64(now.Year())
	month := int64(now.Month())

	customer, err := api.customerEngine.Get(ctx, api.logger, usageKey.EntityDetail.CustomerId, true)
	if err != nil {
		api.statter.Counter(fmt.Sprintf("%s.error", statsKey), stats.Tags{"error": "failed_to_get_customer"}, int64(1))
		api.logger.WithError(err).Error("Failed to get customer in CanProceedWithUsage", kvp.String("customerId", usageKey.EntityDetail.CustomerId))
		return nil, twirp.InternalErrorWith(err)
	}

	if customer == nil {
		api.statter.Counter(fmt.Sprintf("%s.error", statsKey), stats.Tags{"error": "customer_not_found"}, int64(1))
		api.logger.Error("Customer not found in CanProceedWithUsage", kvp.String("customerId", usageKey.EntityDetail.CustomerId))
		return nil, twirp.NotFoundError(fmt.Sprintf("Customer with id %s not found", usageKey.EntityDetail.CustomerId))
	}

	if !customer.HasProductEnabled(usageKey.Product) {
		return api.buildAndLogCanProceedWithUsageResponse(
			false, models.ProductNotEnabled.ToProto(), nil, nil, usageKey, customer.DiscountPlanName, statsKey,
		), nil
	}

	if customer.IsBillingLocked {
		return api.buildAndLogCanProceedWithUsageResponse(
			false, models.BillingLocked.ToProto(), nil, nil, usageKey, customer.DiscountPlanName, statsKey,
		), nil
	}

	if customer.HasFullTradeRestrictions() {
		return api.buildAndLogCanProceedWithUsageResponse(
			false, models.FullTradeRestrictionsApplied.ToProto(), nil, nil, usageKey, customer.DiscountPlanName, statsKey,
		), nil
	}

	if customer.HasAnyTradeRestrictions() {
		return api.buildAndLogCanProceedWithUsageResponse(
			false, models.AnyTradeRestrictionsApplied.ToProto(), nil, nil, usageKey, customer.DiscountPlanName, statsKey,
		), nil
	}

	if customer.HasCommercialInteractionRestriction(usageKey.Product) {
		return api.buildAndLogCanProceedWithUsageResponse(
			false, models.CommercialInteractionRestrictionApplied.ToProto(), nil, nil, usageKey, customer.DiscountPlanName, statsKey,
		), nil
	}

	isFreeSkuFeatureFlagEnabled := api.flagger.IsEnabledWithDefaultValue(ctx, featureflags.FreeSkuCheckEnabled, false, models.CustomerVexiActor(usageKey.EntityDetail.CustomerId))
	if isFreeSkuFeatureFlagEnabled && api.isFreeSku(ctx, usageKey.Sku) {
		return api.buildAndLogCanProceedWithUsageResponse(
			true, models.UsageAllowed.ToProto(), nil, nil, usageKey, customer.DiscountPlanName, statsKey,
		), nil
	}

	entityDetail := models.NewEntityDetail(usageKey.EntityDetail)
	costCenterKey, err := api.costCenterEngine.FindCostCenterFor(ctx, api.logger, entityDetail, usageKey.Sku)
	if err != nil {
		api.statter.Counter(fmt.Sprintf("%s.error", statsKey), stats.Tags{"error": "failed_to_get_cost_center"}, int64(1))
		api.logger.WithError(err).Error("Failed to get cost center in CanProceedWithUsage", kvp.String("customerId", usageKey.EntityDetail.CustomerId))
		return nil, twirp.InternalErrorWith(err)
	}

	if costCenterKey != nil {
		entityDetail.SetCostCenterDetail(models.NewCustomerFromCostCenter(costCenterKey).CostCenterDetail)
	}

	billForPublicRepoUsage := customer.BillForPublicRepoUsage
	publicRepoDiscountAvailable, _ := api.discountEngine.PublicRepoDiscountApplicable(ctx, api.logger, customer.Id, usageKey.Sku, usageKey.EntityDetail.RepoId, usageKey.RepositoryVisibility, billForPublicRepoUsage)
	if publicRepoDiscountAvailable {
		return api.buildAndLogCanProceedWithUsageResponse(
			true, models.UsageAllowed.ToProto(), nil, nil, usageKey, customer.DiscountPlanName, statsKey,
		), nil
	}

	planDiscounts := make([]*proto.CanProceedWithUsagePlanDiscount, 0)
	includedDiscountStart := time.Now()
	planDiscountsStates, canProceedWithIncludedDiscounts, err := api.discountEngine.CanProceedWithIncludedDiscounts(ctx, api.logger, customer, usageKey.Sku, year, month)
	api.statter.Timing(fmt.Sprintf("%s.can_proceed_with_included_discounts", statsKey), stats.Tags{"product": usageKey.Product, "sku": usageKey.Sku}, time.Since(includedDiscountStart))

	if err != nil {
		api.statter.Counter(fmt.Sprintf("%s.error", statsKey), stats.Tags{"error": "failed_to_get_discount_states"}, int64(1))
		api.logger.WithError(err).Error("Failed to get discount states in CanProceedWithUsage", kvp.String("customerId", usageKey.EntityDetail.CustomerId))
		return nil, twirp.InternalErrorWith(err)
	}

	for _, discountState := range planDiscountsStates {
		if discountState != nil {
			planDiscounts = append(planDiscounts, &proto.CanProceedWithUsagePlanDiscount{
				IsFullyApplied: discountState.IsFullyApplied,
				CurrentAmount:  models.ToDecimalAmount(discountState.CurrentAmount),
				TargetAmount:   models.ToDecimalAmount(discountState.TargetAmount),
				Uuid:           discountState.Uuid,
			})
		}
	}

	canProceed := true
	canProceedStatus := models.UsageAllowed.ToProto()
	applicableBudgets := make([]*proto.CanProceedWithUsageInfo, 0)

	if !canProceedWithIncludedDiscounts {
		if customer.IsOnTrial() {
			return api.buildAndLogCanProceedWithUsageResponse(
				false, models.OnTrial.ToProto(), planDiscounts, nil, usageKey, customer.DiscountPlanName, statsKey,
			), nil
		}

		if !models.IsBillable(customer, costCenterKey) {
			return api.buildAndLogCanProceedWithUsageResponse(
				false, models.NotBillable.ToProto(), planDiscounts, nil, usageKey, customer.DiscountPlanName, statsKey,
			), nil
		}

		findBudgetsForStart := time.Now()
		budgets, err := api.budgetEngine.FindBudgetsFor(ctx, api.logger, usageKey.Product, usageKey.Sku, entityDetail, year, month)
		api.statter.Timing(fmt.Sprintf("%s.find_budgets_for", statsKey), stats.Tags{"product": usageKey.Product, "sku": usageKey.Sku}, time.Since(findBudgetsForStart))

		if err != nil {
			api.statter.Counter(fmt.Sprintf("%s.error", statsKey), stats.Tags{"error": "failed_to_get_budgets"}, int64(1))
			api.logger.WithError(err).Error("Failed to get budgets in CanProceedWithUsage", kvp.String("customerId", usageKey.EntityDetail.CustomerId))
			return nil, twirp.InternalErrorWith(err)
		}

		getBudgetStateStart := time.Now()
		for _, b := range budgets {
			state, err := api.budgetEngine.GetBudgetState(ctx, api.logger, b, year, month)
			if err != nil {
				api.statter.Counter(fmt.Sprintf("%s.error", statsKey), stats.Tags{"error": "failed_to_get_budget_state"}, int64(1))
				api.logger.WithError(err).Error("Failed to get budget state in CanProceedWithUsage", kvp.String("customerId", usageKey.EntityDetail.CustomerId))
				return nil, twirp.InternalErrorWith(err)
			}

			if state.IsFullyFunded {
				if b.BudgetLimitType.HardLimit() {
					canProceed = false
					canProceedStatus = models.BudgetLimitReached.ToProto()
				}
				applicableBudgets = append(applicableBudgets, &proto.CanProceedWithUsageInfo{
					BudgetKey:       b.BudgetKey.ToProto(),
					BudgetState:     state.ToProto(),
					BudgetLimitType: b.BudgetLimitType.ToProto(),
				})
			}
		}
		api.statter.Timing(fmt.Sprintf("%s.get_budget_state", statsKey), stats.Tags{"product": usageKey.Product, "sku": usageKey.Sku}, time.Since(getBudgetStateStart))
	}

	return api.buildAndLogCanProceedWithUsageResponse(
		canProceed, canProceedStatus, planDiscounts, applicableBudgets, usageKey, customer.DiscountPlanName, statsKey,
	), nil
}

// UpsertBudget implements proto.CustomerApi
func (api *CustomerApi) UpsertBudget(ctx context.Context, r *proto.UpsertBudgetRequest) (*proto.UpsertBudgetResponse, error) {
	budget, err := models.NewBudget(r.Budget)
	if err != nil {
		return nil, err
	}

	skipCache := false
	if api.isHardLimitBudget(budget) && api.pricingEngine.IsHighWatermarkProduct(ctx, api.logger, budget.PricingTargetId, skipCache) {
		return nil, twirp.NewError(twirp.InvalidArgument, "High watermark products cannot have PreventFurtherUsage budget alerting")
	}

	err = api.budgetEngine.UpsertBudget(ctx, api.logger, budget)
	if err != nil && err.Error() == "Customers on trial cannot create budgets" {
		return nil, twirp.NewError(twirp.PermissionDenied, err.Error())
	}
	if err != nil {
		return nil, err
	}

	return &proto.UpsertBudgetResponse{}, nil
}

func (api *CustomerApi) isHardLimitBudget(budget *models.Budget) bool {
	return budget.BudgetLimitType == models.PreventFurtherUsage || budget.BudgetLimitType == models.StopActiveUsage
}

// DeleteBudget implements proto.CustomerApi
func (api *CustomerApi) DeleteBudget(ctx context.Context, r *proto.DeleteBudgetRequest) (*proto.DeleteBudgetResponse, error) {
	err := api.budgetEngine.DeleteBudget(ctx, api.logger, r.CustomerId, r.Uuid)
	if err != nil {
		return nil, err
	}

	return &proto.DeleteBudgetResponse{}, nil
}

// GetBudget implements proto.CustomerApi basic crud on budget
func (api *CustomerApi) GetBudget(ctx context.Context, request *proto.GetBudgetRequest) (*proto.GetBudgetResponse, error) {

	budgetKey := models.NewBudgetKey(request.Key)

	budget, err := api.budgetEngine.GetBudget(ctx, api.logger, budgetKey)
	if err != nil {
		return nil, err
	}

	if budget == nil {
		return &proto.GetBudgetResponse{}, nil
	}

	return &proto.GetBudgetResponse{
		Budget: budget.ToProto(),
	}, nil
}

// GetBudgetByUuid implements proto.CustomerApi
func (api *CustomerApi) GetBudgetByUuid(ctx context.Context, request *proto.GetBudgetByUuidRequest) (*proto.GetBudgetByUuidResponse, error) {
	budget, err := api.budgetEngine.GetBudgetByUuid(ctx, api.logger, request.CustomerId, request.Uuid)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	if budget == nil {
		return &proto.GetBudgetByUuidResponse{}, nil
	}

	return &proto.GetBudgetByUuidResponse{
		Budget: budget.ToProto(),
	}, nil
}

// GetAllBudgets implements proto.CustomerApi basic crud on budget
func (api *CustomerApi) GetAllBudgets(ctx context.Context, request *proto.GetAllBudgetsRequest) (*proto.GetAllBudgetsResponse, error) {
	customerId := request.CustomerId
	budgetInfos, err := api.budgetEngine.GetAllBudgets(ctx, api.logger, customerId)
	if err != nil {
		return nil, twirp.RequiredArgumentError("request")
	}

	if request.CustomerId == "" {
		return nil, twirp.RequiredArgumentError("customerId")
	}

	if budgetInfos == nil {
		return &proto.GetAllBudgetsResponse{}, nil
	}

	var budgetInfoProtos []*proto.BudgetInfo

	for _, budgetInfo := range budgetInfos {
		budgetInfoProtos = append(budgetInfoProtos, budgetInfo.ToProto())
	}

	return &proto.GetAllBudgetsResponse{
		Budgets: budgetInfoProtos,
	}, nil
}

func (api *CustomerApi) GetAlertableBudgetStateInfo(ctx context.Context, request *proto.GetAllBudgetsRequest) (*proto.GetAllBudgetsResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}

	customerId := request.CustomerId
	if customerId == "" {
		return nil, twirp.RequiredArgumentError("customerId")
	}

	budgetInfos, err := api.budgetEngine.GetAlertableBudgetStateInfo(ctx, api.logger, customerId)
	if err != nil {
		return nil, err
	}

	if budgetInfos == nil {
		return &proto.GetAllBudgetsResponse{}, nil
	}

	var budgetInfoProtos []*proto.BudgetInfo

	for _, budgetInfo := range budgetInfos {
		budgetInfoProtos = append(budgetInfoProtos, budgetInfo.ToProto())
	}

	return &proto.GetAllBudgetsResponse{
		Budgets: budgetInfoProtos,
	}, nil
}

// GetBudgetState implements proto.CustomerApi
func (api *CustomerApi) GetBudgetState(ctx context.Context, request *proto.GetBudgetStateRequest) (*proto.GetBudgetStateResponse, error) {
	budgetKey := models.NewBudgetKey(request.Key)

	budget, err := api.budgetEngine.GetBudget(ctx, api.logger, budgetKey)
	if err != nil {
		return nil, err
	}

	if budget == nil {
		return &proto.GetBudgetStateResponse{}, nil
	}

	budgetState, err := api.budgetEngine.GetBudgetState(ctx, api.logger, budget, request.Year, request.Month)
	if err != nil {
		return nil, err
	}

	if budgetState == nil {
		return &proto.GetBudgetStateResponse{}, nil
	}

	return &proto.GetBudgetStateResponse{
		BudgetState: budgetState.ToProto(),
	}, nil
}

func (api *CustomerApi) UpsertCustomer(ctx context.Context, input *proto.CreateCustomerRequest) (*proto.CreateCustomerResponse, error) {
	customer := input.Customer
	if customer == nil {
		return nil, twirp.RequiredArgumentError("customer")
	}

	item := models.NewCustomerFromProto(customer)

	err := api.customerEngine.Upsert(ctx, api.logger, item)

	return &proto.CreateCustomerResponse{}, err
}

func (api *CustomerApi) PatchCustomer(ctx context.Context, input *proto.PatchCustomerRequest) (*proto.PatchCustomerResponse, error) {
	ctx, sp := api.tracer.Start(ctx, "CustomerApi.PatchCustomer")
	defer sp.End()

	if input.Customer == nil {
		return nil, twirp.RequiredArgumentError("customer")
	}

	if input.Customer.CustomerId == "" {
		return nil, twirp.RequiredArgumentError("customer.customerId")
	}

	err := api.customerService.UpsertAndMigrateCustomer(ctx, input.Customer, input.PreviousCustomerId, api.logger)
	if err != nil {
		return nil, err
	}
	return &proto.PatchCustomerResponse{}, nil
}

func (api *CustomerApi) GetCustomer(ctx context.Context, input *proto.GetCustomerRequest) (*proto.GetCustomerResponse, error) {

	customer, err := api.customerEngine.Get(ctx, api.logger, input.CustomerId, true)
	if err != nil {
		return nil, err
	}

	if customer == nil {
		return &proto.GetCustomerResponse{}, nil
	}

	return &proto.GetCustomerResponse{
		Customer: customer.ToProto(),
	}, err
}

func (api *CustomerApi) GetCustomers(ctx context.Context, input *proto.GetCustomersRequest) (*proto.GetCustomersResponse, error) {
	var customers []*models.Customer
	for _, customerId := range input.CustomerIds {
		customer, err := api.customerEngine.Get(ctx, api.logger, customerId, true)
		if err != nil {
			return nil, err
		}
		if customer != nil {
			customers = append(customers, customer)
		}
	}

	if len(customers) == 0 {
		return &proto.GetCustomersResponse{}, nil
	}

	var customerProtos []*proto.Customer
	for _, customer := range customers {
		customerProtos = append(customerProtos, customer.ToProto())
	}

	return &proto.GetCustomersResponse{
		Customers: customerProtos,
	}, nil
}

func (api *CustomerApi) buildAndLogCanProceedWithUsageResponse(canProceed bool, status proto.CanProceedWithUsageStatus, planDiscounts []*proto.CanProceedWithUsagePlanDiscount, applicableBudgets []*proto.CanProceedWithUsageInfo, usageKey *proto.UsageKey, discountPlanName string, statsKey string) *proto.CanProceedWithUsageResponse {
	api.statter.Counter(
		fmt.Sprintf("%s.status", statsKey),
		stats.Tags{"can_proceed": strconv.FormatBool(canProceed), "status": status.String(), "product": usageKey.Product, "sku": usageKey.Sku},
		int64(1),
	)
	api.logger.Info("CanProceedWithUsage result",
		kvp.String("customerId", usageKey.EntityDetail.CustomerId),
		kvp.Bool("canProceed", canProceed),
		kvp.String("status", status.String()),
		kvp.String("product", usageKey.Product),
		kvp.String("sku", usageKey.Sku),
	)
	return &proto.CanProceedWithUsageResponse{
		CanProceed:        canProceed,
		ApplicableBudgets: applicableBudgets,
		PlanDiscounts:     planDiscounts,
		Status:            status,
		PlanName:          discountPlanName,
	}
}

func (api *CustomerApi) isFreeSku(ctx context.Context, sku string) bool {
	skuPricing, err := api.pricingEngine.GetPricing(ctx, api.logger, sku, false)
	if err != nil {
		return false
	}
	return skuPricing.Price == 0
}
