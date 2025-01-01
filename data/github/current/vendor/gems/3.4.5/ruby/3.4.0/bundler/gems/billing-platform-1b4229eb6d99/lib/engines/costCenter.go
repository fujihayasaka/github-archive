package engines

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"slices"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/bperrors"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/utils"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
)

//go:generate pegomock generate -o ../../testing/fakes/mock_cost_center_engine.go --self_package=fakes --package=fakes CostCenterEngineInterface
type CostCenterEngineInterface interface {
	GetAllCostCenters(ctx context.Context, logger log.Logger, customer *models.Customer) ([]*models.CostCenter, *bperrors.Error)
	GetAllCostCentersFromCache(ctx context.Context, logger log.Logger, customer *models.Customer) ([]*models.CostCenter, *bperrors.Error)
	Get(ctx context.Context, logger log.Logger, costCenterKey *models.CostCenterKey) (*models.CostCenter, error)
	FindCostCenterFor(ctx context.Context, logger log.Logger, entity *models.EntityDetail, sku string) (*models.CostCenterKey, error)
	Create(ctx context.Context, logger log.Logger, costCenter *models.CostCenter) (*models.CostCenter, error)
	Update(ctx context.Context, logger log.Logger, key *models.CostCenterKey, name string, targetId string, resourcesToAdd []*models.Resource, resourcesToRemove []*models.Resource, updateResourcesOnly bool) (*models.CostCenter, error)
	UpdateBillingTarget(ctx context.Context, logger log.Logger, costCenter *models.CostCenter, enterprise *models.Customer) error
	AddResourceTo(ctx context.Context, logger log.Logger, costCenterKey *models.CostCenterKey, resources []*models.Resource) *bperrors.Error
	RemoveResourceFrom(ctx context.Context, logger log.Logger, costCenter *models.CostCenter, resources []*models.Resource, removeNestedResources bool) *bperrors.Error
	ArchiveCostCenter(ctx context.Context, logger log.Logger, costCenter *models.CostCenter) *bperrors.Error
}

// We limit one request to add/remove resources to 50 resources in order to satisfy Cosmos Transactional Batch limits of 100 operations and 2MB total size
var SingleTransactionResourceLimit = 50

type CostCenterEngine struct {
	*EngineParams
	costCenterKeyQuerier db.ModelQuerier[*models.CostCenterKey] // TODO: refactor some calls below use CostCenter/ some use the CostCenterKey
	costCenterQuerier    db.ModelQuerier[*models.CostCenter]
	pricingEngine        PricingEngineInterface
	customerEngine       CustomerEngineInterface
}

func newCostCenterEngineWithQuerier(params *EngineParams, keyQuerier db.ModelQuerier[*models.CostCenterKey], modelQuerier db.ModelQuerier[*models.CostCenter], pricingEngine PricingEngineInterface, customerEngine CustomerEngineInterface) CostCenterEngineInterface {
	return &CostCenterEngine{
		EngineParams:         params,
		costCenterKeyQuerier: keyQuerier,
		costCenterQuerier:    modelQuerier,
		pricingEngine:        pricingEngine,
		customerEngine:       customerEngine,
	}
}

func NewCostCenterEngine(params *EngineParams, pricingEngine PricingEngineInterface, customerEngine CustomerEngineInterface) CostCenterEngineInterface {
	return newCostCenterEngineWithQuerier(params, db.NewQuerier[*models.CostCenterKey](params.db), db.NewQuerier[*models.CostCenter](params.db), pricingEngine, customerEngine)
}

func (e *CostCenterEngine) GetAllCostCenters(ctx context.Context, logger log.Logger, customer *models.Customer) ([]*models.CostCenter, *bperrors.Error) {
	ctx, sp := e.tracer.Start(ctx, "CostCenterEngine.GetAllCostCenters")
	defer sp.End()

	costCenters, err := e.costCenterQuerier.QueryItems(ctx, logger, db.QueryStringAllCostCenterIdEqualsUUID, customer.ToCostCentersPartitionKey())
	if err != nil {
		return nil, bperrors.NewError(bperrors.Internal, err)
	}

	return costCenters, nil
}

func (e *CostCenterEngine) GetAllCostCentersFromCache(ctx context.Context, logger log.Logger, customer *models.Customer) ([]*models.CostCenter, *bperrors.Error) {
	ctx, sp := e.tracer.Start(ctx, "CostCenterEngine.GetAllCostCentersFromCache")
	defer sp.End()

	// Our default consistency level is session, but we want to read from the cache so we need to lax the
	// consistency level to eventual. The alternative would be to pass and manually manage the session token
	// ourselves which is not ideal and the Go SDK does not do this automatically as Azure documentation suggests.
	options := &azcosmos.QueryOptions{
		ConsistencyLevel: azcosmos.ConsistencyLevelEventual.ToPtr(),
	}

	costCenters, err := db.NewGatewayQuerier[*models.CostCenter](e.db).QueryItemsWithOptions(ctx, logger, db.QueryStringAllCostCenterIdEqualsUUID, customer.ToCostCentersPartitionKey(), 0, options)
	if err != nil {
		return nil, bperrors.NewError(bperrors.Internal, err)
	}

	return costCenters, nil
}

func (e *CostCenterEngine) Get(ctx context.Context, logger log.Logger, costCenterKey *models.CostCenterKey) (*models.CostCenter, error) {
	costCenter, err := e.costCenterQuerier.ReadItemWithRetries(ctx, logger, costCenterKey)
	if err != nil {
		return nil, err
	}

	if costCenter != nil {
		return costCenter, nil
	}
	return nil, nil
}

func (c *CostCenterEngine) FindCostCenterFor(ctx context.Context, logger log.Logger, entity *models.EntityDetail, sku string) (*models.CostCenterKey, error) {
	ctx, sp := c.tracer.Start(ctx, "CostCenterEngine.FindCostCenterFor")
	defer sp.End()

	customerId := entity.CustomerId
	skipCache := false
	isUnitTypeUserMonths, err := c.pricingEngine.IsUnitTypeUserMonths(ctx, logger, sku, skipCache)
	if err != nil {
		return nil, err
	}

	// For license based meters, we need to look up user based cost centers first.
	if entity.ActorId != 0 && isUnitTypeUserMonths {
		resource := models.ToResourceLookUpKey(customerId, models.NewResourceWithNumericId(entity.ActorId, models.User))
		resourceCostCenterKey, err := c.costCenterKeyQuerier.ReadItemWithRetries(ctx, logger, resource)
		if err != nil {
			return nil, err
		}

		if resourceCostCenterKey != nil && resourceInActiveCostCenter(resourceCostCenterKey) {
			return resourceCostCenterKey, nil
		}
	}

	if entity.OrganizationId != 0 {
		resource := models.ToResourceLookUpKey(customerId, models.NewResourceWithNumericId(entity.OrganizationId, models.OwningEntity))
		resourceCostCenterKey, err := c.costCenterKeyQuerier.ReadItemWithRetries(ctx, logger, resource)
		if err != nil {
			return nil, err
		}
		if resourceCostCenterKey != nil && resourceInActiveCostCenter(resourceCostCenterKey) {
			return resourceCostCenterKey, nil
		}
	}

	if entity.RepositoryId != 0 {
		resource := models.ToResourceLookUpKey(customerId, models.NewResourceWithNumericId(entity.RepositoryId, models.Repository))
		resourceCostCenterKey, err := c.costCenterKeyQuerier.ReadItemWithRetries(ctx, logger, resource)
		if err != nil {
			return nil, err
		}

		if resourceCostCenterKey != nil && resourceInActiveCostCenter(resourceCostCenterKey) {
			return resourceCostCenterKey, nil
		}
	}

	return nil, nil
}

func resourceInActiveCostCenter(resourceCostCenterKey *models.CostCenterKey) bool {
	return resourceCostCenterKey.Customer != nil &&
		resourceCostCenterKey.Customer.CostCenterDetail != nil &&
		resourceCostCenterKey.Customer.CostCenterState == models.CostCenterActive
}

func (e *CostCenterEngine) Create(ctx context.Context, logger log.Logger, costCenter *models.CostCenter) (*models.CostCenter, error) {
	if len(costCenter.Resources) > SingleTransactionResourceLimit {
		return nil, e.resourceLimitError().OriginalError
	}

	err := e.validateCostCenter(ctx, logger, costCenter)
	if err != nil {
		return nil, err
	}

	success, results, err := e.db.Batch(ctx, costCenter, nil, func(batch *azcosmos.TransactionalBatch) error {
		marshalledCostCenter, err := json.Marshal(costCenter)
		if err != nil {
			return errors.Wrap(err, "failed to marshal cost center")
		}

		batch.UpsertItem(marshalledCostCenter, nil)

		for _, resource := range costCenter.Resources {
			marshalledResource, err := json.Marshal(costCenter.AsResourceLookup(resource))
			if err != nil {
				return errors.Wrap(err, "failed to marshal resource")
			}
			batch.CreateItem(marshalledResource, nil)
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	if !success {
		for index, result := range results {
			if result.StatusCode < 300 {
				continue
			}

			// case statement for different error result.StatusCode values
			if result.StatusCode == http.StatusConflict {
				return nil, db.ItemConflictError
			} else if result.StatusCode != http.StatusFailedDependency {
				return nil, fmt.Errorf("transaction failed due to operation %v which failed with status code %v", index, result.StatusCode)
			}
		}

		// This should never happen in theory
		return nil, bperrors.GenericInternalError()
	}

	return costCenter, nil
}

func (e *CostCenterEngine) Update(ctx context.Context, logger log.Logger, key *models.CostCenterKey, name string, targetId string, resourcesToAdd []*models.Resource, resourcesToRemove []*models.Resource, updateResourcesOnly bool) (*models.CostCenter, error) {
	if len(resourcesToAdd)+len(resourcesToRemove) > SingleTransactionResourceLimit {
		return nil, e.resourceLimitError().OriginalError
	}

	costCenter, err := e.Get(ctx, logger, key)
	if err != nil {
		return nil, err
	}
	if costCenter.CostCenterState != models.CostCenterActive {
		return nil, errors.New("Cannot update a deleted cost center")
	}

	// Use a separate copy so that we don't modify the original cost center before adding/removing resources
	copyToValidate := models.NewCostCenter(costCenter.ToProto(), false)
	if updateResourcesOnly {
		copyToValidate.TargetId = costCenter.TargetId
		copyToValidate.Name = costCenter.Name
	} else {
		copyToValidate.TargetId = targetId
		copyToValidate.Name = name
	}

	copyToValidate.Resources = append(copyToValidate.Resources, resourcesToAdd...)

	err = e.validateCostCenter(ctx, logger, copyToValidate)
	if err != nil {
		return nil, err
	}

	success, results, err := e.db.Batch(ctx, costCenter, nil, func(batch *azcosmos.TransactionalBatch) error {
		// Update the cost center document
		if !updateResourcesOnly {
			costCenter.TargetId = targetId
			costCenter.Name = name

			marshalledCostCenter, err := json.Marshal(costCenter)
			if err != nil {
				return errors.Wrap(err, "failed to marshal cost center")
			}
			batch.UpsertItem(marshalledCostCenter, nil)
		}

		// add resources document and add embedded resources in costcenter document
		err = e.addResourceToInternal(costCenter, resourcesToAdd, batch)
		if err != nil {
			return errors.Wrap(err, "failed to add resources to cost center")
		}

		// remove resources document and remove embedded resources in costcenter document
		err = e.removeResourceFromInternal(costCenter, resourcesToRemove, batch, true)
		if err != nil {
			return errors.Wrap(err, "failed to remove resources from cost center")
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	if !success {
		for index, result := range results {
			if result.StatusCode < 300 {
				continue
			}

			// case statement for different error result.StatusCode values
			if result.StatusCode == http.StatusConflict {
				return nil, db.ItemConflictError
			} else if result.StatusCode != http.StatusFailedDependency {
				return nil, fmt.Errorf("transaction failed due to operation %v which failed with status code %v", index, result.StatusCode)
			}
		}

		// This should never happen in theory
		return nil, bperrors.GenericInternalError()
	}

	return costCenter, nil
}

func (e *CostCenterEngine) AddResourceTo(ctx context.Context, logger log.Logger, costCenterKey *models.CostCenterKey, resources []*models.Resource) *bperrors.Error {
	if len(resources) > SingleTransactionResourceLimit {
		return e.resourceLimitError()
	}

	costCenter, err := e.Get(ctx, logger, costCenterKey)
	if err != nil {
		return bperrors.NewError(bperrors.Internal, err)
	}

	if costCenter == nil {
		return bperrors.NewError(bperrors.NotFound, errors.New("cost center not found."))
	}

	success, results, err := e.db.Batch(ctx, costCenter, nil, func(batch *azcosmos.TransactionalBatch) error {
		// add resources document and add embedded resources in costcenter document
		err = e.addResourceToInternal(costCenter, resources, batch)
		if err != nil {
			return errors.New("failed to add resources to cost center")
		}

		return nil
	})

	if !success {
		for index, result := range results {
			if result.StatusCode < 300 {
				continue
			}

			// case statement for different error result.StatusCode values
			if result.StatusCode == http.StatusConflict {
				return bperrors.NewFriendlyError(bperrors.AlreadyExists, errors.New("one or more resources have already been added to this cost center."))
			} else if result.StatusCode != http.StatusFailedDependency {
				return bperrors.NewError(bperrors.Internal, fmt.Errorf("transaction failed due to operation %v which failed with status code %v", index, result.StatusCode))
			}
		}

		// This should never happen in theory
		return bperrors.GenericInternalError()
	}

	return nil
}

func (e *CostCenterEngine) addResourceToInternal(costCenter *models.CostCenter, resources []*models.Resource, batch *azcosmos.TransactionalBatch) error {
	maxBatchSize := 10 // https://learn.microsoft.com/en-us/azure/cosmos-db/partial-document-update-faq#is-there-a-limit-to-the-number-of-partial-document-update-operations-
	batchEndIdx := 0
	for batchStartIdx := 0; batchStartIdx < len(resources); batchStartIdx += maxBatchSize {
		batchEndIdx += maxBatchSize
		if batchEndIdx > len(resources) {
			batchEndIdx = len(resources)
		}

		ops := db.PatchOps{}
		addResourceCount := 0
		for _, resourceKey := range resources[batchStartIdx:batchEndIdx] {
			marshalled, err := json.Marshal(costCenter.AsResourceLookup(resourceKey))
			if err != nil {
				return errors.Wrap(err, "failed to marshal cost center")
			}

			batch.CreateItem(marshalled, nil)
			ops.AppendAdd("/Resources/-", resourceKey)
			addResourceCount++
		}

		// Do not update if no resources were added
		if addResourceCount > 0 {
			batch.PatchItem(costCenter.Id, ops, nil)
		}
	}

	// Update the Cost Center in memory
	costCenter.Resources = append(costCenter.Resources, resources...)

	return nil
}

/*
Remove resources from a cost center

	Removes the given resources from the given cost center using a transactional batch, up to the SingleTransactionResourceLimit limit.
	If removeNestedResources is true the resources will be removed from the nested array on the cost center (e.g. when updating),
	otherwise they will be persisted (such as when we're archiving and want to persist the data for record-keeping).
*/
func (e *CostCenterEngine) RemoveResourceFrom(ctx context.Context, logger log.Logger, costCenter *models.CostCenter, resources []*models.Resource, removeNestedResources bool) *bperrors.Error {
	if len(resources) > SingleTransactionResourceLimit {
		return e.resourceLimitError()
	}

	success, results, _ := e.db.Batch(ctx, costCenter, nil, func(batch *azcosmos.TransactionalBatch) error {
		// add resources document and add embedded resources in costcenter document
		err := e.removeResourceFromInternal(costCenter, resources, batch, removeNestedResources)
		if err != nil {
			return errors.New("failed to remove resource from cost center")
		}

		return nil
	})

	if !success {
		for index, result := range results {
			if result.StatusCode < 300 {
				continue
			}

			// case statement for different error result.StatusCode values
			if result.StatusCode == http.StatusNotFound {
				return bperrors.NewFriendlyError(bperrors.NotFound, errors.New("one or more resources have already been removed from this cost center."))
			} else if result.StatusCode != http.StatusFailedDependency {
				return bperrors.NewError(bperrors.Internal, fmt.Errorf("transaction failed due to operation %v which failed with status code %v", index, result.StatusCode))
			}

			// This should never happen in theory
			return bperrors.GenericInternalError()
		}
	}

	return nil
}

// Builds Transactional Batch operations to remove the given resources from the given cost center
func (e *CostCenterEngine) removeResourceFromInternal(costCenter *models.CostCenter, resources []*models.Resource, batch *azcosmos.TransactionalBatch, removeNestedResources bool) error {
	// https://learn.microsoft.com/en-us/azure/cosmos-db/partial-document-update-faq#is-there-a-limit-to-the-number-of-partial-document-update-operations-
	maxBatchSize := 10

	// Iterate over resources in reverse order because going in ascending order causes indexing problems when Cosmos iterates through the operations
	for batchEndIdx := len(costCenter.Resources); batchEndIdx > 0; batchEndIdx -= maxBatchSize {
		batchStartIdx := max(batchEndIdx-maxBatchSize, 0)

		ops := db.PatchOps{}
		removeResourceCount := 0

		for idx := batchEndIdx - 1; idx >= batchStartIdx; idx-- {
			resource := costCenter.Resources[idx]

			// Getting index of resource to remove
			shouldRemoveResource := slices.ContainsFunc(resources, func(r *models.Resource) bool {
				return r.Id == resource.Id && r.Type == resource.Type
			})

			if shouldRemoveResource {
				// Add an operation to delete the resource document
				batch.DeleteItem(costCenter.AsResourceLookup(resource).Id, nil)

				if removeNestedResources {
					// Remove the resource from the nested resources on the cost center document
					resourcePath := fmt.Sprintf("/Resources/%d", idx)
					ops.AppendRemove(resourcePath)
				}

				removeResourceCount++
			}
		}

		// Do not update if no resources were removed
		if removeNestedResources && removeResourceCount > 0 {
			batch.PatchItem(costCenter.Id, ops, nil)
		}
	}

	return nil
}

func (e *CostCenterEngine) UpdateBillingTarget(ctx context.Context, logger log.Logger, costCenter *models.CostCenter, enterprise *models.Customer) error {

	err := e.updateCostCenterBillingTarget(ctx, logger, costCenter, enterprise)
	if err != nil {
		return err
	}
	err = e.updateCostCenterCustomerBillingTarget(ctx, logger, costCenter, enterprise)
	if err != nil {
		return err
	}
	err = e.updateCostCenterResourcesTarget(ctx, logger, costCenter, enterprise) // TODO : Can we skip doing this since the target on the resources is not used?
	if err != nil {
		return err
	}
	return nil

}

func (e *CostCenterEngine) updateCostCenterBillingTarget(ctx context.Context, logger log.Logger, costCenter *models.CostCenter, enterprise *models.Customer) error {
	// UpdateCostCenterTarget pk:customer:<customerid>:costcenters , id:costcenterUUID
	// TODO return early if there is no mismatch

	if enterprise.BillingTarget == models.Azure && costCenter.TargetType == models.AzureSubscription {
		return nil
	}
	if enterprise.BillingTarget == models.Zuora && costCenter.TargetType == models.ZuoraSubscription {
		return nil
	}

	po := azcosmos.PatchOperations{}
	if enterprise.BillingTarget == models.Azure {
		po.AppendAdd("/TargetType", models.AzureSubscription)
	} else if enterprise.BillingTarget == models.Zuora {
		po.AppendAdd("/TargetType", models.ZuoraSubscription)
	}
	// Cleaning the target id to prevent a mismatch between Azure and Zuora.
	// This will default to the customer billing target.
	po.AppendAdd("/TargetId", "")

	// also update the embedded customer object within the cost center
	po.AppendAdd("/Customer/BillingTarget", enterprise.BillingTarget)
	err := e.db.PatchWithOptions(ctx, logger, costCenter, po, nil)
	if err != nil {
		logger.WithError(err).Error("Failed to update cost center customer record.")
		return errors.Wrap(err, "Failed to update cost center customer record")
	}
	logger.Info("Updated cost center billing target")
	return nil
}

func (e *CostCenterEngine) updateCostCenterCustomerBillingTarget(ctx context.Context, logger log.Logger, costCenter *models.CostCenter, enterprise *models.Customer) error {
	// UpdateCostCenterCustomerTarget pk:customer:<costCenterUUID> id:customer
	costCenterCustomer, err := e.customerEngine.Get(ctx, logger, costCenter.CostCenterKey.UUID, false)
	if err != nil {
		logger.WithError(err).Error("Failed to get cost center customer")
		return err
	}
	if costCenterCustomer.BillingTarget == enterprise.BillingTarget {
		return nil
	}

	po := azcosmos.PatchOperations{}
	po.AppendAdd("/BillingTarget", enterprise.BillingTarget)
	err = e.db.PatchWithOptions(ctx, logger, costCenterCustomer, po, nil)
	if err != nil {
		logger.WithError(err).Error("Failed to update cost center customer's billing target.")
		return errors.Wrap(err, "Failed to update cost center customer's billing target")
	}
	logger.Info("Updated cost center customer's billing target.")
	return nil
}

func (e *CostCenterEngine) updateCostCenterResourcesTarget(ctx context.Context, logger log.Logger, costCenter *models.CostCenter, enterprise *models.Customer) error {
	for _, resource := range costCenter.Resources {
		resourceLookup := costCenter.AsResourceLookup(resource)

		po := azcosmos.PatchOperations{}

		if enterprise.BillingTarget == models.Azure {
			po.AppendAdd("/TargetType", models.AzureSubscription)
		} else if enterprise.BillingTarget == models.Zuora {
			po.AppendAdd("/TargetType", models.ZuoraSubscription)
		}

		// Cleaning the target id to prevent a mismatch between Azure and Zuora.
		// This will default to the customer billing target.
		po.AppendAdd("/TargetId", "")

		// Updating the billing target on the embedded customer object.
		po.AppendAdd("/Customer/BillingTarget", enterprise.BillingTarget)

		err := e.db.PatchWithOptions(ctx, logger, resourceLookup, po, nil)
		if err != nil {
			logger.WithError(err).Error("Failed to update cost center resource record.")
			return errors.Wrap(err, "Failed to update cost center resource record")
		}

		logger.Info("Updated cost center resource's billing target.")
	}
	return nil

}

/*
Archive the cost center
 1. removes all resource lookup records associate with the costcenter
 2. sets the state of the costcenter to archived
 3. does not update the embedded resources in the costcenter. This field is left so users can see what resources were
    associated with the costcenter before it was archived
*/
func (e *CostCenterEngine) ArchiveCostCenter(ctx context.Context, logger log.Logger, costCenter *models.CostCenter) *bperrors.Error {
	// Split the resource removal into batches
	for batchEndIdx := len(costCenter.Resources); batchEndIdx > 0; batchEndIdx -= SingleTransactionResourceLimit {
		batchStartIdx := max(batchEndIdx-SingleTransactionResourceLimit, 0)

		bpErr := e.RemoveResourceFrom(ctx, logger, costCenter, costCenter.Resources[batchStartIdx:batchEndIdx], false)

		if bpErr != nil {
			return bpErr.WithFriendlyError(errors.New("failed to archive cost center"))
		}
	}

	costCenter.CostCenterState = models.CostCenterArchived
	err := e.db.UpsertWithOptions(ctx, logger, costCenter, &interfaces.QueryOptions{})
	if err != nil {
		return bperrors.NewError(bperrors.Internal, err)
	}

	return nil
}

func (e *CostCenterEngine) validateCostCenter(ctx context.Context, logger log.Logger, costCenter *models.CostCenter) error {
	existingCostCenters, err := e.GetAllCostCenters(ctx, logger, costCenter.Customer)
	if err != nil {
		return err
	}

	// Only validate against active cost centers
	existingCostCenters = utils.FilterSlice(existingCostCenters, func(c *models.CostCenter) bool {
		return c.CostCenterState == models.CostCenterActive
	})

	return costCenter.Validate(existingCostCenters)
}

func (e *CostCenterEngine) resourceLimitError() *bperrors.Error {
	return bperrors.NewFriendlyError(bperrors.BadRequest, fmt.Errorf("request exceeds the limit of %d resources", SingleTransactionResourceLimit))
}
