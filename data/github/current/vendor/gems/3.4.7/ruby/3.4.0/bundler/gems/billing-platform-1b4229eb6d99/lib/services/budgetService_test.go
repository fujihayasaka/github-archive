package services

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
)

func TestMigrateBudgetsToNewCustomer_SingleBudget_Success(t *testing.T) {
	budgetService, budgetEngine, logger := newBudgetService(t)
	ctx := context.Background()
	previousCustomerId := "123"
	newCustomerId := "456"

	budgets := []*models.BudgetInfo{
		{Budget: &models.Budget{
			BudgetKey: &models.BudgetKey{
				CustomerId:        previousCustomerId,
				TargetType:        models.CustomerResource,
				TargetId:          previousCustomerId,
				PricingTargetType: models.ProductPricing,
				PricingTargetId:   "actions",
			},
		}, BudgetState: &models.BudgetState{
			CurrentAmount: 100,
			TargetAmount:  200,
			Key: &models.Key{
				PartitionKey: "123:2024:12",
			},
		}},
	}

	pegomock.When(budgetEngine.GetAllBudgets(ctx, logger, previousCustomerId)).ThenReturn(budgets, nil)

	err := budgetService.MigrateBudgetsToNewCustomer(ctx, previousCustomerId, newCustomerId, logger)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	budgetEngine.VerifyWasCalledOnce().GetAllBudgets(context.Background(), logger, previousCustomerId)
}

func TestMigrateBudgetsToNewCustomer_ErrorFetchingBudgets(t *testing.T) {
	budgetService, budgetEngine, logger := newBudgetService(t)
	ctx := context.Background()
	previousCustomerId := "123"
	newCustomerId := "456"

	pegomock.When(budgetEngine.GetAllBudgets(ctx, logger, previousCustomerId)).ThenReturn(nil, fmt.Errorf("error fetching budgets"))

	err := budgetService.MigrateBudgetsToNewCustomer(ctx, previousCustomerId, newCustomerId, logger)
	if err == nil {
		t.Fatalf("expected error, got nil")
	}

	budgetEngine.VerifyWasCalledOnce().GetAllBudgets(context.Background(), logger, previousCustomerId)
}

func newBudgetService(t *testing.T) (BudgetServiceInterface, *fakes.MockBudgetEngineInterface, log.Logger) {
	_, _, _, logger, _ := helpers.SetupMocks(t)
	pegomock.RegisterMockTestingT(t)
	budgetEngine := fakes.NewMockBudgetEngineInterface()

	return NewBudgetService(budgetEngine), budgetEngine, logger
}
