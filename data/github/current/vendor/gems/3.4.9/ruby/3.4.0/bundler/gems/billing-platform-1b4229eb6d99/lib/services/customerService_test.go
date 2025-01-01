package services

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func TestUpsertAndMigrateCustomer_NewCustomer_Success(t *testing.T) {
	customerService, _, customerEngine, _, _, logger := newCustomerService(t)
	customerProto := &proto.Customer{CustomerId: "123", DiscountPlanName: "PlanA"}
	customer := models.NewCustomerFromProto(customerProto)
	pegomock.When(customerEngine.Get(context.Background(), logger, "123", true)).ThenReturn(nil, nil)
	pegomock.When(customerEngine.Upsert(context.Background(), logger, customer)).ThenReturn(nil)

	// Test
	err := customerService.UpsertAndMigrateCustomer(context.Background(), customerProto, "", logger)

	// Assert
	assert.NoError(t, err)
	customerEngine.VerifyWasCalledOnce().Upsert(context.Background(), logger, customer)
}

func TestUpsertAndMigrateCustomer_ExistingCustomerWithoutMigration_Success(t *testing.T) {
	customerService, _, customerEngine, discountService, costCenterService, logger := newCustomerService(t)
	customerProto := &proto.Customer{CustomerId: "123", DiscountPlanName: "PlanA"}
	existingCustomer := models.NewCustomerFromProto(customerProto)
	pegomock.When(customerEngine.Get(context.Background(), logger, "123", true)).ThenReturn(existingCustomer, nil)

	// Test
	err := customerService.UpsertAndMigrateCustomer(context.Background(), customerProto, "", logger)

	// Assert
	assert.NoError(t, err)
	customerEngine.VerifyWasCalledOnce().PatchCustomer(context.Background(), logger, existingCustomer, customerProto)
	discountService.VerifyWasCalledOnce().UpdateDiscountsOnPatchCustomer(context.Background(), existingCustomer, customerProto, logger)
	costCenterService.VerifyWasCalledOnce().UpdateAllCostCentersTargetOnPatchCustomer(context.Background(), existingCustomer, existingCustomer, logger)
}

func TestUpsertAndMigrateCustomer_ExistingCustomerWithMigration_Success(t *testing.T) {
	customerService, budgetService, customerEngine, discountService, _, logger := newCustomerService(t)
	customerId := "123"
	previousCustomerId := "456"
	customerProto := &proto.Customer{CustomerId: customerId, DiscountPlanName: "PlanA"}
	customerProto2 := &proto.Customer{CustomerId: previousCustomerId, DiscountPlanName: "PlanA"}
	existingCustomer := models.NewCustomerFromProto(customerProto)
	previousCustomer := models.NewCustomerFromProto(customerProto2)
	pegomock.When(customerEngine.Get(context.Background(), logger, "123", true)).ThenReturn(existingCustomer, nil)
	pegomock.When(customerEngine.Get(context.Background(), logger, "456", true)).ThenReturn(previousCustomer, nil)
	pegomock.When(budgetService.MigrateBudgetsToNewCustomer(context.Background(), previousCustomerId, customerId, logger)).ThenReturn(nil)

	// Test
	err := customerService.UpsertAndMigrateCustomer(context.Background(), customerProto, previousCustomerId, logger)

	// Assert
	assert.NoError(t, err)
	customerEngine.VerifyWasCalledOnce().PatchCustomer(context.Background(), logger, existingCustomer, customerProto)
	discountService.VerifyWasCalledOnce().UpdateDiscountsOnPatchCustomer(context.Background(), existingCustomer, customerProto, logger)
	customerEngine.VerifyWasCalledOnce().Get(context.Background(), logger, previousCustomerId, true)
	budgetService.VerifyWasCalledOnce().MigrateBudgetsToNewCustomer(context.Background(), previousCustomerId, customerId, logger)
}

func TestUpsertAndMigrateCustomer_ExistingCustomerWithMigrationBudgets_Error(t *testing.T) {
	customerService, budgetService, customerEngine, discountService, _, logger := newCustomerService(t)
	customerId := "123"
	previousCustomerId := "456"
	customerProto := &proto.Customer{CustomerId: customerId, DiscountPlanName: "PlanA"}
	customerProto2 := &proto.Customer{CustomerId: previousCustomerId, DiscountPlanName: "PlanA"}
	existingCustomer := models.NewCustomerFromProto(customerProto)
	previousCustomer := models.NewCustomerFromProto(customerProto2)
	pegomock.When(customerEngine.Get(context.Background(), logger, customerId, true)).ThenReturn(existingCustomer, nil)
	pegomock.When(customerEngine.Get(context.Background(), logger, previousCustomerId, true)).ThenReturn(previousCustomer, nil)
	pegomock.When(budgetService.MigrateBudgetsToNewCustomer(context.Background(), previousCustomerId, customerId, logger)).ThenReturn(fmt.Errorf("error"))

	// Test
	err := customerService.UpsertAndMigrateCustomer(context.Background(), customerProto, previousCustomerId, logger)
	fmt.Println(err)

	// Assert
	assert.Error(t, err)
	customerEngine.VerifyWasCalledOnce().PatchCustomer(context.Background(), logger, existingCustomer, customerProto)
	discountService.VerifyWasCalledOnce().UpdateDiscountsOnPatchCustomer(context.Background(), existingCustomer, customerProto, logger)
	customerEngine.VerifyWasCalledOnce().Get(context.Background(), logger, previousCustomerId, true)
	budgetService.VerifyWasCalledOnce().MigrateBudgetsToNewCustomer(context.Background(), previousCustomerId, customerId, logger)
}

func newCustomerService(t *testing.T) (CustomerServiceInterface, *fakes.MockBudgetServiceInterface, *fakes.MockCustomerEngineInterface, *fakes.MockDiscountServiceInterface, *fakes.MockCostCenterServiceInterface, log.Logger) {
	_, _, _, logger, _ := helpers.SetupMocks(t)
	pegomock.RegisterMockTestingT(t)
	customerEngine := fakes.NewMockCustomerEngineInterface()
	discountService := fakes.NewMockDiscountServiceInterface()
	budgetService := fakes.NewMockBudgetServiceInterface()
	costCenterService := fakes.NewMockCostCenterServiceInterface()

	return NewCustomerService(budgetService, customerEngine, discountService, costCenterService), budgetService, customerEngine, discountService, costCenterService, logger
}
