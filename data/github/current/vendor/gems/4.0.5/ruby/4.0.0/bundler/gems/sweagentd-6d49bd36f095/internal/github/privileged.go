package github

import (
	"context"
	"fmt"

	privileged "github.com/github/privileged-app-client-go"
	"github.com/github/sweagentd/internal/goerrors"
)

const privilegedAppCapability = "coding_agent_job_execution"

// PrivilegedAppCheckerClient wraps the specific check we are doing for the job API to better enable mocking results during testing.
type PrivilegedAppCheckerClient interface {
	IsCapable(ctx context.Context, appID uint64, applicationType string) (bool, error)
}

// PrivilegedAppChecker is the actual implementation of PrivilegedAppCheckerClient.
type PrivilegedAppChecker struct{}

// IsCapable checks if an app has the capability to execute coding agent jobs.
func (c *PrivilegedAppChecker) IsCapable(ctx context.Context, appID uint64, applicationType string) (bool, error) {
	// Per https://github.com/github/authnd/blob/b24e187fde8ecadfeb5f665051ce19e7f6441ca5/client/constants.go#L13-L15
	// and https://github.com/github/privileged-app-client-go/blob/d8cfeb483b1c90c676fc105a96ef3ea29835988a/privileged_app_client.go#L131
	// we should treat "GithubApplication" as "Integration" and change the capitalization of OAuthApplication since this is what the API expects
	switch applicationType {
	case "GithubApplication":
		applicationType = "Integration"
	case "OAuthApplication":
		applicationType = "OauthApplication"
	default:
		// Keep applicationType as is for other types
	}
	app := &privileged.BaseApp{
		ID:   fmt.Sprintf("%d", appID),
		Type: applicationType,
	}
	hasCapability, err := privileged.IsCapable(ctx, privilegedAppCapability, app)
	if err != nil {
		return false, goerrors.Errorf("API failed to check app capabilities: %w", err)
	}
	return hasCapability, nil
}

// MockPrivilegedAppChecker is a mock implementation for testing.
type MockPrivilegedAppChecker struct {
	MockHasCapabilityResult bool
	MockHasCapabilityError  error
}

// IsCapable implements PrivilegedAppCheckerClient interface for testing.
func (mc *MockPrivilegedAppChecker) IsCapable(ctx context.Context, appID uint64, applicationType string) (bool, error) {
	return mc.MockHasCapabilityResult, mc.MockHasCapabilityError
}
