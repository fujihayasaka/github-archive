package handlers

import (
	"context"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/github/repositories/v2"
	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/internal/monolith"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"

	repositories "github.com/github/monolith-twirp-billing/repositories/v1"
)

type RepositoryRestoredHandler struct {
	DB             interfaces.Database
	MonolithClient *monolith.Client
}

// Listen to repository restored messages so we can update the visibility information of a repository
// that might have been purged and had its visibility changed to invalid in the process
func (h *RepositoryRestoredHandler) HandleEnvelope(ctx context.Context, logger log.Logger, envelope *schemas.Envelope) error {
	var message hydroSchema.Restored
	if err := proto.Unmarshal(envelope.Message, &message); err != nil {
		logger.WithError(err).Error("failed to unmarshal enveloped message")
		return errors.Wrap(err, "failed to unmarshal enveloped message")
	}

	var repoID = message.GetRepositoryId()

	logger.Info("repo restore message received", kvp.Int64(logging.RepositoryId, repoID))

	resp, err := h.MonolithClient.RepositoryAPI.GetRepositoryMetadata(ctx, &repositories.GetRepositoryMetadataRequest{Id: uint64(repoID)})
	if err != nil {
		return errors.Wrap(err, "failed to get repo metadata")
	}

	return h.DB.UpsertWithOptions(ctx, logger, models.NewRepo(repoID, resp.Repository.IsPublic), nil)
}
