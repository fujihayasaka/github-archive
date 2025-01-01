package engines

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	statsmocks "github.com/github/go-stats/mocks"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"go.opentelemetry.io/otel/trace"
)

func Test_CalculateAmountExceedingDiscountState(t *testing.T) {
	mockContainer, mockDB, mockStatter, mockTracer := setupMocks(t)
	engine := NewDiscountEngine(&EngineParams{db: mockDB, statter: mockStatter, tracer: mockTracer}, nil, nil)

	baseDiscount := &models.Discount{
		DiscountKey: &models.DiscountKey{Key: &models.Key{Id: "testID"}, Uuid: "testUUID"},
		// in order for discount state IsValidFor to be true, the discount start and end date has to be within the current date
		StartDate: time.Now().Add(-24 * time.Hour).Unix(),
		EndDate:   time.Now().Add(24 * time.Hour).Unix(),
	}

	tests := []struct {
		name                                 string
		inputAmount                          int64
		inputDiscount                        *models.Discount
		queriedDiscountState                 *models.DiscountState
		shouldReturnError                    bool
		expectedAmountExceedingDiscountState int64
	}{
		{
			name:                                 "expected error when failed to read discount state",
			inputAmount:                          10,
			inputDiscount:                        baseDiscount,
			queriedDiscountState:                 &models.DiscountState{TargetAmount: 100},
			shouldReturnError:                    true,
			expectedAmountExceedingDiscountState: 0,
		},
		{
			name:                                 "expected 0 return when discount is fully applied",
			inputAmount:                          10,
			inputDiscount:                        baseDiscount,
			queriedDiscountState:                 &models.DiscountState{TargetAmount: 100, IsFullyApplied: true},
			shouldReturnError:                    false,
			expectedAmountExceedingDiscountState: 0,
		},
		{
			name:        "expected 0 return when discount is percentage",
			inputAmount: 10,
			inputDiscount: &models.Discount{
				DiscountKey: baseDiscount.DiscountKey,
				StartDate:   baseDiscount.StartDate,
				EndDate:     baseDiscount.EndDate,
				Percentage:  100,
			},
			queriedDiscountState:                 &models.DiscountState{TargetAmount: 100},
			shouldReturnError:                    false,
			expectedAmountExceedingDiscountState: 0,
		},
		{
			name:        "expected 0 return when discount is not fully applied",
			inputAmount: 10,
			inputDiscount: &models.Discount{
				DiscountKey: baseDiscount.DiscountKey,
				StartDate:   baseDiscount.StartDate,
				EndDate:     baseDiscount.EndDate,
			},
			queriedDiscountState:                 &models.DiscountState{TargetAmount: 100},
			shouldReturnError:                    false,
			expectedAmountExceedingDiscountState: 0,
		},
		{
			name:        "expected non-zero return when discount exceeds target amount",
			inputAmount: 10,
			inputDiscount: &models.Discount{
				DiscountKey: baseDiscount.DiscountKey,
				StartDate:   baseDiscount.StartDate,
				EndDate:     baseDiscount.EndDate,
			},
			queriedDiscountState:                 &models.DiscountState{TargetAmount: 5},
			shouldReturnError:                    false,
			expectedAmountExceedingDiscountState: 5,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {

			discountStateReadItemMock := pegomock.When(
				mockContainer.ReadItem(
					pegomock.Any[context.Context](),
					// partition key
					pegomock.Eq(azcosmos.NewPartitionKeyString(fmt.Sprintf("customer:1:discounts:%s:2024:11", tt.inputDiscount.DiscountKey.Uuid))),
					// id
					pegomock.Eq("discountState"),
					pegomock.Any[*azcosmos.ItemOptions](),
				),
			)

			if tt.shouldReturnError {
				discountStateReadItemMock.ThenReturn(
					helpers.MockAzureItemResponse(t, tt.queriedDiscountState),
					errors.New("failed to read discount state"),
				)
			} else {
				discountStateReadItemMock.ThenReturn(
					helpers.MockAzureItemResponse(t, tt.queriedDiscountState),
					nil,
				)
			}

			amountExceedingDiscountState, err := engine.CalculateAmountExceedingDiscountState(
				context.TODO(),
				log.NewNullLogger(),
				"1",
				tt.inputDiscount,
				10,
				2024,
				11,
			)

			if tt.shouldReturnError {
				assert.Error(t, err)
			} else {
				assert.Nil(t, err)
			}

			assert.Equal(t, tt.expectedAmountExceedingDiscountState, amountExceedingDiscountState)
		})
	}
}

func Test_UpdateDiscountState(t *testing.T) {
	baseDiscount := &models.Discount{
		DiscountKey: &models.DiscountKey{Key: &models.Key{Id: "testUUID"}, Uuid: "testUUID"},
		// in order for discount state IsValidFor to be true, the discount start and end date has to be within the current date
		StartDate: time.Now().Add(-24 * time.Hour).Unix(),
		EndDate:   time.Now().Add(24 * time.Hour).Unix(),
	}

	basePercentageDiscount := &models.Discount{
		DiscountKey: &models.DiscountKey{Key: &models.Key{Id: "testUUID"}, Uuid: "testUUID"},
		// in order for discount state IsValidFor to be true, the discount start and end date has to be within the current date
		StartDate:  time.Now().Add(-24 * time.Hour).Unix(),
		EndDate:    time.Now().Add(24 * time.Hour).Unix(),
		Percentage: 100,
	}

	tests := []struct {
		name                                     string
		inputPayload                             models.UpdateDiscountStatePayload
		shouldReturnError                        bool
		shouldCreateDiscountState                bool
		shouldPatchDiscountState                 bool
		shouldPatchDiscountStateWithFullyApplied bool
		shouldCountOverageAmount                 bool
		queriedDiscountState                     *models.DiscountState
	}{
		{
			name:                 "expected error when failed to read discount state",
			inputPayload:         models.UpdateDiscountStatePayload{Discount: baseDiscount, CustomerId: "1", Amount: 10, Year: 2024, Month: 11},
			queriedDiscountState: nil,
			shouldReturnError:    true,
		},
		{
			name:                      "create called when discount state does not exist",
			inputPayload:              models.UpdateDiscountStatePayload{Discount: baseDiscount, CustomerId: "1", Amount: 10, Year: 2024, Month: 11},
			queriedDiscountState:      nil,
			shouldCreateDiscountState: true,
		},
		{
			name:                     "patch called when discount state exists (has CosmosProperties)",
			inputPayload:             models.UpdateDiscountStatePayload{Discount: baseDiscount, CustomerId: "1", Amount: 10, Year: 2024, Month: 11},
			queriedDiscountState:     &models.DiscountState{TargetAmount: 100, CosmosProperties: &models.CosmosProperties{Timestamp: 1}},
			shouldPatchDiscountState: true,
		},
		{
			name:                                     "patch called with IsFullyApplied set to true when discount state is newly fully applied",
			inputPayload:                             models.UpdateDiscountStatePayload{Discount: baseDiscount, CustomerId: "1", Amount: 10, Year: 2024, Month: 11},
			queriedDiscountState:                     &models.DiscountState{TargetAmount: 10, CosmosProperties: &models.CosmosProperties{Timestamp: 1}},
			shouldPatchDiscountStateWithFullyApplied: true,
		},
		{
			name:                     "patch not called with IsFullyApplied set to true when percentage discount",
			inputPayload:             models.UpdateDiscountStatePayload{Discount: basePercentageDiscount, CustomerId: "1", Amount: 10, Year: 2024, Month: 11},
			queriedDiscountState:     &models.DiscountState{TargetAmount: 10, CosmosProperties: &models.CosmosProperties{Timestamp: 1}},
			shouldPatchDiscountState: true,
		},
		{
			name:                     "metric client count called with discount state overage amount",
			inputPayload:             models.UpdateDiscountStatePayload{Discount: baseDiscount, CustomerId: "1", Amount: 10, Year: 2024, Month: 11},
			queriedDiscountState:     &models.DiscountState{TargetAmount: 25, CurrentAmount: 20, CosmosProperties: &models.CosmosProperties{Timestamp: 1}},
			shouldCountOverageAmount: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockContainer, mockDB, mockStatter, _ := setupMocks(t)
			engine := NewDiscountEngine(&EngineParams{db: mockDB, statter: mockStatter}, nil, nil)

			discountStateReadItemMock := pegomock.When(
				mockContainer.ReadItem(
					pegomock.Any[context.Context](),
					// partition key
					pegomock.Eq(azcosmos.NewPartitionKeyString(fmt.Sprintf("customer:1:discounts:%s:2024:11", tt.inputPayload.Discount.DiscountKey.Uuid))),
					// id
					pegomock.Eq("discountState"),
					pegomock.Any[*azcosmos.ItemOptions](),
				),
			)

			if tt.shouldReturnError {
				discountStateReadItemMock.ThenReturn(
					helpers.MockAzureItemResponse(t, tt.queriedDiscountState),
					errors.New("failed to read discount state"),
				)
			} else {
				discountStateReadItemMock.ThenReturn(
					helpers.MockAzureItemResponse(t, tt.queriedDiscountState),
					nil,
				)
			}

			err := engine.UpdateDiscountState(
				context.TODO(),
				log.NewNullLogger(),
				tt.inputPayload,
			)

			if tt.shouldReturnError {
				assert.Error(t, err)
			} else {
				assert.Nil(t, err)
			}

			switch {
			case tt.shouldCreateDiscountState:
				mockDB.VerifyWasCalledOnce().CreateWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Any[*interfaces.QueryOptions](),
				)
			case tt.shouldPatchDiscountState:
				po := azcosmos.PatchOperations{}
				po.AppendIncrement("/CurrentAmount", tt.inputPayload.Amount)

				mockDB.VerifyWasCalledOnce().PatchWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Eq(po),
					pegomock.Any[*interfaces.QueryOptions](),
				)
			case tt.shouldPatchDiscountStateWithFullyApplied:
				po := azcosmos.PatchOperations{}
				po.AppendIncrement("/CurrentAmount", tt.inputPayload.Amount)
				po.AppendReplace("/IsFullyApplied", true)

				mockDB.VerifyWasCalledOnce().PatchWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Eq(po),
					pegomock.Any[*interfaces.QueryOptions](),
				)
			case tt.shouldCountOverageAmount:
				expectedOverageAmount := tt.queriedDiscountState.CurrentAmount + tt.inputPayload.Amount - tt.queriedDiscountState.TargetAmount
				mockStatter.AssertCalled(t, "Counter", "discount.state.overage_amount", stats.Tags{}, expectedOverageAmount)
			}
		})
	}
}

func Test_GetDiscountState(t *testing.T) {
	mockContainer, mockDB, mockStatter, _ := setupMocks(t)
	engine := NewDiscountEngine(&EngineParams{db: mockDB, statter: mockStatter}, nil, nil)

	tests := []struct {
		name                 string
		queriedDiscountState *models.DiscountState
		shouldReturnError    bool
	}{
		{
			name:                 "expected error when failed to read discount state",
			queriedDiscountState: nil,
			shouldReturnError:    true,
		},
		{
			name:                 "returns existing discount state when found",
			queriedDiscountState: &models.DiscountState{TargetAmount: 100, CurrentAmount: 10},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			discountStateReadItemMock := pegomock.When(
				mockContainer.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Any[string](),
					pegomock.Any[*azcosmos.ItemOptions](),
				),
			)

			if tt.shouldReturnError {
				discountStateReadItemMock.ThenReturn(
					helpers.MockAzureItemResponse(t, tt.queriedDiscountState),
					errors.New("failed to read discount state"),
				)
			} else {
				discountStateReadItemMock.ThenReturn(
					helpers.MockAzureItemResponse(t, tt.queriedDiscountState),
					nil,
				)
			}

			discountState, err := engine.GetDiscountState(
				context.TODO(),
				log.NewNullLogger(),
				&models.DiscountKey{Key: &models.Key{Id: "testUUID"}},
				2024,
				11,
			)

			if tt.shouldReturnError {
				assert.Error(t, err)
				assert.Nil(t, discountState)
			} else {
				assert.Nil(t, err)
				assert.Equal(t, tt.queriedDiscountState, discountState)
			}
		})
	}
}

func setupMocks(t *testing.T) (*fakes.MockCosmosConnection, *fakes.MockDatabase, *statsmocks.Client, trace.Tracer) {
	mocker := pegomock.WithT(t)

	telem, err := telemetry.NewFromEnv()
	assert.NoError(t, err)

	mockStatter := statsmocks.Client{}
	mockStatter.Mock.On("WithTags", mock.AnythingOfType("stats.Tags")).Return(&mockStatter)
	mockStatter.Mock.On("Distribution", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("float64")).Return(nil)
	mockStatter.Mock.On("Counter", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Return(nil)
	mockStatter.Mock.On("Timing", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("time.Duration")).Return(nil)

	mockDB := fakes.NewMockDatabase(mocker)
	mockContainer := fakes.NewMockCosmosConnection(mocker)
	pegomock.When(mockDB.GetTracer()).ThenReturn(telem.Tracer.Tracer)
	pegomock.When(mockDB.GetConnection()).ThenReturn(mockContainer)
	pegomock.When(mockDB.GetGatewayConnection()).ThenReturn(mockContainer)
	pegomock.When(mockDB.GetStatter()).ThenReturn(&mockStatter)

	mockTracer := telem.Tracer.Tracer

	return mockContainer, mockDB, &mockStatter, mockTracer
}
