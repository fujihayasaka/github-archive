package services

import (
	"context"
	"errors"
	"testing"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func TestUpdateDiscountsOnPatchCustomer(t *testing.T) {
	ctx := context.Background()
	discountService, discountEngine, logger := newDiscountService(t)

	existingCustomer := &models.Customer{
		DiscountPlanName: "oldPlan",
		Key: &models.Key{
			PartitionKey: "Customer",
			Id:           "1",
		},
		CostCenterDetail: &models.CostCenterDetail{
			IsCostCenterProxy:    false,
			EnterpriseCustomerId: "456",
		},
	}
	protoCustomer := &proto.Customer{
		DiscountPlanName: "newPlan",
	}

	t.Run("should update discounts when plan name changes", func(t *testing.T) {
		emptyDiscountStates := make([]*models.DiscountState, 0)
		pegomock.When(discountEngine.GetPlanDiscountStates(context.Background(), logger, existingCustomer)).ThenReturn(emptyDiscountStates, nil)

		// Test
		err := discountService.UpdateDiscountsOnPatchCustomer(ctx, existingCustomer, protoCustomer, logger)

		// Assert
		assert.NoError(t, err)
		discountEngine.VerifyWasCalledOnce().GetPlanDiscountStates(pegomock.Any[context.Context](), pegomock.Any[log.Logger](),
			pegomock.Any[*models.Customer]())
	})

	t.Run("should not update discounts when plan name does not change", func(t *testing.T) {
		protoCustomer.DiscountPlanName = "oldPlan"

		// Test
		err := discountService.UpdateDiscountsOnPatchCustomer(ctx, existingCustomer, protoCustomer, logger)

		// Assert
		discountEngine.VerifyWasCalled(pegomock.Never()).UpsertDiscountState(pegomock.Any[context.Context](), pegomock.Any[log.Logger](),
			pegomock.Any[*models.DiscountState]())
		assert.NoError(t, err)
	})
}

func TestMapCurrentAndNewPlanDiscounts(t *testing.T) {
	oldPlanDiscounts := []*models.PlanDiscount{
		{
			Uuid: "old-uuid-1",
			Type: "type1",
		},
		{
			Uuid: "old-uuid-2",
			Type: "type2",
		},
	}

	currentPlanDiscounts := []*models.PlanDiscount{
		{
			Uuid: "new-uuid-1",
			Type: "type1",
		},
		{
			Uuid: "new-uuid-2",
			Type: "type2",
		},
	}

	t.Run("should map old plan discounts to new plan discounts based on type", func(t *testing.T) {
		// Test
		mappedDiscounts := mapCurrentAndNewPlanDiscounts(oldPlanDiscounts, currentPlanDiscounts)

		// Assert
		assert.Equal(t, "new-uuid-1", mappedDiscounts["old-uuid-1"].Uuid)
		assert.Equal(t, "new-uuid-2", mappedDiscounts["old-uuid-2"].Uuid)
	})

	t.Run("should return empty map when no matching types", func(t *testing.T) {
		nonMatchingCurrentPlanDiscounts := []*models.PlanDiscount{
			{
				Uuid: "new-uuid-3",
				Type: "type3",
			},
		}

		// Test
		mappedDiscounts := mapCurrentAndNewPlanDiscounts(oldPlanDiscounts, nonMatchingCurrentPlanDiscounts)

		// Assert
		assert.Empty(t, mappedDiscounts)
	})

	t.Run("should return empty map when old plan discounts are empty", func(t *testing.T) {
		// Test
		mappedDiscounts := mapCurrentAndNewPlanDiscounts([]*models.PlanDiscount{}, currentPlanDiscounts)

		// Assert
		assert.Empty(t, mappedDiscounts)
	})

	t.Run("should return empty map when current plan discounts are empty", func(t *testing.T) {
		// Test
		mappedDiscounts := mapCurrentAndNewPlanDiscounts(oldPlanDiscounts, []*models.PlanDiscount{})

		// Assert
		assert.Empty(t, mappedDiscounts)
	})
}

func TestUpdatePlanDiscountsForCustomer_NoExistingDiscounts(t *testing.T) {
	ctx := context.Background()
	discountService, discountEngine, logger := newDiscountService(t)

	customer := &models.Customer{
		DiscountPlanName: "team",
		BillingTarget:    models.Zuora,
		CostCenterDetail: &models.CostCenterDetail{
			IsCostCenterProxy:    false,
			EnterpriseCustomerId: "123",
		},
		Key: &models.Key{
			PartitionKey: "Customer",
			Id:           "1",
		},
	}

	t.Run("should not update plan discounts when there are no existing discounts", func(t *testing.T) {
		emptyDiscountStates := make([]*models.DiscountState, 0)
		pegomock.When(discountEngine.GetPlanDiscountStates(ctx, logger, customer)).ThenReturn(emptyDiscountStates, nil)

		// Test
		err := discountService.UpdatePlanDiscountsForCustomer(ctx, customer, "free_organization", logger)

		// Assert
		assert.NoError(t, err)
		discountEngine.VerifyWasCalledOnce().GetPlanDiscountStates(ctx, logger, customer)
		discountEngine.VerifyWasCalled(pegomock.Never()).UpsertDiscountState(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.DiscountState]())
	})
}

func TestUpdatePlanDiscountsForCustomer_WithExistingDiscounts(t *testing.T) {
	ctx := context.Background()
	discountService, discountEngine, logger := newDiscountService(t)

	customer := &models.Customer{
		DiscountPlanName: "team",
		BillingTarget:    models.Zuora,
		CostCenterDetail: &models.CostCenterDetail{
			IsCostCenterProxy:    false,
			EnterpriseCustomerId: "456",
		},
		Key: &models.Key{
			PartitionKey: "Customer",
			Id:           "2",
		},
	}

	t.Run("should update plan discounts when there are existing discounts", func(t *testing.T) {
		existingDiscountStates := []*models.DiscountState{
			{
				Uuid:          "e8cdc13b-0de4-45f2-afa9-6619209084e5",
				CurrentAmount: 16,
				TargetAmount:  24,
				Key: &models.Key{
					PartitionKey: "DiscountState",
					Id:           "1",
				},
			},
		}
		pegomock.When(discountEngine.GetPlanDiscountStates(ctx, logger, customer)).ThenReturn(existingDiscountStates, nil)

		// Test
		err := discountService.UpdatePlanDiscountsForCustomer(ctx, customer, "free_organization", logger)

		// Assert
		assert.NoError(t, err)
		discountEngine.VerifyWasCalledOnce().GetPlanDiscountStates(ctx, logger, customer)
		discountEngine.VerifyWasCalledOnce().UpsertDiscountState(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.DiscountState]())
	})
}

func TestUpdatePlanDiscountsForCustomer_WhenGetPlanDiscountStatesFails(t *testing.T) {
	ctx := context.Background()
	discountService, discountEngine, logger := newDiscountService(t)
	customer := &models.Customer{
		DiscountPlanName: "team",
		BillingTarget:    models.Zuora,
		CostCenterDetail: &models.CostCenterDetail{
			IsCostCenterProxy:    false,
			EnterpriseCustomerId: "789",
		},
		Key: &models.Key{
			PartitionKey: "Customer",
			Id:           "3",
		},
	}

	t.Run("should return error when GetPlanDiscountStates fails", func(t *testing.T) {
		pegomock.When(discountEngine.GetPlanDiscountStates(ctx, logger, customer)).ThenReturn(nil, errors.New("error"))

		// Test
		err := discountService.UpdatePlanDiscountsForCustomer(ctx, customer, "free_organization", logger)

		// Assert
		assert.Error(t, err)
		discountEngine.VerifyWasCalledOnce().GetPlanDiscountStates(ctx, logger, customer)
		discountEngine.VerifyWasCalled(pegomock.Never()).UpsertDiscountState(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.DiscountState]())
	})
}

func TestUpdatePlanDiscountsForCustomer_WhenUpsertDiscountStateFails(t *testing.T) {
	ctx := context.Background()
	discountService, discountEngine, logger := newDiscountService(t)
	customer := &models.Customer{
		DiscountPlanName: "team",
		BillingTarget:    models.Zuora,
		CostCenterDetail: &models.CostCenterDetail{
			IsCostCenterProxy:    false,
			EnterpriseCustomerId: "124",
		},
		Key: &models.Key{
			PartitionKey: "Customer",
			Id:           "1",
		},
	}

	t.Run("should return error when UpsertDiscountState fails", func(t *testing.T) {
		existingDiscountStates := []*models.DiscountState{
			{
				Uuid:          "e8cdc13b-0de4-45f2-afa9-6619209084e5",
				CurrentAmount: 16,
				TargetAmount:  24,
				Key: &models.Key{
					PartitionKey: "DiscountState",
					Id:           "1",
				},
			},
		}
		pegomock.When(discountEngine.GetPlanDiscountStates(ctx, logger, customer)).ThenReturn(existingDiscountStates, nil)
		pegomock.When(discountEngine.UpsertDiscountState(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.DiscountState]())).ThenReturn(errors.New("error"))

		// Test
		err := discountService.UpdatePlanDiscountsForCustomer(ctx, customer, "free_organization", logger)

		// Assert
		assert.Error(t, err)
		discountEngine.VerifyWasCalledOnce().GetPlanDiscountStates(ctx, logger, customer)
		discountEngine.VerifyWasCalledOnce().UpsertDiscountState(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.DiscountState]())
	})
}

func TestUpdatePlanDiscounts(t *testing.T) {
	customer := &models.Customer{
		DiscountPlanName: "team",
		BillingTarget:    models.Zuora,
		CostCenterDetail: &models.CostCenterDetail{
			IsCostCenterProxy:    false,
			EnterpriseCustomerId: "124",
		},
		Key: &models.Key{
			PartitionKey: "Customer",
			Id:           "1",
		},
	}

	t.Run("should update discount state with new plan discount details", func(t *testing.T) {
		ds := &models.DiscountState{
			Uuid: "old-uuid",
			Key: &models.Key{
				PartitionKey: "old-partition-key",
			},
			TargetAmount:  100000000000,
			CurrentAmount: 50,
		}

		newPlanDiscount := &models.PlanDiscount{
			Uuid:         "new-uuid",
			TargetAmount: 200,
		}

		// Test
		updatedDs := updatePlanDiscounts(ds, newPlanDiscount, customer)

		// Assert
		assert.Equal(t, "new-uuid", updatedDs.Uuid)
		assert.Equal(t, customer.ToDiscountStatePartitionKey("new-uuid", int64(models.UTCNow().Year()), int64(models.UTCNow().Month())), updatedDs.PartitionKey)
		assert.Equal(t, int64(200000000000), updatedDs.TargetAmount)
		assert.Equal(t, int64(50), updatedDs.CurrentAmount)
		assert.Equal(t, false, updatedDs.IsFullyApplied)
	})

	t.Run("should update discount state with new plan discount details, is fully applied true", func(t *testing.T) {
		ds := &models.DiscountState{
			Uuid: "old-uuid",
			Key: &models.Key{
				PartitionKey: "old-partition-key",
			},
			TargetAmount:   200000000000,
			CurrentAmount:  150000000000,
			IsFullyApplied: false,
		}

		newPlanDiscount := &models.PlanDiscount{
			Uuid:         "new-uuid",
			TargetAmount: 100,
		}

		// Test
		updatedDs := updatePlanDiscounts(ds, newPlanDiscount, customer)

		// Assert
		assert.Equal(t, "new-uuid", updatedDs.Uuid)
		assert.Equal(t, customer.ToDiscountStatePartitionKey("new-uuid", int64(models.UTCNow().Year()), int64(models.UTCNow().Month())), updatedDs.PartitionKey)
		assert.Equal(t, int64(100000000000), updatedDs.TargetAmount)
		assert.Equal(t, int64(150000000000), updatedDs.CurrentAmount)
		assert.Equal(t, true, updatedDs.IsFullyApplied)
	})
}

func newDiscountService(t *testing.T) (DiscountServiceInterface, *fakes.MockDiscountEngineInterface, log.Logger) {
	_, _, _, logger, _ := helpers.SetupMocks(t)
	pegomock.RegisterMockTestingT(t)
	discountEngine := fakes.NewMockDiscountEngineInterface()

	return NewDiscountService(discountEngine), discountEngine, logger
}
