// Package handlers provides the handlers for aqueduct jobs.
package handlers

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/trace"
)

// ProductEnablementUpdatedHandler is an aqueduct message handler for product enablement updates.
type ProductEnablementUpdatedHandler struct {
	productEnablementEngine *engines.ProductEnablementEngine
	statter                 stats.Client
	tracer                  trace.Tracer
}

// NewProductEnablementUpdatedHandler creates a new ProductEnablementUpdatedHandler.
func NewProductEnablementUpdatedHandler(productEnablementEngine *engines.ProductEnablementEngine, statter stats.Client, tracer trace.Tracer) *ProductEnablementUpdatedHandler {
	return &ProductEnablementUpdatedHandler{
		productEnablementEngine: productEnablementEngine,
		statter:                 statter,
		tracer:                  tracer,
	}
}

type productEnablementUpdatedMessage struct {
	models.Key
}

// ProcessMessage takes an aqueduct message for an product enablement being updated and updates the customer licenses.
func (h *ProductEnablementUpdatedHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	logger.Debug("Processing message", kvp.String("payload", string(rr.Payload)))

	var key *productEnablementUpdatedMessage
	if err := json.Unmarshal(rr.Payload, &key); err != nil {
		logger.WithError(err).Error("Failed to unmarshal message")
		return err
	}
	logger.Debug("Unmarshaled message", kvp.String("key", fmt.Sprintf("%+v", key)))

	// TODO: Implement the logic to update the customer licenses here

	logger.Info("Finished processing message")
	return nil
}
