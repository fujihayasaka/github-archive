package engines

import (
	"context"
	"reflect"
	"testing"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/helpers"
)

func TestGetEnterpriseInfoFromBillingAndParentCustomers(t *testing.T) {
	// Define test cases
	tests := []struct {
		name            string
		billingCustomer *models.Customer // Replace with actual input type
		parentCustomer  *models.Customer
		expected        *models.EnterpriseInfo // Replace with actual output type
	}{
		{
			name:            "when the billing customer is nil",
			billingCustomer: nil,
			parentCustomer:  nil,
			expected:        nil,
		},
		{
			name: "when the billing customer is not a cost center proxy",
			billingCustomer: &models.Customer{
				CostCenterDetail: &models.CostCenterDetail{
					IsCostCenterProxy:    false,
					EnterpriseCustomerId: "123",
				},
			},
			parentCustomer: &models.Customer{
				CostCenterDetail: &models.CostCenterDetail{
					IsCostCenterProxy:    false,
					EnterpriseCustomerId: "456",
				},
			},
			expected: &models.EnterpriseInfo{
				EnterpriseCustomerId: "123",
			},
		}, {
			name: "when the billing customer is a cost center proxy",
			billingCustomer: &models.Customer{
				CostCenterDetail: &models.CostCenterDetail{
					IsCostCenterProxy:    true,
					EnterpriseCustomerId: "123",
				},
			},
			parentCustomer: &models.Customer{
				CostCenterDetail: &models.CostCenterDetail{
					IsCostCenterProxy:    false,
					EnterpriseCustomerId: "456",
				},
			},
			expected: &models.EnterpriseInfo{
				EnterpriseCustomerId: "456",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, telem, stats, logger, db := helpers.SetupMocks(t)
			cfg := &config.Config{
				Environment: "test",
			}

			engineParams := &EngineParams{
				db:             db,
				cfg:            cfg,
				aqueductClient: nil,
				statter:        stats,
				tracer:         telem.Tracer.Tracer,
			}

			customerEngine := NewCustomerEngine(engineParams)
			result := customerEngine.GetEnterpriseInfoFromBillingAndParentCustomers(context.Background(), logger, tt.billingCustomer, tt.parentCustomer)
			if !reflect.DeepEqual(result, tt.expected) {
				t.Errorf("GetEnterpriseInfoFromBillingAndParentCustomers(%v, %v) = %v; want %v", tt.billingCustomer, tt.parentCustomer, result, tt.expected)
			}
		})
	}
}
