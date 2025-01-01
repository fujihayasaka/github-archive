package vssf_token

import (
	"context"
	"time"
)

// MockClient is a mock implementation of the token.Client interface.
type MockClient struct{}

// GetToken is a mock implementation of the GetToken method.
func (c *MockClient) GetToken(ctx context.Context) (string, error) {
	// Return a dummy token for testing purposes
	return "dummy_token", nil
}

// RefreshToken is a mock implementation of the RefreshToken method.
func (c *MockClient) RefreshToken(ctx context.Context, token string) (string, error) {
	// Simulate token refresh by returning a new dummy token
	return "new_dummy_token", nil
}

// GetTokenWithExpiration is a mock implementation of the GetTokenWithExpiration method.
func (c *MockClient) GetTokenWithExpiration(ctx context.Context) (string, time.Time, error) {
	// Return a dummy token and expiration time for testing purposes
	expiration := time.Now().Add(30 * time.Hour)
	return "dummy_token", expiration, nil
}
