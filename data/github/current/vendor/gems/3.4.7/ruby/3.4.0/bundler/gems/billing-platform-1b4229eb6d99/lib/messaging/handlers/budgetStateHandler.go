package handlers

import (
	"context"
	"encoding/json"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"

	"github.com/github/billing-platform/lib/models"
)

type BudgetStateHandler struct {
	*Handler
	budgetEngine   engines.BudgetEngineInterface
	hydroPublisher interfaces.HydroPublisher
}

func NewBudgetStateHandler(params *HandlerParams, budgetEngine engines.BudgetEngineInterface, hydroPublisher interfaces.HydroPublisher) *BudgetStateHandler {
	return &BudgetStateHandler{
		Handler:        NewHandler(params, models.WorkerTypeBudgetState),
		budgetEngine:   budgetEngine,
		hydroPublisher: hydroPublisher,
	}
}

func (h *BudgetStateHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	logger.Info("Processing message in", kvp.String("queue", h.queueName), kvp.Int("budget_state_handler.job_delivery_attempt", rr.DeliveryAttempt))

	_, sp := h.tracer.Start(ctx, "BudgetStateHandler.ProcessMessage")
	defer sp.End()

	var budgetStateJob *models.BudgetStateUpdateJob
	if err := json.Unmarshal(rr.Payload, &budgetStateJob); err != nil {
		return errors.Wrap(err, "BudgetStateHandler failed to unmarshal enveloped message")
	}
	budgetState, err := h.budgetEngine.PatchBudgetState(ctx, logger, budgetStateJob.Budget, budgetStateJob.Amount, budgetStateJob.Year, budgetStateJob.Month, budgetStateJob.Sku)
	if err != nil {
		return errors.Wrap(err, "BudgetStateHandler failed to patch budget state")
	} else if budgetState == nil {
		logger.Error("Budget state is nil", kvp.Any("budget", budgetStateJob.Budget), kvp.String("CustomerID", budgetStateJob.Budget.CustomerId))
		// log error and explicitly return nil to avoid retrying the message, as this will never pass with a retry
		return nil
	}
	if budgetStateJob.Budget.BudgetLimitType.HardLimit() && budgetState.CurrentAmount > budgetState.TargetAmount {
		// We allowed the budget to go over the limit, but it's too late to fix it now.
		// We should log to investigate.
		logger.Error("Budget went over the limit", kvp.Any("budget", budgetStateJob.Budget), kvp.Any("budgetState", budgetState), kvp.String("CustomerID", budgetStateJob.Budget.CustomerId))
		h.statter.Counter("wrongful_overage", stats.Tags{"sku": budgetStateJob.Sku}, int64(1))
	}

	err = h.budgetEngine.PublishBudgetStateThresholdMessage(logger, h.hydroPublisher, budgetStateJob.Budget, budgetState)
	if err != nil {
		logger.WithError(err).Error("failed to update budget state")
	}
	return err
}
