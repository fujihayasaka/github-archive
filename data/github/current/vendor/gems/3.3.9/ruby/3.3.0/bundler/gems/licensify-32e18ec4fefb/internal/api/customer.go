// Package api provides the API handlers for the Licensify service.
package api

import (
	"context"
	"strings"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/twitchtv/twirp"
)

// CustomerAPI provides the API handlers for the Customer service.
type CustomerAPI struct {
	customerEngine *engines.CustomerEngine
	aqueductClient aqueduct.Client
	logger         log.Logger
	cfg            *config.Config
}

// NewCustomerAPI creates a new CustomerAPI.
func NewCustomerAPI(customerEngine *engines.CustomerEngine, aqueductClient aqueduct.Client, logger log.Logger, cfg *config.Config) *CustomerAPI {
	return &CustomerAPI{
		customerEngine: customerEngine,
		aqueductClient: aqueductClient,
		logger:         logger,
		cfg:            cfg,
	}
}

// UpsertCustomer upserts a customer.
func (api *CustomerAPI) UpsertCustomer(ctx context.Context, request *proto.UpsertCustomerRequest) (*proto.UpsertCustomerResponse, error) {
	customer := models.NewCustomerFromProto(request.Customer)

	if errors := customer.IsValid(); len(errors) != 0 {
		return nil, twirp.RequiredArgumentError(strings.Join(errors, ", "))
	}

	err := api.customerEngine.Upsert(ctx, api.logger, customer, nil)
	if err != nil {
		return nil, err
	}

	return &proto.UpsertCustomerResponse{}, nil
}
