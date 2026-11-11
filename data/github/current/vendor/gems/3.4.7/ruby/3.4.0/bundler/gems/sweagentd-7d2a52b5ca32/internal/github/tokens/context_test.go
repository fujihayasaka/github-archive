package tokens

import (
	"context"
	"testing"
)

func TestNewCtxTokens(t *testing.T) {
	tokens := newCtxTokens()

	if tokens == nil {
		t.Fatal("newCtxTokens() returned nil")
	}

	if tokens.RepoTokensByID == nil {
		t.Error("RepoTokensByID should be initialized")
	}

	if tokens.RepoTokensByName == nil {
		t.Error("RepoTokensByName should be initialized")
	}

	if tokens.UserTokens == nil {
		t.Error("UserTokens should be initialized")
	}

	if len(tokens.RepoTokensByID) != 0 {
		t.Error("RepoTokensByID should be empty initially")
	}

	if len(tokens.RepoTokensByName) != 0 {
		t.Error("RepoTokensByName should be empty initially")
	}

	if len(tokens.UserTokens) != 0 {
		t.Error("UserTokens should be empty initially")
	}
}

func TestWithTokens(t *testing.T) {
	ctx := context.Background()
	tokens := newCtxTokens()

	ctxWithTokens := withTokens(ctx, tokens)

	if ctxWithTokens == nil {
		t.Fatal("withTokens() returned nil context")
	}

	retrievedTokens := getTokens(ctxWithTokens)
	if retrievedTokens == nil {
		t.Fatal("Failed to retrieve tokens from context")
	}

	if retrievedTokens != tokens {
		t.Error("Retrieved tokens don't match the original tokens")
	}
}

func TestGetTokens(t *testing.T) {
	t.Run("context with tokens", func(t *testing.T) {
		ctx := context.Background()
		tokens := newCtxTokens()
		ctxWithTokens := withTokens(ctx, tokens)

		retrievedTokens := getTokens(ctxWithTokens)
		if retrievedTokens == nil {
			t.Fatal("Failed to retrieve tokens from context")
		}

		if retrievedTokens != tokens {
			t.Error("Retrieved tokens don't match the original tokens")
		}
	})
}

func TestNewContext(t *testing.T) {
	t.Run("context without tokens", func(t *testing.T) {
		ctx := context.Background()

		ctxWithTokens := NewContext(ctx)

		tokens := getTokens(ctxWithTokens)
		if tokens == nil {
			t.Fatal("EnsureTokens should add tokens to context")
		}

		if tokens == nil {
			t.Error("Tokens should not be nil")
		}
	})
}

func TestGetGlobalTokenFromContext(t *testing.T) {
	ctx := context.Background()
	ctx = NewContext(ctx)

	t.Run("get token by ID - token exists", func(t *testing.T) {
		// Set up test data
		req := globalTokenRequest{
			TargetID:      123,
			RepositoryIDs: []int64{456},
		}
		resp := &globalTokenResponse{
			Token: "test-token-by-id",
		}

		// Store the token
		setGlobalTokenInContext(ctx, req, resp)

		// Retrieve the token
		token := getGlobalTokenFromContext(ctx, req)
		if token == nil {
			t.Fatal("Expected token to be found")
		}

		if token.Token != "test-token-by-id" {
			t.Errorf("Expected token 'test-token-by-id', got '%s'", token.Token)
		}
	})

	t.Run("get token by ID - token does not exist", func(t *testing.T) {
		req := globalTokenRequest{
			TargetID:      999,
			RepositoryIDs: []int64{888},
		}

		token := getGlobalTokenFromContext(ctx, req)
		if token != nil {
			t.Error("Expected no token to be found")
		}
	})

	t.Run("get token by name - token exists", func(t *testing.T) {
		// Set up test data
		req := globalTokenRequest{
			Target:       "owner",
			Repositories: []string{"repo"},
		}
		resp := &globalTokenResponse{
			Token: "test-token-by-name",
		}

		// Store the token
		setGlobalTokenInContext(ctx, req, resp)

		// Retrieve the token
		token := getGlobalTokenFromContext(ctx, req)
		if token == nil {
			t.Fatal("Expected token to be found")
		}

		if token.Token != "test-token-by-name" {
			t.Errorf("Expected token 'test-token-by-name', got '%s'", token.Token)
		}
	})

	t.Run("get token by name - token does not exist", func(t *testing.T) {
		req := globalTokenRequest{
			Target:       "nonexistent",
			Repositories: []string{"repo"},
		}

		token := getGlobalTokenFromContext(ctx, req)
		if token != nil {
			t.Error("Expected no token to be found")
		}
	})

	t.Run("unhandled request", func(t *testing.T) {
		req := globalTokenRequest{
			Target:       "owner",
			Repositories: []string{"repo1", "repo2"}, // Multiple repos - unhandled
		}

		token := getGlobalTokenFromContext(ctx, req)
		if token != nil {
			t.Error("Expected no token for unhandled request")
		}
	})

	t.Run("panic on no tokens in context", func(t *testing.T) {
		ctxWithoutTokens := context.Background()
		req := globalTokenRequest{
			TargetID:      123,
			RepositoryIDs: []int64{456},
		}

		defer func() {
			if r := recover(); r == nil {
				t.Error("Expected panic when no tokens in context")
			}
		}()

		getGlobalTokenFromContext(ctxWithoutTokens, req)
	})
}

func TestSetGlobalTokenInContext(t *testing.T) {
	ctx := context.Background()
	ctx = NewContext(ctx)

	t.Run("set token by ID", func(t *testing.T) {
		req := globalTokenRequest{
			TargetID:      123,
			RepositoryIDs: []int64{456},
		}
		resp := &globalTokenResponse{
			Token: "test-token-set-by-id",
		}

		setGlobalTokenInContext(ctx, req, resp)

		// Verify the token was stored
		token := getGlobalTokenFromContext(ctx, req)
		if token == nil {
			t.Fatal("Expected token to be stored")
		}

		if token.Token != "test-token-set-by-id" {
			t.Errorf("Expected token 'test-token-set-by-id', got '%s'", token.Token)
		}
	})

	t.Run("set token by name", func(t *testing.T) {
		req := globalTokenRequest{
			Target:       "owner",
			Repositories: []string{"repo"},
		}
		resp := &globalTokenResponse{
			Token: "test-token-set-by-name",
		}

		setGlobalTokenInContext(ctx, req, resp)

		// Verify the token was stored
		token := getGlobalTokenFromContext(ctx, req)
		if token == nil {
			t.Fatal("Expected token to be stored")
		}

		if token.Token != "test-token-set-by-name" {
			t.Errorf("Expected token 'test-token-set-by-name', got '%s'", token.Token)
		}
	})

	t.Run("unhandled request", func(t *testing.T) {
		req := globalTokenRequest{
			Target:       "owner",
			Repositories: []string{"repo1", "repo2"}, // Multiple repos - unhandled
		}
		resp := &globalTokenResponse{
			Token: "test-token-unhandled",
		}

		// This should not panic, just do nothing
		setGlobalTokenInContext(ctx, req, resp)

		// Verify no token was stored by trying to retrieve it
		token := getGlobalTokenFromContext(ctx, req)
		if token != nil {
			t.Error("Expected no token to be stored for unhandled request")
		}
	})

	t.Run("panic on no tokens in context", func(t *testing.T) {
		ctxWithoutTokens := context.Background()
		req := globalTokenRequest{
			TargetID:      123,
			RepositoryIDs: []int64{456},
		}
		resp := &globalTokenResponse{
			Token: "test-token",
		}

		defer func() {
			if r := recover(); r == nil {
				t.Error("Expected panic when no tokens in context")
			}
		}()

		setGlobalTokenInContext(ctxWithoutTokens, req, resp)
	})
}

func TestGetUserTokenFromContext(t *testing.T) {
	ctx := context.Background()
	ctx = NewContext(ctx)

	t.Run("get existing user token", func(t *testing.T) {
		userID := int64(123)
		repoID := int64(456)
		tokenValue := "user-token-123"

		// Store the token
		setUserTokenInContext(ctx, userID, repoID, tokenValue)

		// Retrieve the token
		token := getUserTokenFromContext(ctx, userID, repoID)
		if token == nil {
			t.Fatal("Expected token to be found")
		}

		if token.Token != tokenValue {
			t.Errorf("Expected token '%s', got '%s'", tokenValue, token.Token)
		}
	})

	t.Run("get non-existing user token - no repo", func(t *testing.T) {
		userID := int64(999)
		repoID := int64(888)

		token := getUserTokenFromContext(ctx, userID, repoID)
		if token != nil {
			t.Error("Expected no token to be found")
		}
	})

	t.Run("get non-existing user token - repo exists but user doesn't", func(t *testing.T) {
		userID := int64(123)
		repoID := int64(456)
		anotherUserID := int64(999)

		// Store a token for one user
		setUserTokenInContext(ctx, userID, repoID, "token")

		// Try to get token for different user
		token := getUserTokenFromContext(ctx, anotherUserID, repoID)
		if token != nil {
			t.Error("Expected no token to be found for different user")
		}
	})

	t.Run("panic on no tokens in context", func(t *testing.T) {
		ctxWithoutTokens := context.Background()
		userID := int64(123)
		repoID := int64(456)

		defer func() {
			if r := recover(); r == nil {
				t.Error("Expected panic when no tokens in context")
			}
		}()

		getUserTokenFromContext(ctxWithoutTokens, userID, repoID)
	})
}

func TestSetUserTokenInContext(t *testing.T) {
	ctx := context.Background()
	ctx = NewContext(ctx)

	t.Run("set user token", func(t *testing.T) {
		userID := int64(123)
		repoID := int64(456)
		tokenValue := "user-token-set"

		setUserTokenInContext(ctx, userID, repoID, tokenValue)

		// Verify the token was stored
		token := getUserTokenFromContext(ctx, userID, repoID)
		if token == nil {
			t.Fatal("Expected token to be stored")
		}

		if token.Token != tokenValue {
			t.Errorf("Expected token '%s', got '%s'", tokenValue, token.Token)
		}
	})

	t.Run("overwrite existing user token", func(t *testing.T) {
		userID := int64(123)
		repoID := int64(456)
		originalToken := "original-token"
		newToken := "new-token"

		// Set original token
		setUserTokenInContext(ctx, userID, repoID, originalToken)

		// Overwrite with new token
		setUserTokenInContext(ctx, userID, repoID, newToken)

		// Verify the new token was stored
		token := getUserTokenFromContext(ctx, userID, repoID)
		if token == nil {
			t.Fatal("Expected token to be stored")
		}

		if token.Token != newToken {
			t.Errorf("Expected token '%s', got '%s'", newToken, token.Token)
		}
	})

	t.Run("panic on no tokens in context", func(t *testing.T) {
		ctxWithoutTokens := context.Background()
		userID := int64(123)
		repoID := int64(456)
		tokenValue := "test-token"

		defer func() {
			if r := recover(); r == nil {
				t.Error("Expected panic when no tokens in context")
			}
		}()

		setUserTokenInContext(ctxWithoutTokens, userID, repoID, tokenValue)
	})
}

func TestIntegration(t *testing.T) {
	t.Run("full workflow with multiple tokens", func(t *testing.T) {
		ctx := context.Background()
		ctx = NewContext(ctx)

		// Set multiple global tokens
		req1 := globalTokenRequest{
			TargetID:      123,
			RepositoryIDs: []int64{456},
		}
		resp1 := &globalTokenResponse{Token: "global-token-1"}
		setGlobalTokenInContext(ctx, req1, resp1)

		req2 := globalTokenRequest{
			Target:       "owner2",
			Repositories: []string{"repo2"},
		}
		resp2 := &globalTokenResponse{Token: "global-token-2"}
		setGlobalTokenInContext(ctx, req2, resp2)

		// Set multiple user tokens
		setUserTokenInContext(ctx, 111, 222, "user-token-1")
		setUserTokenInContext(ctx, 333, 444, "user-token-2")

		// Verify all tokens can be retrieved correctly
		token1 := getGlobalTokenFromContext(ctx, req1)
		if token1 == nil || token1.Token != "global-token-1" {
			t.Error("Failed to retrieve global token 1")
		}

		token2 := getGlobalTokenFromContext(ctx, req2)
		if token2 == nil || token2.Token != "global-token-2" {
			t.Error("Failed to retrieve global token 2")
		}

		userToken1 := getUserTokenFromContext(ctx, 111, 222)
		if userToken1 == nil || userToken1.Token != "user-token-1" {
			t.Error("Failed to retrieve user token 1")
		}

		userToken2 := getUserTokenFromContext(ctx, 333, 444)
		if userToken2 == nil || userToken2.Token != "user-token-2" {
			t.Error("Failed to retrieve user token 2")
		}
	})
}
