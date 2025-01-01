package engines

import (
	"context"
	"strconv"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	repositories "github.com/github/monolith-twirp-billing/repositories/v1"
	"github.com/pkg/errors"
	//nolint:staticcheck
)

//go:generate pegomock generate -o ../../testing/fakes/mock_customer_engine.go --self_package=fakes --package=fakes CustomerEngineInterface
type CustomerEngineInterface interface {
	Upsert(ctx context.Context, logger log.Logger, customer *models.Customer) error
	PatchCustomer(ctx context.Context, logger log.Logger, customer *models.Customer, toPatch *proto.Customer) error
	CacheRepositoryMetadata(ctx context.Context, logger log.Logger, repo *repositories.Repository) error
	Get(ctx context.Context, logger log.Logger, customerId string, skipCache bool) (*models.Customer, error)
	GetEnterpriseInfoFromItem(ctx context.Context, logger log.Logger, item *models.Item) (*models.EnterpriseInfo, error)
	GetBillingAndParentCustomersFromItem(ctx context.Context, logger log.Logger, item *models.Item) (*models.Customer, *models.Customer, error)
	GetEnterpriseInfoFromBillingAndParentCustomers(ctx context.Context, logger log.Logger, billingCustomer *models.Customer, parentCustomer *models.Customer) *models.EnterpriseInfo
	GetBillingAndParentCustomersFromCustomerId(ctx context.Context, logger log.Logger, customerId string) (*models.Customer, *models.Customer, error)
	GetEnterpriseInfoFromCustomerId(ctx context.Context, logger log.Logger, customerId string) (*models.EnterpriseInfo, *models.Customer, error)
}

type CustomerEngine struct {
	*EngineParams
}

func NewCustomerEngine(params *EngineParams) CustomerEngineInterface {
	return &CustomerEngine{
		EngineParams: params,
	}
}

func (e *CustomerEngine) Upsert(ctx context.Context, logger log.Logger, customer *models.Customer) error {
	err := e.db.UpsertWithOptions(ctx, logger, customer, nil)
	return err
}

func (e *CustomerEngine) PatchCustomer(ctx context.Context, logger log.Logger, customer *models.Customer, toPatch *proto.Customer) error {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.PatchCustomer")
	defer sp.End()

	type patchFunc func(*azcosmos.PatchOperations, string, any)

	// Patch operation functions
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

	batchStart := time.Now()
	_, _, err := e.db.Batch(ctx, customer, nil, assign)

	duration := time.Since(batchStart)
	e.statter.Timing("customer_engine.patch_customer_db_batch_update", stats.Tags{"patch_operations_count": strconv.Itoa(len(po))}, duration)

	return err
}

func (e *CustomerEngine) CacheRepositoryMetadata(ctx context.Context, logger log.Logger, repo *repositories.Repository) error {
	return e.db.UpsertWithOptions(ctx, logger, models.NewRepo(int64(repo.Id), repo.IsPublic), nil)
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

	billingCustomer, err := e.Get(ctx, logger, customerId, false)
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
		parentCustomer, err = e.Get(ctx, logger, billingCustomer.EnterpriseCustomerId, false)
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

func (e *CustomerEngine) Get(ctx context.Context, logger log.Logger, customerId string, skipCache bool) (*models.Customer, error) {
	ctx, sp := e.tracer.Start(ctx, "CustomerEngine.Get")
	defer sp.End()

	customerKey := models.NewCustomerKey(customerId)

	if skipCache {
		customer, err := db.NewQuerier[*models.Customer](e.db).ReadItem(ctx, logger, customerKey, nil)
		return customer, err
	} else {

		// Our default consistency level is session, but we want to read from the cache so we need to lax the
		// consistency level to eventual. The alternative would be to pass and manually manage the session token
		// ourselves which is not ideal and the Go SDK does not do this automatically as Azure documentation suggests.
		duration := time.Duration(1 * time.Minute)
		options := &interfaces.QueryOptions{
			ConsistencyLevel: azcosmos.ConsistencyLevelEventual.ToPtr(),
			DedicatedGatewayRequestOptions: &azcosmos.DedicatedGatewayRequestOptions{
				MaxIntegratedCacheStaleness: &duration,
			},
		}
		customer, err := db.NewGatewayQuerier[*models.Customer](e.db).ReadItem(ctx, logger, customerKey, options) // uses the item cache
		return customer, err
	}
}
