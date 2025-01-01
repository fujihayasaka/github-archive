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

type CustomerService struct {
	budgetService     BudgetServiceInterface
	customerEngine    engines.CustomerEngineInterface
	discountService   DiscountServiceInterface
	costCenterService CostCenterServiceInterface
}

//go:generate pegomock generate -o ../../testing/fakes/mock_customer_service.go --self_package=fakes --package=fakes CustomerServiceInterface
type CustomerServiceInterface interface {
	UpsertAndMigrateCustomer(ctx context.Context, customer *proto.Customer, previousCustomerId string, logger log.Logger) error
}

func NewCustomerService(budgetService BudgetServiceInterface, customerEngine engines.CustomerEngineInterface, discountService DiscountServiceInterface, costCenterService CostCenterServiceInterface) CustomerServiceInterface {
	return &CustomerService{
		budgetService:     budgetService,
		customerEngine:    customerEngine,
		discountService:   discountService,
		costCenterService: costCenterService,
	}
}

// UpsertCustomer inserts a new customer or updates an existing customer in the database.
// If the customer already exists, their information will be updated; otherwise, a new customer record will be created.
//
// Parameters:
//
//	ctx - The context for managing request deadlines and cancellation signals.
//	customer - The customer information to be upserted.
//
// Returns:
//
//	An error if the operation fails, otherwise nil.
func (c *CustomerService) UpsertAndMigrateCustomer(ctx context.Context, customer *proto.Customer, previousCustomerId string, logger log.Logger) error {
	existingCustomer, err := c.customerEngine.Get(ctx, logger, customer.CustomerId, true)
	if err != nil {
		return err
	}

	if existingCustomer == nil {
		err := c.createNewCustomer(ctx, customer, logger)
		if err != nil {
			return errors.Wrap(err, "Failed to create new customer when upserting customer")
		}
	} else {
		err = c.updateExistingCustomer(ctx, existingCustomer, customer, logger)
		if err != nil {
			return errors.Wrap(err, "Failed to update existing customer when upserting customer")
		}
	}

	err = c.migrateCustomer(ctx, customer.CustomerId, previousCustomerId, logger)
	if err != nil {
		return errors.Wrap(err, "Failed to migrate customer")
	}

	return nil
}

func (c *CustomerService) createNewCustomer(ctx context.Context, customer *proto.Customer, logger log.Logger) error {
	logger.Info("CustomerService creating new customer", kvp.String(logging.BillingCustomerId, customer.CustomerId))
	newCustomer := models.NewCustomerFromProto(customer)
	err := c.customerEngine.Upsert(ctx, logger, newCustomer)
	if err != nil {
		return errors.Wrap(err, "Failed to upsert new customer")
	}
	return nil
}

func (c *CustomerService) updateExistingCustomer(ctx context.Context, existingCustomer *models.Customer, customerProto *proto.Customer, logger log.Logger) error {
	logger.Info("CustomerService updating existing customer", kvp.String(logging.BillingCustomerId, existingCustomer.GetCustomerId()))
	err := c.customerEngine.PatchCustomer(ctx, logger, existingCustomer, customerProto)
	if err != nil {
		return errors.Wrap(err, "Failed to patch customer when updating existing customer")
	}

	err = c.discountService.UpdateDiscountsOnPatchCustomer(ctx, existingCustomer, customerProto, logger)
	if err != nil {
		return errors.Wrap(err, "Failed to update discounts when patching existing customer")
	}

	updatedCustomer, err := c.customerEngine.Get(ctx, logger, customerProto.GetCustomerId(), true)
	if err != nil {
		return errors.Wrap(err, "Failed to get customer when updating existing customer")
	}

	err = c.costCenterService.UpdateAllCostCentersTargetOnPatchCustomer(ctx, existingCustomer, updatedCustomer, logger)
	if err != nil {
		return errors.Wrap(err, "Failed to update all cost centers targets when patching customer")
	}

	return nil
}

func (c *CustomerService) migrateCustomer(ctx context.Context, customerId string, previousCustomerId string, logger log.Logger) error {
	// Migrate customer data if the previous customer ID is not empty
	if previousCustomerId != "" {
		logger.Info("Migrating customer", kvp.String(logging.BillingCustomerId, customerId), kvp.String(logging.BillingCustomerPreviousId, previousCustomerId))
		// Verify the previous customer is valid
		previousCustomer, err := c.customerEngine.Get(ctx, logger, previousCustomerId, true)
		if err != nil {
			return errors.Wrap(err, "Failed to get existing customer")
		}
		if previousCustomer == nil {
			logger.Info("Previous customer was not found in Billing Platform to migrate from, skipping rest of migrate customer", kvp.String(logging.BillingCustomerId, customerId), kvp.String(logging.BillingCustomerPreviousId, previousCustomerId))
			return nil
		}

		// Get previous customer budgets and change them to new customer
		err = c.budgetService.MigrateBudgetsToNewCustomer(ctx, previousCustomerId, customerId, logger)
		if err != nil {
			return errors.Wrap(err, "Failed to migrate budgets to new customer")
		}
	}

	return nil
}
