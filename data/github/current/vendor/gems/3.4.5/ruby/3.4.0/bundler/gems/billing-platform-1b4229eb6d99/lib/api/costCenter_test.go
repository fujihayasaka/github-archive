package api

import (
	"context"
	"errors"
	"testing"

	"github.com/github/billing-platform/lib/bperrors"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/testing/fakes"
	"github.com/github/billing-platform/testing/helpers"
	"github.com/github/github-telemetry-go/log"
	"github.com/petergtz/pegomock/v4"
	"github.com/stretchr/testify/assert"
)

func Test_GetAllCostCenters_Cache(t *testing.T) {
	_, telem, _, logger, _ := helpers.SetupMocks(t)
	mocker := pegomock.WithT(t)

	tests := []struct {
		name       string
		customerId string
		useCache   bool
	}{
		{
			name:       "use cache",
			customerId: "1",
			useCache:   true,
		},
		{
			name:       "do not use cache",
			customerId: "1",
			useCache:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockCostCenterEngine := fakes.NewMockCostCenterEngineInterface(mocker)
			customerAPI := NewCostCenterAPI(mockCostCenterEngine, nil, logger, telem.Tracer.Tracer)

			response, err := customerAPI.GetAllCostCenters(context.Background(), &proto.GetAllCostCentersRequest{
				CustomerId: tt.customerId,
				UseCache:   tt.useCache,
			})

			if tt.useCache {
				mockCostCenterEngine.VerifyWasCalledOnce().GetAllCostCentersFromCache(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Customer]())
			} else {
				mockCostCenterEngine.VerifyWasCalledOnce().GetAllCostCenters(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[*models.Customer]())
			}

			assert.Equal(t, 0, len(response.CostCenters))
			assert.Nil(t, err)
		})
	}
}

func Test_ArchiveCostCenter(t *testing.T) {
	_, telem, _, logger, _ := helpers.SetupMocks(t)
	mocker := pegomock.WithT(t)

	tests := []struct {
		name                 string
		request              *proto.ArchiveCostCenterRequest
		customer             *models.Customer
		costCenter           *models.CostCenter
		getCustomerErr       bool
		custUpsertErr        bool
		getCostCenterErr     bool
		archiveCostCenterErr bool
	}{
		{
			name: "cost center successfully archived",
			request: &proto.ArchiveCostCenterRequest{
				CostCenterKey: &proto.CostCenterKey{
					CustomerId: "123",
					TargetType: proto.CostCenterType_ZuoraSubscription,
					TargetId:   "456",
					Uuid:       "1",
				},
			},
			customer: &models.Customer{
				Key: models.NewKeyFromPartitionKey("customer:123"),
				CostCenterDetail: &models.CostCenterDetail{
					CostCenterState: models.CostCenterActive,
				},
			},
			costCenter: &models.CostCenter{
				Name: "testCenter",
			},
		},
		{
			name: "customer not found",
			request: &proto.ArchiveCostCenterRequest{
				CostCenterKey: &proto.CostCenterKey{
					CustomerId: "123",
					TargetType: proto.CostCenterType_ZuoraSubscription,
					TargetId:   "456",
					Uuid:       "1",
				},
			},
			customer: nil,
		},
		{
			name: "get customer error",
			request: &proto.ArchiveCostCenterRequest{
				CostCenterKey: &proto.CostCenterKey{
					CustomerId: "123",
					TargetType: proto.CostCenterType_ZuoraSubscription,
					TargetId:   "456",
					Uuid:       "1",
				},
			},
			customer:       &models.Customer{},
			getCustomerErr: true,
		},
		{
			name: "customer upsert error",
			request: &proto.ArchiveCostCenterRequest{
				CostCenterKey: &proto.CostCenterKey{
					CustomerId: "123",
					TargetType: proto.CostCenterType_ZuoraSubscription,
					TargetId:   "456",
					Uuid:       "1",
				},
			},
			customer: &models.Customer{
				Key: models.NewKeyFromPartitionKey("customer:123"),
				CostCenterDetail: &models.CostCenterDetail{
					CostCenterState: models.CostCenterActive,
				},
			},
			custUpsertErr: true,
		},
		{
			name: "cost center not found",
			request: &proto.ArchiveCostCenterRequest{
				CostCenterKey: &proto.CostCenterKey{
					CustomerId: "123",
					TargetType: proto.CostCenterType_ZuoraSubscription,
					TargetId:   "456",
					Uuid:       "1",
				},
			},
			customer: &models.Customer{
				Key: models.NewKeyFromPartitionKey("customer:123"),
				CostCenterDetail: &models.CostCenterDetail{
					CostCenterState: models.CostCenterActive,
				},
			},
			costCenter: nil,
		},
		{
			name: "get cost center error",
			request: &proto.ArchiveCostCenterRequest{
				CostCenterKey: &proto.CostCenterKey{
					CustomerId: "123",
					TargetType: proto.CostCenterType_ZuoraSubscription,
					TargetId:   "456",
					Uuid:       "1",
				},
			},
			customer: &models.Customer{
				Key: models.NewKeyFromPartitionKey("customer:123"),
				CostCenterDetail: &models.CostCenterDetail{
					CostCenterState: models.CostCenterActive,
				},
			},
			getCostCenterErr: true,
		},
		{
			name: "archive cost center error",
			request: &proto.ArchiveCostCenterRequest{
				CostCenterKey: &proto.CostCenterKey{
					CustomerId: "123",
					TargetType: proto.CostCenterType_ZuoraSubscription,
					TargetId:   "456",
					Uuid:       "1",
				},
			},
			customer: &models.Customer{
				Key: models.NewKeyFromPartitionKey("customer:123"),
				CostCenterDetail: &models.CostCenterDetail{
					CostCenterState: models.CostCenterActive,
				},
			},
			costCenter: &models.CostCenter{
				Name: "testCenter",
			},
			archiveCostCenterErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockCostCenterEngine := fakes.NewMockCostCenterEngineInterface(mocker)
			mockCustomerEngine := fakes.NewMockCustomerEngineInterface(mocker)
			costCenterAPI := NewCostCenterAPI(mockCostCenterEngine, mockCustomerEngine, logger, telem.Tracer.Tracer)

			if tt.getCustomerErr {
				pegomock.When(mockCustomerEngine.Get(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[string](), pegomock.Eq(false))).ThenReturn(nil, errors.New("error getting customer"))
			} else {
				pegomock.When(mockCustomerEngine.Get(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Any[string](), pegomock.Eq(false))).ThenReturn(tt.customer, nil)
			}

			if tt.custUpsertErr {
				pegomock.When(mockCustomerEngine.Upsert(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Eq(tt.customer))).ThenReturn(errors.New("upsert failed"))
			} else {
				pegomock.When(mockCustomerEngine.Upsert(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Eq(tt.customer))).ThenReturn(nil)
			}

			ccKey := models.NewCostCenterKey(tt.request.CostCenterKey, false)
			if tt.getCostCenterErr {
				pegomock.When(mockCostCenterEngine.Get(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Eq(ccKey))).ThenReturn(nil, errors.New("error getting cost center"))
			} else {
				pegomock.When(mockCostCenterEngine.Get(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Eq(ccKey))).ThenReturn(tt.costCenter, nil)
			}

			if tt.archiveCostCenterErr {
				pegomock.When(mockCostCenterEngine.ArchiveCostCenter(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Eq(tt.costCenter))).ThenReturn(bperrors.NewError(bperrors.NotFound, errors.New("error archiving cost center")))
			} else {
				pegomock.When(mockCostCenterEngine.ArchiveCostCenter(pegomock.Any[context.Context](), pegomock.Any[log.Logger](), pegomock.Eq(tt.costCenter))).ThenReturn(nil)
			}

			resp, err := costCenterAPI.ArchiveCostCenter(context.Background(), tt.request)

			if tt.customer == nil || tt.getCustomerErr || tt.custUpsertErr || tt.getCostCenterErr || tt.costCenter == nil || tt.archiveCostCenterErr {
				assert.NotNil(t, err)
				assert.Nil(t, resp)
				return
			}

			assert.Nil(t, err)
			assert.Equal(t, &proto.ArchiveCostCenterResponse{}, resp)
		})
	}
}
