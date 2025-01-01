// Package handlers provides the handlers for aqueduct jobs.
package handlers

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	billingplatformv1 "github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1"
	entities "github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1/entities"
	licensifyv0 "github.com/github/hydro-schemas-go/hydro/schemas/licensify/v0"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/interfaces"
	"github.com/github/licensify/internal/models"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// BillingPlatformCustomerIDs is a temporary list of customer IDs that should emit usage to the billing-platform for testing.
// These customers will be doubled billed through dotcom and licensify, so only add test accounts.
var BillingPlatformCustomerIDs = map[string]map[uint64]struct{}{
	"production": {
		10606098: {}, // metered, https://admin.github.com/stafftools/enterprises/licensing-metered-test
		15831447: {}, // metered, https://admin.github.com/stafftools/enterprises/lj-test-trial-20241017
		4285800:  {}, // volume, https://admin.github.com/stafftools/enterprises/flavortown-ltd
	},
	"staff-wus2-01": {
		206: {}, // metered, https://stafftoolswus2.ghe.com/stafftools/enterprises/licensing-test
	},
	"prod-weu-01": {
		321: {}, // metered, https://stafftools-prodweu01.ghe.com/stafftools/enterprises/billing-test
	},
	"prod-sdc-01": {
		71: {}, // metered, https://stafftools-prodsdc01.ghe.com/stafftools/enterprises/billing-sweden-test-09042024
	},
}

// PublishEmissionHandler is an aqueduct message handler for publishing emissions.
type PublishEmissionHandler struct {
	cfg                   *config.Config
	customerEngine        *engines.CustomerEngine
	customerLicenseEngine *engines.CustomerLicenseEngine
	featuresClient        twirpFeatures.FeaturesAPI
	hydroPublisher        interfaces.HydroPublisher
	statter               stats.Client
	tracer                trace.Tracer
}

// NewPublishEmissionHandler creates a new PublishEmissionHandler.
func NewPublishEmissionHandler(
	cfg *config.Config,
	customerEngine *engines.CustomerEngine,
	customerLicenseEngine *engines.CustomerLicenseEngine,
	featuresClient twirpFeatures.FeaturesAPI,
	hydroPublisher interfaces.HydroPublisher,
	statter stats.Client,
	tracer trace.Tracer,
) *PublishEmissionHandler {
	return &PublishEmissionHandler{
		cfg:                   cfg,
		customerEngine:        customerEngine,
		customerLicenseEngine: customerLicenseEngine,
		featuresClient:        featuresClient,
		hydroPublisher:        hydroPublisher,
		statter:               statter,
		tracer:                tracer,
	}
}

// ProcessMessage takes an aqueduct message for publishing emissions.
// For each license, it publishes to a test hydro topic (licensify.v0.TestLicenseUsage) and optionally to the billing platform (billingplatform.v1.Usage).
func (h *PublishEmissionHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	ctx, sp := h.tracer.Start(ctx, "PublishEmissionHandler.ProcessMessage")
	defer sp.End()

	var msg *models.PublishEmissionJob
	if err := json.Unmarshal(rr.Payload, &msg); err != nil {
		logger.WithError(err).Error("Failed to unmarshal message")
		return fmt.Errorf("failed to unmarshal message: %w", err)
	}

	emitToBillingPlatform, err := h.shouldEmitToBillingPlatform(ctx, msg.CustomerID)
	if err != nil {
		h.trackError(err, "check-feature-flag-error", sp, logger)
		return err
	}

	logger = logger.WithFields(msg.GetLoggerFields()...)
	logger = logger.WithFields(
		kvp.Bool("licensify.emit_to_billing_platform", emitToBillingPlatform),
	)
	logger.Info("Processing publish emission message", kvp.String("gh.aqueduct.job.payload", fmt.Sprintf("%+v", *msg)))

	// Calculate the quantity for the license usage message
	unixTime := time.Unix(msg.UsageTime, 0)
	usageTime := models.NewUsageTimeFromTime(unixTime)
	entityQuantity := 1.0 / float64(usageTime.BillableDaysInMonth())

	// Get the customer licenses
	licenses, err := h.customerLicenseEngine.GetAllWithEnablementReasonsOrHighWatermark(
		ctx,
		logger,
		msg.CustomerID,
		models.ProductSDLC,
	)

	if err != nil {
		err = fmt.Errorf("failed to get customer licenses: %w", err)
		h.trackError(err, "get-customer-licenses", sp, logger)
		return err
	}

	logger.Info("Found customer licenses", kvp.Int("count", len(licenses)))

	failedMessages := make([]protoreflect.ProtoMessage, 0)
	succeededMessages := make([]protoreflect.ProtoMessage, 0)

	// For each license, create and publish a license usage message
	for _, license := range licenses {
		messages := h.buildUsageMessages(
			msg.CustomerID,
			license,
			unixTime,
			entityQuantity,
			emitToBillingPlatform,
		)

		// Publish the license usage messages
		for _, msg := range messages {
			err = h.hydroPublisher.Publish(msg)
			if err == nil {
				schemaName := msg.ProtoReflect().Descriptor().FullName()
				logger.Info("published emission message",
					kvp.String("gh.hydro.payload", fmt.Sprintf("%+v", msg)),
					kvp.String("gh.hydro.topic", string(schemaName)),
				)
				h.statter.Counter("publish_emission_handler.published_events", stats.Tags{"topic": string(schemaName)}, int64(1))
				succeededMessages = append(succeededMessages, msg)
			} else {
				h.trackError(err, "publish-emission-error", sp, logger)
				failedMessages = append(failedMessages, msg)
			}
		}
	}

	logger.Info("Publish emission message processed successfully",
		kvp.Int("publish_emission_handler.successfully_published_count", len(succeededMessages)),
		kvp.Int("publish_emission_handler.failed_published_count", len(failedMessages)),
	)

	if len(failedMessages) > 0 {
		return fmt.Errorf("failed to publish emission messages for licenses: %v", failedMessages)
	}

	return nil
}

func (h *PublishEmissionHandler) buildUsageMessages(customerID uint64, license *models.CustomerLicense, usageTime time.Time, quantity float64, emitToBillingPlatform bool) []protoreflect.ProtoMessage {
	const sku = "ghec_licenses"
	messages := make([]protoreflect.ProtoMessage, 0, 2)
	usageUUID := h.createBillingUsageUUID(
		usageTime,
		models.ProductSDLC,
		customerID,
		license.Licensee,
	)
	entity := &entities.EntityDetail{
		ActorId:    license.LicenseeIDToInt64(),
		CustomerId: license.CustomerIDToInt64(),
	}

	testUsage := &licensifyv0.TestLicenseUsage{
		Entity:    entity,
		Quantity:  quantity,
		Sku:       sku,
		SourceUri: license.Licensee.GlobalID.String(),
		UsageAt:   timestamppb.New(usageTime),
		UsageUuid: usageUUID,
	}
	messages = append(messages, testUsage)

	if emitToBillingPlatform {
		usage := &billingplatformv1.Usage{
			Entity:    entity,
			Quantity:  quantity,
			Sku:       sku,
			SourceUri: license.Licensee.GlobalID.String(),
			UsageAt:   timestamppb.New(usageTime),
			UsageUuid: usageUUID,
		}
		messages = append(messages, usage)
	}
	return messages
}

func (h *PublishEmissionHandler) shouldEmitToBillingPlatform(ctx context.Context, customerID uint64) (bool, error) {
	// Check if customer ID is in the list of test customer IDs, these customers are double billed through dotcom and licensify
	if foundCustomerIDs, ok := BillingPlatformCustomerIDs[h.cfg.HeavenEnv]; ok {
		if _, ok = foundCustomerIDs[customerID]; ok {
			return true, nil
		}
	}

	// Check if the feature flag is enabled for the customer, these customers are only billed through licensify
	req := &twirpFeatures.CheckActorFeatureRequest{
		ActorId: fmt.Sprintf("Customer:%d", customerID),
		Feature: "ghec_bill_through_licensify",
	}
	resp, err := h.featuresClient.CheckActorFeature(ctx, req)
	if err != nil {
		return false, fmt.Errorf("failed to check feature flag: %w", err)
	}
	h.statter.Counter("publish_emission_handler.ghec_bill_through_licensify", stats.Tags{"enabled": fmt.Sprint(resp.IsEnabled)}, int64(1))
	return resp.IsEnabled, nil
}

// CreateBillingUsageUUID generates a UUID-like string using SHA256 that is consistent for the same inputs.
func (h *PublishEmissionHandler) createBillingUsageUUID(t time.Time, product models.Product, customerID uint64, licensee *models.Licensee) string {
	// Format the time as a string
	dateStr := t.Format("01/02/2006:15:04:05")

	// Create the string to hash, ex: "sdlc:1:user:1:01/23/2006:15:04:05"
	toHash := fmt.Sprintf("%s:%d:%s:%s:%s", product, customerID, licensee.Type, licensee.ID, dateStr)

	// Hash the string using SHA256
	hash := sha256.Sum256([]byte(toHash))

	// Convert the hash to a hexadecimal string
	return hex.EncodeToString(hash[:])
}

func (h *PublishEmissionHandler) trackError(err error, origin string, span trace.Span, logger log.Logger) {
	h.statter.Counter("publish_emission_error",
		stats.Tags{"origin": origin},
		int64(1),
	)
	logger.WithError(err).Error("error processing PublishEmission message")
	span.RecordError(err)
	span.SetStatus(codes.Error, origin)
}
