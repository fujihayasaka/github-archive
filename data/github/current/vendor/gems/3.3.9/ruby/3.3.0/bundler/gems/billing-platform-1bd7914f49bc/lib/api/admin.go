package api

import (
	"context"
	"fmt"
	"time"

	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
)

type AdminApi struct {
	adminEngine         *engines.AdminEngine
	azureEmissionEngine *engines.AzureEmissionEngine
	customerEngine      *engines.CustomerEngine
	logger              log.Logger
	pricingEngine       *engines.PricingEngine
}

func NewAdminAPI(
	adminEngine *engines.AdminEngine,
	azureEmissionEngine *engines.AzureEmissionEngine,
	customerEngine *engines.CustomerEngine,
	logger log.Logger,
	pricingEngine *engines.PricingEngine,
) *AdminApi {
	return &AdminApi{
		adminEngine:         adminEngine,
		azureEmissionEngine: azureEmissionEngine,
		customerEngine:      customerEngine,
		logger:              logger.Named("AdminApi"),
		pricingEngine:       pricingEngine,
	}
}

// ProcessDeadLetterQueue implements proto.AdminApi
func (api *AdminApi) ProcessDeadLetterQueue(ctx context.Context, input *proto.ProcessDeadLetterQueueRequest) (*proto.ProcessDeadLetterQueueResponse, error) {
	err := api.adminEngine.CreateProcessDeadLetterQueueRequest(ctx, api.logger, &models.ProcessDeadLetterQueueData{
		DeadLetterQueueName: input.QueueName,
		Num:                 input.Num,
	})

	if err != nil {
		return nil, err
	}

	return &proto.ProcessDeadLetterQueueResponse{
		Success: true,
	}, nil
}

// GetAzureEmission implements proto.AdminApi
func (api *AdminApi) GetAzureEmission(ctx context.Context, input *proto.GetAzureEmissionRequest) (*proto.GetAzureEmissionResponse, error) {
	azureEmission, err := api.azureEmissionEngine.GetAzureEmission(ctx, api.logger, &models.AzureEmissionPartitionDetail{
		CustomerId: input.CustomerId,
		Sku:        input.Sku,
		Year:       input.Year,
		Month:      input.Month,
		Day:        input.Day,
	})
	if err != nil {
		return nil, err
	}

	if azureEmission == nil {
		return &proto.GetAzureEmissionResponse{
			AzureEmission: &proto.AzureEmission{
				Status: proto.AzureEmissionStatus_New,
			},
		}, nil
	}

	return &proto.GetAzureEmissionResponse{
		AzureEmission: azureEmission.ToProto(),
	}, nil
}

// TriggerAzureEmission implements proto.AdminApi
func (api *AdminApi) TriggerAzureEmission(ctx context.Context, input *proto.TriggerAzureEmissionRequest) (*proto.TriggerAzureEmissionResponse, error) {
	now := time.Now().UTC()
	if input.Year <= 0 {
		return nil, fmt.Errorf("invalid year value provided")
	}

	if input.Month <= 0 {
		return nil, fmt.Errorf("invalid month value provided")
	}

	if input.Day <= 0 {
		return nil, fmt.Errorf("invalid day value provided")
	}

	inputTime := time.Date(int(input.Year), time.Month(input.Month), int(input.Day), 0, 0, 0, 0, time.UTC)

	if inputTime.After(now) {
		return nil, fmt.Errorf("cannot trigger emission for dates in the future")
	}

	// validate the customer ID if it exists
	if input.CustomerId != "" {
		customer, err := api.customerEngine.Get(ctx, api.logger, input.CustomerId)
		if err != nil {
			return nil, err
		}

		if customer == nil {
			return nil, fmt.Errorf("invalid customer ID provided")
		}
	}

	usageDate := &models.AzureUsageDate{
		CustomerId: input.CustomerId,
		Year:       input.Year,
		Month:      input.Month,
		Day:        input.Day,
	}

	err := api.adminEngine.CreateScheduleAzureEmissionRequest(ctx, api.logger, usageDate)

	if err != nil {
		return nil, err
	}

	return &proto.TriggerAzureEmissionResponse{
		Success: true,
	}, nil
}

func (api *AdminApi) TriggerInvoiceGeneration(ctx context.Context, input *proto.TriggerInvoiceGenerationRequest) (*proto.TriggerInvoiceGenerationResponse, error) {
	ipd := &models.InvoicePartitionDetail{
		CustomerId: input.CustomerId,
		Period:     models.InvoiceMonthly,
		Year:       input.Year,
		Month:      input.Month,
	}

	if !ipd.IsValid() {
		return nil, fmt.Errorf("invalid year/month provided")
	}

	// validate the customer ID if it exists
	if input.CustomerId != "" {
		customer, err := api.customerEngine.Get(ctx, api.logger, input.CustomerId)
		if err != nil {
			return nil, err
		}

		if customer == nil {
			return nil, fmt.Errorf("invalid customer ID provided")
		}
	}

	err := api.adminEngine.CreateScheduleInvoiceGenerationRequest(ctx, api.logger, ipd)

	if err != nil {
		return &proto.TriggerInvoiceGenerationResponse{
			Success: false,
		}, nil
	} else {

		return &proto.TriggerInvoiceGenerationResponse{
			Success: true,
		}, nil
	}
}

func (api *AdminApi) TriggerWatermarkWorkflow(ctx context.Context, input *proto.TriggerWatermarkWorkflowRequest) (*proto.TriggerWatermarkWorkflowResponse, error) {
	err := api.validateWatermarkWorkflowParams(input)
	if err != nil {
		return nil, err
	}

	// validate the customer ID if it exists
	if input.CustomerId != "" {
		customer, err := api.customerEngine.Get(ctx, api.logger, input.CustomerId)
		if err != nil {
			return nil, errors.Wrap(err, "Error getting customer")
		}

		if customer == nil {
			return nil, errors.New("Unable to find customer")
		}
	}

	// TODO: add validation to ensure requested SKU exists
	// if input.Sku != "" {
	// }

	watermarkJobRun := &models.WatermarkJobRun{
		Year:       int64(input.Year),
		Month:      int64(input.Month),
		Day:        int64(input.Day),
		Hour:       int64(input.Hour),
		CustomerId: input.CustomerId,
		Sku:        input.Sku,
	}

	err = api.adminEngine.CreateScheduleWatermarkJobsRequest(ctx, api.logger, watermarkJobRun)
	if err != nil {
		return nil, errors.Wrap(err, "Failed to trigger watermark workflow")
	}

	return &proto.TriggerWatermarkWorkflowResponse{
		Success: true,
	}, nil
}

func (api *AdminApi) validateWatermarkWorkflowParams(input *proto.TriggerWatermarkWorkflowRequest) error {
	now := time.Now().UTC()
	daysInMonth := time.Date(int(input.Year), time.Month(input.Month+1), 0, 0, 0, 0, 0, time.UTC).Day()

	if input.Year <= 0 || input.Year > int64(now.Year()) {
		return errors.New("Invalid year value provided")
	}

	afterCurrentMonth := (input.Year == int64(now.Year()) && input.Month > int64(now.Month()))
	if input.Month <= 0 || input.Month > 12 {
		return errors.New("Invalid month value provided")
	} else if afterCurrentMonth {
		return errors.New("Invalid month value provided - cannot be in the future")
	}

	afterEndOfMonth := input.Day > int64(daysInMonth)
	afterCurrentDay := input.Year == int64(now.Year()) && input.Month == int64(now.Month()) && input.Day > int64(now.Day())
	switch {
	case input.Day <= 0 || input.Day > 31:
		return errors.New("Invalid day value provided")
	case afterEndOfMonth:
		return errors.New("Invalid day value provided - exceeds days in month")
	case afterCurrentDay:
		return errors.New("Invalid day value provided - cannot be in the future")
	}

	afterCurrentHour := input.Year == int64(now.Year()) && input.Month == int64(now.Month()) && input.Day == int64(now.Day()) && input.Hour > int64(now.Hour())
	if input.Hour < 0 || input.Hour > 23 {
		return errors.New("Invalid hour value provided")
	} else if afterCurrentHour {
		return errors.New("Invalid hour value provided - cannot be in the future")
	}

	return nil
}

func (api *AdminApi) GenerateUsage(ctx context.Context, input *proto.GenerateUsageRequest) (*proto.GenerateUsageResponse, error) {
	err := api.validateGenerateUsageParams(input)
	if err != nil {
		return nil, err
	}

	customer, err := api.customerEngine.Get(ctx, api.logger, input.CustomerId)
	if err != nil {
		return nil, err
	}
	if customer == nil {
		return nil, errors.New("Unable to find customer")
	}

	foundPricing, err := api.pricingEngine.GetPricing(ctx, api.logger, input.Sku, true)
	if err != nil {
		return nil, err
	}
	if foundPricing == nil {
		return nil, errors.New("Unable to find pricing")
	}

	quantity := api.getChargeQuantity(input, foundPricing)

	err = api.adminEngine.GenerateUsage(ctx, api.logger, customer, input.OrgId, input.RepoId, foundPricing, *quantity)
	if err != nil {
		return nil, errors.Wrap(err, "Failed to create charge")
	}

	return &proto.GenerateUsageResponse{
		Success: true,
	}, nil
}

func (api *AdminApi) TriggerHighWatermarkRolloverJob(ctx context.Context, input *proto.TriggerHighWatermarkRolloverRequest) (*proto.TriggerHighWatermarkRolloverResponse, error) {
	err := api.validateHighWatermarkRolloverJobParams(input)
	if err != nil {
		return nil, err
	}

	if input.CustomerId != "" {
		customer, err := api.customerEngine.Get(ctx, api.logger, input.CustomerId)
		if err != nil {
			return nil, errors.Wrap(err, "Error getting customer")
		}

		if customer == nil {
			return nil, errors.New("Unable to find customer")
		}
	}

	rolloverJobRun := &models.HighWatermarkRolloverJobRun{
		Year:       int64(input.Year),
		Month:      int64(input.Month),
		CustomerId: input.CustomerId,
		Sku:        input.Sku,
		DryRun:     input.DryRun,
	}

	err = api.adminEngine.CreateScheduleHighWatermarkRolloverJobRequest(ctx, api.logger, rolloverJobRun)
	if err != nil {
		return &proto.TriggerHighWatermarkRolloverResponse{
			Success: false,
		}, nil
	} else {
		return &proto.TriggerHighWatermarkRolloverResponse{
			Success: true,
		}, nil
	}
}

func (api *AdminApi) validateGenerateUsageParams(input *proto.GenerateUsageRequest) error {
	// must set only one of the possible value params
	if input.Amount != 0.0 && input.Quantity != 0.0 {
		return errors.New("Must set only one of Amount or Quantity")
	}

	return nil
}

// Returns the quantity to charge for a given charge request.
// If the quantity is set, use that as a nano.
// Otherwise, use the amount and divide by the price.
func (api *AdminApi) getChargeQuantity(input *proto.GenerateUsageRequest, pricing *models.Pricing) *nano.Nano {
	if input.Quantity != 0.0 {
		return nano.NewFromFloat(float64(input.Quantity))
	}

	amount := nano.NewFromFloat(float64(input.Amount))
	price := nano.NewFromInt(pricing.GetPrice())
	return amount.Div(price)
}

func (api *AdminApi) validateHighWatermarkRolloverJobParams(input *proto.TriggerHighWatermarkRolloverRequest) error {
	now := time.Now().UTC()

	if input.Year < 1 || input.Year > int64(now.Year()+1) {
		return errors.New("Invalid year value provided")
	}

	if input.Month < 1 || input.Month > 12 {
		return errors.New("Invalid month value provided")
	}

	return nil
}
