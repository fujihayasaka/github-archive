package services

import (
	"context"

	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
)

type BudgetService struct {
	budgetEngine engines.BudgetEngineInterface
}

//go:generate pegomock generate -o ../../testing/fakes/mock_budget_service.go --self_package=fakes --package=fakes BudgetServiceInterface
type BudgetServiceInterface interface {
	MigrateBudgetsToNewCustomer(ctx context.Context, previousCustomerId string, newCustomerId string, logger log.Logger) error
}

func NewBudgetService(budgetEngine engines.BudgetEngineInterface) BudgetServiceInterface {
	return &BudgetService{
		budgetEngine: budgetEngine,
	}
}

// UpdateDiscountsOnPatchCustomer updates the discount states for a customer when their discount plan name changes.
// It compares the existing customer's discount plan name with the new discount plan name from the proto customer.
// If the discount plan name has changed, it logs the change and updates the discount states accordingly.
//
// Parameters:
//   - ctx: The context for managing request-scoped values, cancellation, and deadlines.
//   - previousCustomerId: The customer id of the previous customer (we are migrating from).
//   - newCustomerId: The customer id of the new customer (we are migrating to).
//   - logger: The logger for logging information and errors.
//
// Returns:
//   - error: An error if something fails, otherwise nil.
func (b *BudgetService) MigrateBudgetsToNewCustomer(ctx context.Context, previousCustomerId string, newCustomerId string, logger log.Logger) error {
	// Get all existing budgets
	budgetInfos, err := b.budgetEngine.GetAllBudgets(ctx, logger, previousCustomerId)
	if err != nil {
		return errors.Wrap(err, "Failed to get all budget infos")
	}

	logger.Info("Migrating budgets to new customer", kvp.String(logging.BillingCustomerPreviousId, previousCustomerId), kvp.String(logging.BillingCustomerId, newCustomerId), kvp.Int("gh.customer.budget_count", len(budgetInfos)))

	for _, budgetInfo := range budgetInfos {
		budgetInfo := budgetInfo
		logger.Info("Migrating budget for customer", kvp.String(logging.BillingCustomerPreviousId, previousCustomerId), kvp.String(logging.BillingCustomerId, newCustomerId), kvp.String("gh.customer.budget_key", budgetInfo.Budget.BudgetKey.String()))

		budgetInfo.Budget.BudgetKey = models.NewBudgetKeyFromExistingKey(newCustomerId, budgetInfo.Budget.BudgetKey)

		err := b.budgetEngine.UpsertBudgetWithoutBudgetState(ctx, logger, budgetInfo.Budget)
		if err != nil {
			return errors.Wrap(err, "Failed to update budget")
		}

		budgetState, err := models.NewBudgetStateFromExistingBudgetState(budgetInfo.Budget, budgetInfo.BudgetState)
		if err != nil {
			return errors.Wrap(err, "Failed to create new budget state")
		}

		err = b.budgetEngine.UpsertBudgetState(ctx, logger, budgetState)
		if err != nil {
			return errors.Wrap(err, "Failed to update budget state")
		}
	}

	return nil
}
