// Package quotaapi provides Twirp handlers for quota snapshot APIs used by internal services.
package quotaapi

import (
	"context"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/twitchtv/twirp"
)

// Handler handles quota API requests.
type Handler struct {
	obsv     observability.Exporters
	ghTwirp  githubtwirp.ClientInterface
	ffClient featureflags.Client
}

var _ jobs_pb.QuotaAPI = (*Handler)(nil)

// NewHandler creates a new quota API handler.
func NewHandler(
	obsv observability.Exporters,
	ghTwirp githubtwirp.ClientInterface,
	ffClient featureflags.Client,
) *Handler {
	return &Handler{
		obsv:     obsv,
		ghTwirp:  ghTwirp,
		ffClient: ffClient,
	}
}

// GetQuotaSnapshot returns a quota snapshot for the provided user.
func (h *Handler) GetQuotaSnapshot(ctx context.Context, req *jobs_pb.GetQuotaSnapshotRequest) (*jobs_pb.GetQuotaSnapshotResponse, error) {
	ctx, span := h.obsv.Tracer.Start(ctx, "quotaapi.GetQuotaSnapshot")
	defer span.End()

	userID := req.GetUserId()
	if userID <= 0 {
		return nil, twirp.InvalidArgumentError("user_id", "must be a positive integer")
	}

	quotaSnapshot := githubtwirp.ComposeQuotaSnapshot(ctx, h.ghTwirp, h.ffClient, h.obsv, 0, 0, userID)

	return &jobs_pb.GetQuotaSnapshotResponse{
		Remaining:           quotaSnapshot.Remaining,
		PercentageRemaining: quotaSnapshot.PercentageRemaining,
		CanStartSession:     quotaSnapshot.CanStartSession,
		Unlimited:           quotaSnapshot.Unlimited,
		CopilotPlan:         quotaSnapshot.CopilotPlan,
	}, nil
}
