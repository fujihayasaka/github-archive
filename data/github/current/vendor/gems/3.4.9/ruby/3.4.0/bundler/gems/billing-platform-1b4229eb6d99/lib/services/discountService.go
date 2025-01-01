package services

import (
	"context"

	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
)

type DiscountService struct {
	discountEngine engines.DiscountEngineInterface
}

//go:generate pegomock generate -o ../../testing/fakes/mock_discount_service.go --self_package=fakes --package=fakes DiscountServiceInterface
type DiscountServiceInterface interface {
	UpdateDiscountsOnPatchCustomer(ctx context.Context, existingCustomer *models.Customer, protoCustomer *proto.Customer, logger log.Logger) error
	UpdatePlanDiscountsForCustomer(ctx context.Context, customer *models.Customer, newPlanName string, logger log.Logger) error
}

func NewDiscountService(discountEngine engines.DiscountEngineInterface) DiscountServiceInterface {
	return &DiscountService{
		discountEngine: discountEngine,
	}
}

// UpdateDiscountsOnPatchCustomer updates the discount states for a customer when their discount plan name changes.
// It compares the existing customer's discount plan name with the new discount plan name from the proto customer.
// If the discount plan name has changed, it logs the change and updates the discount states accordingly.
//
// Parameters:
//   - ctx: The context for managing request-scoped values, cancellation, and deadlines.
//   - existingCustomer: The existing customer model containing current discount plan information.
//   - protoCustomer: The proto customer model containing the new discount plan information.
//   - logger: The logger for logging information and errors.
//
// Returns:
//   - error: An error if updating the discount states fails, otherwise nil.
func (d *DiscountService) UpdateDiscountsOnPatchCustomer(ctx context.Context, existingCustomer *models.Customer, protoCustomer *proto.Customer, logger log.Logger) error {
	if existingCustomer.DiscountPlanName != protoCustomer.DiscountPlanName {
		logger.Info("Discount plan name has changed, updating discount states", kvp.String(logging.BillingCustomerId, existingCustomer.GetCustomerId()), kvp.String(logging.CustomerPlanName, existingCustomer.DiscountPlanName), kvp.String("gh.customer.discount.plan.name.new", protoCustomer.DiscountPlanName))
		err := d.UpdatePlanDiscountsForCustomer(ctx, existingCustomer, protoCustomer.DiscountPlanName, logger)
		if err != nil {
			return err
		}
	}
	return nil
}

// UpdatePlanDiscountsForCustomer updates the discount states for a customer when they switch to a new plan.
// It retrieves the current discount states, maps them to the new plan's discounts, and updates the discount states accordingly.
//
// Parameters:
//   - ctx: The context for managing request-scoped values, cancellation, and deadlines.
//   - customer: The customer whose discount states need to be updated.
//   - newPlanName: The name of the new plan to which the customer is switching.
//   - logger: The logger for logging information and errors.
//
// Returns:
//   - error: An error if any occurs during the update process, otherwise nil.
func (d *DiscountService) UpdatePlanDiscountsForCustomer(ctx context.Context, customer *models.Customer, newPlanName string, logger log.Logger) error {
	currentCustomerPlanDiscounts, err := d.discountEngine.GetPlanDiscountStates(ctx, logger, customer)
	if err != nil {
		return err
	}

	logger.Info("Current customer plan discounts", kvp.String(logging.BillingCustomerId, customer.GetCustomerId()), kvp.String(logging.CustomerPlanName, customer.DiscountPlanName), kvp.Any("gh.customer.plan.discounts.length", len(currentCustomerPlanDiscounts)))
	if len(currentCustomerPlanDiscounts) == 0 {
		return nil
	}

	currentPlanDiscounts := engines.AllPlanDiscounts()[newPlanName]
	existingPlanDiscounts := engines.AllPlanDiscounts()[customer.DiscountPlanName]
	oldUuidToNewPlanDiscount := mapCurrentAndNewPlanDiscounts(existingPlanDiscounts, currentPlanDiscounts)

	// Iterate through all of a customer's plan discounts and update to the new Uuid if it already exists
	for _, ds := range currentCustomerPlanDiscounts {
		logger.Info("Checking plan discount", kvp.String(logging.BillingCustomerId, customer.EnterpriseCustomerId), kvp.String(logging.CustomerPlanName, customer.DiscountPlanName), kvp.String("gh.customer.plan.name.new", newPlanName), kvp.String("gh.customer.plan.discount.uuid", ds.Uuid))
		if oldUuidToNewPlanDiscount[ds.Uuid] == nil {
			continue
		}

		newPlanDiscount := oldUuidToNewPlanDiscount[ds.Uuid]
		logger.Info("Found a plan discount to update", kvp.String(logging.BillingCustomerId, customer.GetCustomerId()), kvp.String("gh.customer.plan.discount.uuid", ds.Uuid), kvp.String("gh.customer.plan.discount.uuid.new", newPlanDiscount.Uuid), kvp.String(logging.BillingPlatformPartitionKey, ds.PartitionKey), kvp.Int64(logging.DiscountStateTargetAmount, ds.TargetAmount), kvp.Int64(logging.DiscountStateCurrentAmount, ds.CurrentAmount), kvp.Bool(logging.DiscountStateIsFullyApplied, ds.IsFullyApplied))
		ds = updatePlanDiscounts(ds, newPlanDiscount, customer)
		err := d.discountEngine.UpsertDiscountState(ctx, logger, ds)
		if err != nil {
			return errors.Wrap(err, "unable to upsert discount state")
		}
	}

	return nil
}

// mapCurrentAndNewPlanDiscounts maps old plan discounts to new plan discounts based on their type.
// It takes two slices of PlanDiscount pointers: oldPlanDiscounts and currentPlanDiscounts.
// It returns a map where the keys are the UUIDs of the old plan discounts and the values are the corresponding new plan discounts.
//
// Parameters:
// - oldPlanDiscounts: A slice of pointers to PlanDiscount representing the old plan discounts.
// - currentPlanDiscounts: A slice of pointers to PlanDiscount representing the current plan discounts.
//
// Returns:
// - A map where the keys are the UUIDs of the old plan discounts and the values are pointers to the corresponding new plan discounts.
func mapCurrentAndNewPlanDiscounts(oldPlanDiscounts []*models.PlanDiscount, currentPlanDiscounts []*models.PlanDiscount) map[string]*models.PlanDiscount {
	oldDiscountIdToNewPlanDiscount := make(map[string]*models.PlanDiscount)
	for _, oldPlanDiscount := range oldPlanDiscounts {
		for _, currentPlanDiscount := range currentPlanDiscounts {
			if oldPlanDiscount.Type == currentPlanDiscount.Type {
				oldDiscountIdToNewPlanDiscount[oldPlanDiscount.Uuid] = currentPlanDiscount
				break
			}
		}
	}
	return oldDiscountIdToNewPlanDiscount
}

// updatePlanDiscounts updates the DiscountState with the new PlanDiscount and customer information.
// It sets the UUID, PartitionKey, and TargetAmount fields of the DiscountState.
//
// Parameters:
//   - ds: A pointer to the DiscountState to be updated.
//   - newPlanDiscount: A pointer to the new PlanDiscount containing the updated discount information.
//   - customer: A pointer to the Customer whose discount state is being updated.
//
// Returns:
//   - A pointer to the updated DiscountState.
func updatePlanDiscounts(ds *models.DiscountState, newPlanDiscount *models.PlanDiscount, customer *models.Customer) *models.DiscountState {
	ds.Uuid = newPlanDiscount.Uuid
	ds.PartitionKey = customer.ToDiscountStatePartitionKey(ds.Uuid, int64(models.UTCNow().Year()), int64(models.UTCNow().Month()))
	newTargetAmount := models.ToWholeAmount[int64](newPlanDiscount.TargetAmount)
	ds.TargetAmount = newTargetAmount

	// We do not update the current amount since that could be a potential abuse vector switching between plans
	if ds.CurrentAmount >= newTargetAmount {
		ds.IsFullyApplied = true
	} else {
		ds.IsFullyApplied = false
	}

	return ds
}
