package services

import (
	"context"
	"errors"
	"testing"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func newCostCenterService(t *testing.T) (CostCenterServiceInterface, *fakes.MockCostCenterEngineInterface, log.Logger) {
	_, _, _, logger, _ := helpers.SetupMocks(t)
	pegomock.RegisterMockTestingT(t)
	costCenterEngine := fakes.NewMockCostCenterEngineInterface()

	return NewCostCenterService(costCenterEngine), costCenterEngine, logger

}

func setupCostCenterAndEnterprise() ([]*models.CostCenter, *models.Customer, *models.Customer) {
	costCentersWithZuora := []*models.CostCenter{
		{
			CostCenterKey: &models.CostCenterKey{
				Key: &models.Key{
					PartitionKey: "Customer:1:CostCenter",
					Id:           "uuid1",
				},
				Customer: &models.Customer{
					Key: &models.Key{
						PartitionKey: "customer:1",
						Id:           "customer"},
				},
				TargetType: models.ZuoraSubscription,
				TargetId:   "A1234",
			}},
		{
			CostCenterKey: &models.CostCenterKey{
				Key: &models.Key{
					PartitionKey: "Customer:1:CostCenter",
					Id:           "uuid2",
				},
				Customer: &models.Customer{
					Key: &models.Key{
						PartitionKey: "Customer",
						Id:           "1"},
				},
				TargetType: models.ZuoraSubscription,
				TargetId:   "A1234",
			},
		},
	}

	existingCustomer := &models.Customer{
		Key: &models.Key{
			PartitionKey: "customer:1",
			Id:           "customer",
		},
		CostCenterDetail: &models.CostCenterDetail{
			EnterpriseCustomerId: "1",
		},
		BillingTarget: models.Zuora,
	}

	updatedCustomer := &models.Customer{
		Key: &models.Key{
			PartitionKey: "Customer",
			Id:           "1",
		},
		CostCenterDetail: &models.CostCenterDetail{
			EnterpriseCustomerId: "1",
		},
		BillingTarget: models.Azure,
	}

	return costCentersWithZuora, existingCustomer, updatedCustomer

}

func TestUpdateAllCostCentersTargetOnPatchCustomer(t *testing.T) {
	costCenterService, costCenterEngine, logger := newCostCenterService(t)
	ctx := context.Background()

	costCenters, existingCustomer, updatedCustomer := setupCostCenterAndEnterprise()

	pegomock.When(costCenterEngine.GetAllCostCenters(ctx, logger, updatedCustomer)).ThenReturn(costCenters, nil)
	pegomock.When(costCenterEngine.UpdateBillingTarget(ctx, logger, costCenters[0], updatedCustomer)).ThenReturn(nil)

	err := costCenterService.UpdateAllCostCentersTargetOnPatchCustomer(ctx, existingCustomer, updatedCustomer, logger)

	assert.NoError(t, err)
	costCenterEngine.VerifyWasCalledOnce().UpdateBillingTarget(ctx, logger, costCenters[0], updatedCustomer)
	costCenterEngine.VerifyWasCalledOnce().UpdateBillingTarget(ctx, logger, costCenters[1], updatedCustomer)
}

func TestUpdateAllCostCentersTargetOnPatchCustomer_ErrorCase(t *testing.T) {
	// If one of them fails we continue with the rest
	costCenterService, costCenterEngine, logger := newCostCenterService(t)
	ctx := context.Background()

	costCenters, existingCustomer, updatedCustomer := setupCostCenterAndEnterprise()

	expectedError := "Failed to update some cost centers for customer 1 with cost centers"
	pegomock.When(costCenterEngine.GetAllCostCenters(ctx, logger, updatedCustomer)).ThenReturn(costCenters, nil)
	pegomock.When(costCenterEngine.UpdateBillingTarget(ctx, logger, costCenters[0], updatedCustomer)).ThenReturn(errors.New(expectedError))

	err := costCenterService.UpdateAllCostCentersTargetOnPatchCustomer(ctx, existingCustomer, updatedCustomer, logger)

	assert.ErrorContains(t, err, expectedError)
	costCenterEngine.VerifyWasCalledOnce().UpdateBillingTarget(ctx, logger, costCenters[0], updatedCustomer)
	costCenterEngine.VerifyWasCalledOnce().UpdateBillingTarget(ctx, logger, costCenters[1], updatedCustomer)

}
