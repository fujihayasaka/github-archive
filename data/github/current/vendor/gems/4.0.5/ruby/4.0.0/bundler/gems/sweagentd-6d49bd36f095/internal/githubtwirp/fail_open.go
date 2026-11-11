package githubtwirp

import (
	"context"
	"errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/twitchtv/twirp"
)

// isFailOpenEligible reports whether err is a transient Twirp error eligible
// for fail-open (Internal, Unavailable, or DeadlineExceeded). When eligible it
// returns true and the Twirp error code string; otherwise false and "".
func isFailOpenEligible(err error) (bool, string) {
	var twerr twirp.Error
	if !errors.As(err, &twerr) {
		return false, ""
	}

	switch twerr.Code() {
	case twirp.Internal, twirp.Unavailable, twirp.DeadlineExceeded:
		return true, string(twerr.Code())
	default:
		return false, ""
	}
}

// ShouldFailOpenOnQuotaError determines whether a quota-check error should be
// treated as a non-fatal failure, allowing the operation to proceed.
//
// It returns true only when ALL of the following are satisfied:
//   - err contains a transient Twirp error (Internal/Unavailable/DeadlineExceeded)
//   - the CopilotSWEAgentLimiterFailOpen feature flag is enabled for the actor/repo/owner
//
// When it returns true it also emits the events.quota_check_fail_open counter
// with resource and error_code tags so callers don't need to emit metrics separately.
func ShouldFailOpenOnQuotaError(
	ctx context.Context,
	err error,
	ffClient featureflags.Client,
	obsv observability.Exporters,
	actors sweagentd.RepositoryWithActor,
	resource string,
) bool {
	ok, errorCode := isFailOpenEligible(err)
	if !ok {
		return false
	}

	if !ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentLimiterFailOpen, actors) {
		return false
	}

	logger := obsv.LoggerWithTelemetry(ctx)
	logger.WithFields(
		kvp.String("resource", resource),
		kvp.String("error_code", errorCode),
		kvp.Int64("actor_id", actors.GetActorID()),
	).WithError(err).Warn("quota check failed with transient error, failing open")

	obsv.Increment(ctx, "events.quota_check_fail_open", stats.Tags{
		"resource":   resource,
		"error_code": errorCode,
	})

	return true
}
