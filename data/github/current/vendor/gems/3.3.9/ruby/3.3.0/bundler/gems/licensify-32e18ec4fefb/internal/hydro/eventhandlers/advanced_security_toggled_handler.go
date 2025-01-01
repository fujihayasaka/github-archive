package eventhandlers

import (
	"context"
	"strconv"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	security_centerv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/lib/globalid"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"go.opentelemetry.io/otel/trace"
)

// HandleAdvancedSecurityToggled handles the AdvancedSecurityToggled message.
func (eh *EventHandler) HandleAdvancedSecurityToggled(ctx context.Context, logger log.Logger, message *security_centerv0.AdvancedSecurityToggled, envelope *schemas.Envelope) (Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	repoID := message.GetRepositoryId()
	customerID := message.GetCustomerId()

	logger = logger.WithFields(
		kvp.Int64("gh.hydro.msg.repository.id", repoID),
		kvp.Int64("gh.hydro.msg.customer.id", customerID),
	)
	logger.Info("Begin handle advanced security toggled")

	if customerID == 0 {
		return Skip{
			reason: "customer ID is 0",
			tags:   stats.Tags{"reason": "missing-customer-id"},
		}, Error{}
	}
	if repoID == 0 {
		return Skip{
			reason: "repository ID is 0",
			tags:   stats.Tags{"reason": "missing-repository-id"},
		}, Error{}
	}

	enabledAt := envelope.Timestamp
	featureEnabled := message.GetFeatureEnabled()
	if !featureEnabled {
		enabledAt = nil
	}

	// Create the global ID for the product enablement
	// Mirrors the rails global ID format https://github.com/rails/globalid
	globalID := &globalid.GlobalID{
		App:       "git-hub",
		ModelName: "Repository",
		ModelID:   strconv.FormatInt(repoID, 10),
	}

	productEnablement := models.NewProductEnablementFromProto(&proto.ProductEnablement{
		CustomerId:     uint64(customerID),
		Product:        proto.Product_PRODUCT_GHAS,
		EnablementId:   uint64(repoID),
		EnablementType: proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_REPO,
		GlobalId:       globalID.String(),
		EnabledAt:      enabledAt,
	})

	err := eh.productEnablementEngine.Upsert(ctx, logger, productEnablement, nil)
	if err != nil {
		return Skip{}, Error{Err: err, span: sp, origin: "upsert-product-enablement"}
	}

	logger.Info("End handle advanced security toggled")
	return Skip{}, Error{}
}
