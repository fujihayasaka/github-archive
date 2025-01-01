package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/google/uuid"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
	//nolint:staticcheck
)

func TestBudgetStateHandler_ProcessMessage(t *testing.T) {
	tests := []struct {
		name               string
		item               *models.Item
		discountItem       *models.DiscountItem
		budget             *models.Budget
		budgetId           string
		budgetState        *models.BudgetState
		budgetStateId      string
		numDBCalls         int
		preConditionFailed bool
	}{
		{
			name: "Creates budget state when it doesn't exist and usage is for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "456", // this is a cost center id
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123", // this is the parent customer id
						CostCenterUUID:       "456",
						IsCostCenterProxy:    true,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets", // budgets are stored using the parent customer id
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId:           "customer:123:budgets:customer:123",
			budgetState:        nil,
			budgetStateId:      "budgetState",
			numDBCalls:         1,
			preConditionFailed: false,
		},
		{
			name: "Creates budget state when it doesn't exist and usage is not for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123",
						IsCostCenterProxy:    false,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets",
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId:           "customer:123:budgets:customer:123",
			budgetState:        nil,
			budgetStateId:      "budgetState",
			numDBCalls:         1,
			preConditionFailed: false,
		},
		{
			name: "Updates budget state when it does exist and usage is for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "456",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123",
						IsCostCenterProxy:    true,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets",
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId: "customer:123:budgets:customer:123",
			budgetState: &models.BudgetState{
				Key: &models.Key{
					Id:           "budgetId-123:2024:1",
					PartitionKey: "budgetState-pk",
				},
				Quantity:      10,
				CurrentAmount: 10,
				IsFullyFunded: false,
			},
			budgetStateId:      "budgetState",
			numDBCalls:         1,
			preConditionFailed: false,
		},
		{
			name: "Updates budget state when it does exist and usage is not for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123",
						IsCostCenterProxy:    false,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets",
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId: "customer:123:budgets:customer:123",
			budgetState: &models.BudgetState{
				Key: &models.Key{
					Id:           "budgetId-123:2024:1",
					PartitionKey: "budgetState-pk",
				},
				Quantity:      10,
				CurrentAmount: 10,
				IsFullyFunded: false,
			},
			budgetStateId:      "budgetState",
			numDBCalls:         1,
			preConditionFailed: false,
		},
		{
			name: "Updates budget state when it does exist and first pre-condition fails and usage is for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "456",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123",
						IsCostCenterProxy:    true,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets",
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId: "customer:123:budgets:customer:123",
			budgetState: &models.BudgetState{
				Key: &models.Key{
					Id:           "budgetId-123:2024:1",
					PartitionKey: "budgetState-pk",
				},
				Quantity:      10,
				CurrentAmount: 10,
				IsFullyFunded: false,
			},
			budgetStateId:      "budgetState",
			numDBCalls:         2,
			preConditionFailed: true,
		},
		{
			name: "Updates budget state when it does exist and first pre-condition fails and usage is not for a cost center",
			item: &models.Item{
				Amounts: &models.Amounts{
					Quantity: 10,
				},
				EntityDetail: &models.EntityDetail{
					CustomerId: "123",
					CostCenterDetail: &models.CostCenterDetail{
						EnterpriseCustomerId: "123",
						IsCostCenterProxy:    false,
					},
				},
			},
			budget: &models.Budget{
				BudgetKey: &models.BudgetKey{
					Key: &models.Key{
						Id:           "budgetId-123",
						PartitionKey: "customer:123:budgets",
					},
				},
				BudgetAlerting: &models.BudgetAlerting{
					WillAlert: true,
				},
				Uuid: uuid.NewString(),
			},
			budgetId: "customer:123:budgets:customer:123",
			budgetState: &models.BudgetState{
				Key: &models.Key{
					Id:           "budgetId-123:2024:1",
					PartitionKey: "budgetState-pk",
				},
				Quantity:      10,
				CurrentAmount: 10,
				IsFullyFunded: false,
			},
			budgetStateId:      "budgetState",
			numDBCalls:         2,
			preConditionFailed: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup mocks
			pegomock.RegisterMockTestingT(t)
			fakeContainer, telem, stats, l, db := helpers.SetupMocks(t)
			pegomock.When(db.GetTracer()).ThenReturn(telem.Tracer.Tracer)
			pegomock.When(db.GetConnection()).ThenReturn(fakeContainer)
			pegomock.When(db.GetStatter()).ThenReturn(stats)
			cfg := &config.Config{
				Environment: "test",
			}
			engineParams := engines.NewEngineParams(nil, cfg, db, nil, stats, nil, telem.Tracer.Tracer)
			events := make(chan hydro.Message, 100)
			sink, err := hydro.NewMemorySink(events)
			assert.Nil(t, err)
			hydroPublisher, err := hydro.NewPublisher(sink)
			assert.Nil(t, err)

			customerEngine := engines.NewCustomerEngine(engineParams)
			budgetEngine := engines.NewBudgetEngine(engineParams, customerEngine)

			vexiClient, _ := helpers.NewFeatureFlagClient(context.Background(), t, false)
			handler := &BudgetStateHandler{
				Handler: &Handler{
					HandlerParams: &HandlerParams{
						tracer:  telem.Tracer.Tracer,
						statter: stats,
						flagger: vexiClient,
						DB:      db,
					},
				},
				budgetEngine:   budgetEngine,
				hydroPublisher: hydroPublisher,
			}

			// mock the the return for a specific budget
			pegomock.When(
				fakeContainer.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Eq(tt.budgetId),
					pegomock.Any[*azcosmos.ItemOptions]()),
			).ThenReturn(
				helpers.StaticTestBudget(t, tt.budget), nil,
			)

			// mock the the return for a specific budget state
			pegomock.When(
				fakeContainer.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Any[azcosmos.PartitionKey](),
					pegomock.Eq(tt.budgetStateId),
					pegomock.Any[*azcosmos.ItemOptions]()),
			).ThenReturn(
				helpers.StaticTestBudgetState(t, tt.budgetState), nil,
			)

			// mock the return as 404 for all other budgets
			pegomock.When(
				fakeContainer.ReadItem(
					pegomock.Any[context.Context](),
					pegomock.Eq(azcosmos.NewPartitionKeyString(tt.budget.PartitionKey)),
					pegomock.NotEq(tt.budgetId),
					pegomock.Any[*azcosmos.ItemOptions]()),
			).ThenReturn(
				helpers.StaticTestBudget(t, nil), &azcore.ResponseError{StatusCode: http.StatusNotFound},
			)

			// simulate a pre-condition failure on the first call (etag mismatch due to race condition)
			if tt.preConditionFailed {
				pegomock.When(db.UpsertWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Any[*interfaces.QueryOptions](),
				)).ThenReturn(
					&azcore.ResponseError{StatusCode: http.StatusPreconditionFailed},
				).ThenReturn(nil)
			}
			payload := createBudgetStatePayload(*tt.budget, 2024, 1, "sku", tt.item.Amounts)
			err = handler.ProcessMessage(context.Background(), l, aqueduct.ReceiveResult{
				Job: aqueduct.Job{
					Payload: payload,
				},
				ValidPayload: true,
			})
			assert.Nil(t, err)

			if tt.budgetState == nil {
				db.VerifyWasCalled(pegomock.Times(tt.numDBCalls)).CreateWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Any[*interfaces.QueryOptions](),
				)
			} else {
				db.VerifyWasCalled(pegomock.Times(tt.numDBCalls)).UpsertWithOptions(
					pegomock.Any[context.Context](),
					pegomock.Any[log.Logger](),
					pegomock.Any[models.ItemKey](),
					pegomock.Any[*interfaces.QueryOptions](),
				)
			}
		})
	}
}

func createBudgetStatePayload(budget models.Budget, year int64, month int64, sku string, amount *models.Amounts) []byte {
	i := models.BudgetStateUpdateJob{
		Budget: &budget,
		Amount: amount,
		Year:   year,
		Month:  month,
		Sku:    sku,
	}
	p, _ := json.Marshal(&i)
	return p
}
