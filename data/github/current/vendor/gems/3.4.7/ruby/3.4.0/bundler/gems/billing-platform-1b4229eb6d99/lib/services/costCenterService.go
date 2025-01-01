package services

import (
	"context"
	"strings"

	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

type CostCenterService struct {
	costCenterEngine engines.CostCenterEngineInterface
}

func NewCostCenterService(costCenterEngine engines.CostCenterEngineInterface) CostCenterServiceInterface {
	return &CostCenterService{
		costCenterEngine: costCenterEngine,
	}
}

//go:generate pegomock generate -o ../../testing/fakes/mock_costcenter_service.go --self_package=fakes --package=fakes CostCenterServiceInterface
type CostCenterServiceInterface interface {
	UpdateAllCostCentersTargetOnPatchCustomer(ctx context.Context, existingCustomer *models.Customer, updatedCustomer *models.Customer, logger log.Logger) error
}

type CostCenterServiceError struct {
	errorType     string
	customerID    string
	costCenterIDs []string
	Errors        []error
}

func (c *CostCenterServiceError) Error() string {
	switch c.errorType {
	case "TargetPatchError":
		return "Failed to update some cost centers for customer " + c.customerID + " with cost centers " + strings.Join(c.costCenterIDs, ",")
	default:
		return "CostCenter Sevice Error"
	}
}

func (c *CostCenterService) UpdateAllCostCentersTargetOnPatchCustomer(ctx context.Context, existingCustomer *models.Customer, updatedCustomer *models.Customer, logger log.Logger) error {
	logger = logger.WithFields(kvp.String("gh.customer.id", updatedCustomer.GetCustomerId()))
	logger.Info("CostcenterService updating billing targets", kvp.Any("existingCustomer", existingCustomer), kvp.Any("updatedCustomer", updatedCustomer))

	if existingCustomer.BillingTarget == updatedCustomer.BillingTarget {
		logger.Info("Billing target not changed, skipping cost center update")
		return nil
	}

	// Get all cost centers for the customer
	costCenters, err := c.costCenterEngine.GetAllCostCenters(ctx, logger, updatedCustomer)
	if err != nil {
		return err
	}

	// Update the cost centers

	var UpdateErrors []error
	var costCenterIDs []string
	for _, costCenter := range costCenters {
		logger.Info("Updating cost center", kvp.String("gh.cost_center.id", costCenter.Id))

		UpdateError := c.costCenterEngine.UpdateBillingTarget(ctx, logger, costCenter, updatedCustomer)

		if UpdateError != nil {
			costCenterIDs = append(costCenterIDs, costCenter.Id)
			UpdateErrors = append(UpdateErrors, UpdateError)
		}
	}

	if UpdateErrors != nil {
		return &CostCenterServiceError{
			errorType:     "TargetPatchError",
			customerID:    updatedCustomer.Id,
			costCenterIDs: costCenterIDs,
			Errors:        UpdateErrors,
		}
	}
	return nil

}
