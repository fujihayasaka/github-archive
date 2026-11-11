package github

import (
	"context"
	"fmt"

	privileged "github.com/github/privileged-app-client-go"
)

const privilegedAppCapability = "coding_agent_job_execution"

// This interface wraps the specific check we are doing for the job API to better enable mocking results during testing
type PrivilegedAppCheckerClient interface {
	IsCapable(ctx context.Context, appID uint64, applicationType string) (bool, error)
}

// Actual implementation
type PrivilegedAppChecker struct{}

func (c *PrivilegedAppChecker) IsCapable(ctx context.Context, appID uint64, applicationType string) (bool, error) {
	// Per https://github.com/github/authnd/blob/b24e187fde8ecadfeb5f665051ce19e7f6441ca5/client/constants.go#L13-L15
	// and https://github.com/github/privileged-app-client-go/blob/d8cfeb483b1c90c676fc105a96ef3ea29835988a/privileged_app_client.go#L131
	// we should treat "GithubApplication" as "Integration" and change the capitalization of OAuthApplication since this is what the API expects
	switch applicationType {
	case "GithubApplication":
		applicationType = "Integration"
	case "OAuthApplication":
		applicationType = "OauthApplication"
	}
	app := &privileged.BaseApp{
		ID:   fmt.Sprintf("%d", appID),
		Type: applicationType,
	}
	hasCapability, err := privileged.IsCapable(ctx, privilegedAppCapability, app)
	if err != nil {
		return false, fmt.Errorf("API failed to check app capabilities: %w", err)
	}
	return hasCapability, nil
}

// Mock for testing
type MockPrivilegedAppChecker struct {
	MockHasCapabilityResult bool
}

func (mc *MockPrivilegedAppChecker) IsCapable(ctx context.Context, appID uint64, applicationType string) (bool, error) {
	return mc.MockHasCapabilityResult, nil
}
