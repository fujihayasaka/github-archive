package githubtwirp

import (
	"context"
	"fmt"
	"time"

	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"google.golang.org/protobuf/proto"
)

// copilotUserDetailsCacheTTL is the TTL for caching Copilot user details.
// this can be fairly high, because user details don't change often. There are
// other similar calls for agent enablement, model policies etc, this is just for
// user identifiers, policies and plan information.
const copilotUserDetailsCacheTTL = 5 * time.Minute

// copilotUserDetailsCacheKey returns the cache key for a user's Copilot details.
func copilotUserDetailsCacheKey(userID int64) string {
	return fmt.Sprintf("copilot_user_details:%d", userID)
}

// GetCopilotUserDetails gets the Copilot user details, and memoizes it in the context to not need to refetch it multiple times.
func (c *Client) GetCopilotUserDetails(ctx context.Context, userID int64) (*copilotUsersTwirp.CopilotUserDetails, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "githubtwirp.Client.GetCopilotUserDetails")
	defer span.End()

	// Check if we already have the user details in the context for this specific user ID
	if userDetails, ok := requestctx.CopilotUserDetails(ctx, userID); ok {
		return userDetails, nil
	}

	cacheKey := copilotUserDetailsCacheKey(userID)

	// Check the cache for user details
	cachedValue, exists := c.cacheStore.Get(cacheKey)
	if exists && cachedValue != "" {
		var userDetails copilotUsersTwirp.CopilotUserDetails
		err := proto.Unmarshal([]byte(cachedValue), &userDetails)
		if err == nil {
			// Memoize in context for subsequent calls
			_ = requestctx.AddCopilotUserDetails(ctx, userID, &userDetails)
			return &userDetails, nil
		}
		// Log and continue to fetch from API if unmarshal fails
		c.obsv.LogAndReportError(ctx, err, "GetCopilotUserDetails: failed to unmarshal cached user details")
	}

	res, err := c.UserDetailAPI().GetCopilotUser(ctx, &copilotUsersTwirp.GetCopilotUserRequest{
		Id: uint64(userID),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get user details: %w", err)
	}

	// Cache the user details
	marshaled, err := proto.Marshal(res.UserDetails)
	if err != nil {
		c.obsv.LogAndReportError(ctx, err, "GetCopilotUserDetails: failed to marshal user details for caching")
	} else {
		c.cacheStore.Set(cacheKey, string(marshaled), copilotUserDetailsCacheTTL)
	}

	// Memoize it in ctx for this specific user ID
	_ = requestctx.AddCopilotUserDetails(ctx, userID, res.UserDetails)

	return res.UserDetails, nil
}

// GetCustomerID gets the customer ID associated with the given user ID.
func (c *Client) GetCustomerID(ctx context.Context, userID int64) (int64, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "githubtwirp.Client.GetCustomerID")
	defer span.End()

	userDetails, err := c.GetCopilotUserDetails(ctx, userID)
	if err != nil {
		return 0, fmt.Errorf("failed to get user details: %w", err)
	}

	response, err := c.LimiterAPI().GetConsumptiveUser(ctx, &copilotLimitersTwirp.GetConsumptiveUserRequest{
		CopilotTrackingId: userDetails.GetAnalyticsTrackingId(),
	})
	if err != nil {
		return 0, fmt.Errorf("failed to get consumptive user: %w", err)
	}
	// Define as int64
	customerID := int64(0)

	if len(response.CustomerIds) == 0 && IsMultiSKU(response.AccessType.String()) {
		// this means that they have been assigned multiple seats
		// by non-associated (having different Customer records) entities
		// they must select their customer in their copilot settings
		// before they can use copilot

		// we will set the customer ID to -1 to indicate that they need to select a customer
		customerID = -1
	} else if len(response.CustomerIds) > 0 {
		customerID = response.CustomerIds[0]
	}

	return customerID, nil
}

// IsAgentEnabled checks if the agent is enabled for the given agent ID, user ID, and repository ID.
func (c *Client) IsAgentEnabled(ctx context.Context, agentID, userID int64, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "githubtwirp.Client.IsAgentEnabled")
	defer span.End()

	result, err := c.SweagentdAPI().ConfigurationForRepository(ctx, &sweagentdTwirp.ConfigurationForRepositoryRequest{
		RepositoryId: repositoryID,
		UserId:       uint64(userID),
		AgentId:      agentID,
	})
	if err != nil {
		return false, nil, fmt.Errorf("failed to get monolith configuration for repository: %w", err)
	}

	return result.IsAgentEnabled, result, nil
}

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
