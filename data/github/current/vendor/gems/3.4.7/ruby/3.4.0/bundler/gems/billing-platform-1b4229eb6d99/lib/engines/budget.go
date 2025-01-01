package engines

import (
	"context"
	"fmt"
	"math/rand"
	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"
)

//go:generate pegomock generate -o ../../testing/fakes/mock_budget_engine.go --self_package=fakes --package=fakes BudgetEngineInterface
type BudgetEngineInterface interface {
	UpsertBudget(ctx context.Context, logger log.Logger, budget *models.Budget) error
	UpsertBudgetWithoutBudgetState(ctx context.Context, logger log.Logger, budget *models.Budget) error
	DeleteBudget(ctx context.Context, logger log.Logger, customerId string, uuid string) error
	GetBudget(ctx context.Context, logger log.Logger, budgetKey *models.BudgetKey) (*models.Budget, error)
	GetBudgetByUuid(ctx context.Context, logger log.Logger, customerId string, uuid string) (*models.Budget, error)
	GetBudgetState(ctx context.Context, logger log.Logger, budget *models.Budget, year, month int64) (*models.BudgetState, error)
	UpsertBudgetState(ctx context.Context, logger log.Logger, budgetState *models.BudgetState) error
	GetAllBudgets(ctx context.Context, logger log.Logger, customerId string) ([]*models.BudgetInfo, error)
	FindBudgetsFor(ctx context.Context, logger log.Logger, product string, sku string, entity *models.EntityDetail, year, month int64) ([]*models.Budget, error)
	GetBudgetsByEntityType(ctx context.Context, logger log.Logger, customerId string, entityType models.ResourceType, entityId string, product string, sku string) ([]*models.Budget, error)
	GetBudgetByKey(ctx context.Context, logger log.Logger, key *models.BudgetKey) (*models.Budget, error)
	GetAllBudgetsWithoutInfo(ctx context.Context, logger log.Logger, customerId string) ([]*models.Budget, error)
	PatchBudgetState(ctx context.Context, logger log.Logger, budget *models.Budget, amounts *models.Amounts, year int64, month int64, sku string) (*models.BudgetState, error)
	PublishBudgetStateThresholdMessage(logger log.Logger, hydroPublisher interfaces.HydroPublisher, budget *models.Budget, budgetState *models.BudgetState) error
	GetAlertableBudgetStateInfo(ctx context.Context, logger log.Logger, customerId string) ([]*models.BudgetInfo, error)
}

type BudgetEngine struct {
	*EngineParams
	customerEngine            CustomerEngineInterface
	gatewayBudgetStateQuerier interfaces.Querier[*models.BudgetState]
}

func NewBudgetEngine(params *EngineParams, customerEngine CustomerEngineInterface) BudgetEngineInterface {
	return &BudgetEngine{
		EngineParams:              params,
		customerEngine:            customerEngine,
		gatewayBudgetStateQuerier: db.NewGatewayQuerier[*models.BudgetState](params.db),
	}
}

func (e *BudgetEngine) UpsertBudget(ctx context.Context, logger log.Logger, budget *models.Budget) error {
	customer, err := e.customerEngine.Get(ctx, logger, budget.CustomerId, false)
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

func (e *BudgetEngine) UpsertBudgetWithoutBudgetState(ctx context.Context, logger log.Logger, budget *models.Budget) error {
	err := e.db.UpsertWithOptions(ctx, logger, budget, nil)
	if err != nil {
		return err
	}
	return nil
}

func (e *BudgetEngine) DeleteBudget(ctx context.Context, logger log.Logger, customerId string, uuid string) error {
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

func (e *BudgetEngine) GetBudget(ctx context.Context, logger log.Logger, budgetKey *models.BudgetKey) (*models.Budget, error) {
	budget, err := db.NewQuerier[*models.Budget](e.db).ReadItemWithRetries(ctx, logger, budgetKey)
	if err != nil {
		return nil, err
	}

	return budget, nil
}

func (e *BudgetEngine) GetBudgetByUuid(ctx context.Context, logger log.Logger, customerId string, uuid string) (*models.Budget, error) {
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

func (e *BudgetEngine) GetBudgetState(ctx context.Context, logger log.Logger, budget *models.Budget, year, month int64) (*models.BudgetState, error) {
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

func (e *BudgetEngine) GetBudgetStateWithCachingAndWithoutRetries(ctx context.Context, logger log.Logger, budget *models.Budget, year, month int64) (*models.BudgetState, error) {
	budgetStateKey := budget.BudgetKey.ToBudgetStateKey(year, month, models.DocumentIdBudgetState)

	// ReadItem from the gateway querier uses the item cache to get a point read using the budgetStateKey
	budgetState, err := e.gatewayBudgetStateQuerier.ReadItem(ctx, logger, budgetStateKey, &interfaces.QueryOptions{RetryCount: 0, ConsistencyLevel: azcosmos.ConsistencyLevelEventual.ToPtr()})
	if err != nil {
		return nil, err
	}

	return budgetState, nil
}

func (e *BudgetEngine) UpsertBudgetState(ctx context.Context, logger log.Logger, budgetState *models.BudgetState) error {
	err := e.db.UpsertWithOptions(ctx, logger, budgetState, nil)
	return err
}

// GetAllBudgets returns all budgets for a customer with the budget state info (useful for CRUD operations).
func (e *BudgetEngine) GetAllBudgets(ctx context.Context, logger log.Logger, customerId string) ([]*models.BudgetInfo, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.GetAllBudgets")
	defer sp.End()

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

// FindBudgetsFor - This is a newer efficient implementation that uses a single query to get all budgets for the entity.
// The filtering of the data happens after the query is made. This is in contrast to the earlier implementation
// method which uses a query per budget key per type returning 404 most of the time.
// Additionally the GetAllBudgetsWithoutInfo is a cached query
func (e *BudgetEngine) FindBudgetsFor(ctx context.Context, logger log.Logger, product string, sku string, entity *models.EntityDetail, year, month int64) ([]*models.Budget, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.FindBudgetsFor")
	defer sp.End()

	// ensure we are using the parent customer id and not a cost center uuid to look up budgets
	enterpriseCustomerId := entity.EnterpriseId()

	// query all budgets for the enterprise (uses a cached query)
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
		if each.BudgetKey.TargetType == models.CustomerResource && bProduct == product {
			filteredBudgets = append(filteredBudgets, each)
		}
		if each.BudgetKey.TargetType == models.Enterprise && entity.EnterpriseId() != "" && bProduct == product {
			filteredBudgets = append(filteredBudgets, each)
		}
	}

	return filteredBudgets, nil
}

// GetAlertableBudgetStateInfo returns alertable budgets where the alertable threshold has been met. It uses caching without any retries and is used for budget notifications(ex. overview page) and not on the budgets page.
func (e *BudgetEngine) GetAlertableBudgetStateInfo(ctx context.Context, logger log.Logger, customerId string) ([]*models.BudgetInfo, error) {
	ctx, sp := e.tracer.Start(ctx, "BudgetEngine.GetAlertableBudgetStateInfo")
	defer sp.End()

	budgets, err := e.GetAlertableBudgetsWithCachingAndWithoutRetries(ctx, logger, customerId)
	if err != nil {
		return nil, err
	}

	budgetInfos := make([]*models.BudgetInfo, 0)
	now := models.UTCNow()
	year := int64(now.Year())
	month := int64(now.Month())
	g, gctx := errgroup.WithContext(ctx)
	var budgetStateMutex = &sync.Mutex{}

	for _, budget := range budgets {
		b := budget
		g.Go(func() error {
			budgetState, err := e.GetBudgetStateWithCachingAndWithoutRetries(gctx, logger, b, year, month)
			if err != nil {
				return err
			}
			if budgetState == nil {
				return nil
			}
			budgetState.ThresholdMet = *budgetState.GetThresholdMet()
			budgetThresholdMet := budgetState.ThresholdMet
			if budgetThresholdMet.Alertable {
				budgetStateMutex.Lock()
				budgetInfos = append(budgetInfos, &models.BudgetInfo{
					Budget:      b,
					BudgetState: budgetState,
				})
				budgetStateMutex.Unlock()
			}
			return nil
		})
	}

	if err := g.Wait(); err != nil {
		return nil, errors.Wrap(err, "error getting budget state")
	}

	return budgetInfos, nil
}

func (e *BudgetEngine) GetAlertableBudgetsWithCachingAndWithoutRetries(ctx context.Context, logger log.Logger, customerId string) ([]*models.Budget, error) {
	budgetsKey := models.CustomerIdToBudgetsPartitionKey(customerId)
	alertableBudgetsQuery := "SELECT * FROM c WHERE c.WillAlert = true"

	// Our default consistency level is session, but we want to read from the cache so we need to lax the
	// consistency level to eventual. The alternative would be to pass and manually manage the session token
	// ourselves which is not ideal and the Go SDK does not do this automatically as Azure documentation suggests.
	budgets, err := db.NewGatewayQuerier[*models.Budget](e.db).
		QueryItemsWithOptions(
			ctx,
			logger,
			alertableBudgetsQuery,
			budgetsKey,
			0,
			&azcosmos.QueryOptions{
				ConsistencyLevel: azcosmos.ConsistencyLevelEventual.ToPtr(), // uses the query cache
			})
	if err != nil {
		return nil, err
	}

	return budgets, nil
}

func (e *BudgetEngine) GetBudgetsByEntityType(
	ctx context.Context,
	logger log.Logger,
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
		budget, err := e.GetBudgetByKey(ctx, logger, key)
		if err != nil {
			return nil, err
		}
		if budget != nil {
			budgets = append(budgets, budget)
		}
	}

	return budgets, nil
}

func (e *BudgetEngine) GetBudgetByKey(ctx context.Context, logger log.Logger, key *models.BudgetKey) (*models.Budget, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.GetBudgetByKey")
	defer sp.End()

	budget, err := db.NewQuerier[*models.Budget](e.db).ReadItemWithRetries(ctx, logger, key)
	if err != nil {
		return nil, err
	}

	return budget, nil
}

// GetAllBudgetsWithoutInfo returns all budgets for a customer without the budget state info (useful for minimal calls).
// This uses a query cache
func (e *BudgetEngine) GetAllBudgetsWithoutInfo(ctx context.Context, logger log.Logger, customerId string) ([]*models.Budget, error) {
	budgetsKey := models.CustomerIdToBudgetsPartitionKey(customerId)
	// Our default consistency level is session, but we want to read from the cache so we need to lax the
	// consistency level to eventual. The alternative would be to pass and manually manage the session token
	// ourselves which is not ideal and the Go SDK does not do this automatically as Azure documentation suggests.
	duration := time.Duration(1 * time.Minute)
	budgets, err := db.NewGatewayQuerier[*models.Budget](e.db).
		QueryItemsWithOptions(
			ctx,
			logger,
			db.QueryStringAll,
			budgetsKey,
			3,
			&azcosmos.QueryOptions{
				ConsistencyLevel: azcosmos.ConsistencyLevelEventual.ToPtr(), // uses the query cache
				DedicatedGatewayRequestOptions: &azcosmos.DedicatedGatewayRequestOptions{
					MaxIntegratedCacheStaleness: &duration,
				},
			})
	if err != nil {
		return nil, err
	}

	return budgets, nil
}

func (e *BudgetEngine) PatchBudgetState(ctx context.Context, logger log.Logger, budget *models.Budget, amounts *models.Amounts, year int64, month int64, sku string) (*models.BudgetState, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.PatchBudgetState")
	defer sp.End()

	logger.Info("updating budget state", kvp.String("budgetPK", budget.PartitionKey), kvp.String("budgetID", budget.Id))

	retryCount := 10
	// add a little jitter to the retry loop
	sleep := 200 * time.Millisecond
	var err error
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

		budgetState, readErr := db.NewQuerier[*models.BudgetState](e.db).ReadItem(ctx, logger, budgetStatePatch.Key, nil)
		if readErr != nil {
			return nil, errors.Wrap(readErr, "failed to query budget state")
		}

		if budgetState == nil {
			err = e.db.CreateWithOptions(ctx, logger, budgetStatePatch, nil)

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
	return nil, errors.Wrapf(err, "failed to update budget state after %d retries", retryCount)
}

func (e *BudgetEngine) PublishBudgetStateThresholdMessage(logger log.Logger, hydroPublisher interfaces.HydroPublisher, budget *models.Budget, budgetState *models.BudgetState) error {
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
