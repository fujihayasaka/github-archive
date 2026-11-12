package githubtwirp

import (
	"context"
	"fmt"
	"strconv"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/goerrors"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

// IsMemoryEnabled checks if the memory feature is enabled for the given user ID.
func (c *Client) IsMemoryEnabled(ctx context.Context, userID int64) (bool, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "githubtwirp.Client.IsMemoryEnabled")
	defer span.End()

	userDetails, err := c.GetCopilotUserDetails(ctx, userID)
	if err != nil {
		return false, fmt.Errorf("failed to get user details: %w", err)
	}

	return userDetails.GetMemorySetting() == copilotUsersTwirp.Memory_MEMORY_ENABLED, nil
}

// IsMemoryDisabledForRepo checks if agentic memory is disabled at the
// repository level by a repo admin. It calls ConfigurationForRepository and
// returns the value of the repo_memory_disabled field (default false when
// the field is unset, which is treated as "memory enabled" — that is the
// safe rollout default).
func (c *Client) IsMemoryDisabledForRepo(ctx context.Context, repositoryID, userID int64) (bool, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "githubtwirp.Client.IsMemoryDisabledForRepo")
	defer span.End()

	startTime := time.Now()

	result, err := c.SweagentdAPI().ConfigurationForRepository(ctx, &sweagentdTwirp.ConfigurationForRepositoryRequest{
		RepositoryId: repositoryID,
		UserId:       uint64(userID),
	})

	latency := time.Since(startTime)

	if err != nil {
		// Track failed fetch - helps debug connectivity/timeout issues during rollout
		c.obsv.DistributionMs(ctx, MetricRepoMemoryOptOut+".latency_ms", stats.Tags{
			"success": "false",
		}, latency)
		return false, goerrors.Errorf("failed to get repository configuration: %w", err)
	}

	disabled := result.GetRepoMemoryDisabled()
	c.obsv.DistributionMs(ctx, MetricRepoMemoryOptOut+".latency_ms", stats.Tags{
		"success":  "true",
		"disabled": strconv.FormatBool(disabled),
	}, latency)

	return disabled, nil
}
