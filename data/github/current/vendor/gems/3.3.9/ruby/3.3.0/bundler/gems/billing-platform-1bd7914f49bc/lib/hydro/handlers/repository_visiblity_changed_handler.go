package handlers

import (
	"context"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/github/repositories/v1"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	schemas "github.com/github/hydro-client-go/v5/generated/hydro/schemas/hydro/v1"
	"github.com/golang/protobuf/proto" //nolint:staticcheck
	"github.com/pkg/errors"
)

type RepositoryVisibilityChangedHandler struct {
	DB interfaces.Database
}

func (h *RepositoryVisibilityChangedHandler) HandleEnvelope(ctx context.Context, logger log.Logger, envelope *schemas.Envelope) error {
	var message hydroSchema.VisibilityChanged
	if err := proto.Unmarshal(envelope.Message, &message); err != nil {
		logger.WithError(err).Error("failed to unmarshal enveloped message")
		return errors.Wrap(err, "failed to unmarshal enveloped message")
	}

	isPublic := message.GetNewVisibility() == hydroSchema.VisibilityChanged_PUBLIC

	logger.Info("message received", kvp.Int64("repoId", int64(message.GetRepositoryId())), kvp.Bool("isPublic", isPublic))
	return h.DB.UpsertWithOptions(ctx, logger, models.NewRepo(int64(message.GetRepositoryId()), isPublic), nil)
}
