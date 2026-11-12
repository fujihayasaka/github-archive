package twirpserver

import (
	"context"
	"errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/twitchtv/twirp"
)

type quotaActors struct {
	ownerID int64
	repoID  int64
	actorID int64
}

func (q *quotaActors) GetActorID() int64      { return q.actorID }
func (q *quotaActors) GetRepositoryID() int64 { return q.repoID }
func (q *quotaActors) GetOwnerID() int64      { return q.ownerID }

// CheckQuota checks if the user has sufficient premium quota to proceed.
// It handles the customer selection required scenario based on the feature flag.
func CheckQuota(
	ctx context.Context,
	ghTwirp githubtwirp.ClientInterface,
	ffClient featureflags.Client,
	obsv observability.Exporters,
	ownerID, repoID, actorID int64,
	resourceName string,
) error {
	logger := obsv.LoggerWithTelemetry(ctx)

	hasSufficientQuota, _, _, err := githubtwirp.CheckPremiumQuota(
		ctx,
		ghTwirp,
		ffClient,
		obsv,
		ownerID,
		repoID,
		actorID,
		false,
	)

	if err != nil {
		actors := &quotaActors{ownerID: ownerID, repoID: repoID, actorID: actorID}

		// If the error is a transient failure and fail-open is enabled,
		// allow the operation to proceed rather than blocking the user.
		if githubtwirp.ShouldFailOpenOnQuotaError(ctx, err, ffClient, obsv, actors, "quota_check") {
			return nil
		}

		if !errors.Is(err, githubtwirp.ErrCustomerSelectionRequired) {
			return goerrors.Errorf("failed to check quota: %w", err)
		}

		// Customer selection required - check feature flag
		if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentSelectCustomerError, actors) {
			logger.Info("user needs to select customer in Copilot settings, returning error",
				kvp.Int64("actor_id", actorID),
			)
			return twirp.FailedPrecondition.Error("customer selection required")
		}

		// Feature flag disabled: log and continue
		logger.Info("user needs to select customer in Copilot settings, but continuing due to feature flag",
			kvp.Int64("actor_id", actorID),
		)
		return nil
	}

	if !hasSufficientQuota {
		return twirp.FailedPrecondition.Error("insufficient premium quota to create " + resourceName)
	}

	return nil
}
