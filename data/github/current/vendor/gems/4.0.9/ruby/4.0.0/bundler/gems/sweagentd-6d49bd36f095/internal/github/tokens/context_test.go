package tokens

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/sweagentd"
)

func TestNewCtxTokens(t *testing.T) {
	tokens := newCtxTokens()

	if tokens == nil {
		t.Fatal("newCtxTokens() returned nil")
	}

	if tokens.UserTokens == nil {
		t.Error("UserTokens should be initialized")
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
	})
}

func TestGetUserTokenFromContext(t *testing.T) {
	ctx := context.Background()
	ctx = NewContext(ctx)

	t.Run("get existing user token", func(t *testing.T) {
		userID := int64(123)
		repoID := int64(456)
		tokenValue := "user-token-123"
		target := sweagentd.ClientTargetForUser(0, userID)

		// Store the token
		setUserTokenInContext(ctx, target, repoID, tokenValue)

		// Retrieve the token
		token := getUserTokenFromContext(ctx, target, repoID)
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
		target := sweagentd.ClientTargetForUser(0, userID)

		token := getUserTokenFromContext(ctx, target, repoID)
		if token != nil {
			t.Error("Expected no token to be found")
		}
	})

	t.Run("get non-existing user token - repo exists but user doesn't", func(t *testing.T) {
		userID := int64(123)
		repoID := int64(456)
		anotherUserID := int64(999)
		target := sweagentd.ClientTargetForUser(0, userID)
		anotherTarget := sweagentd.ClientTargetForUser(0, anotherUserID)

		// Store a token for one user
		setUserTokenInContext(ctx, target, repoID, "token")

		// Try to get token for different user
		token := getUserTokenFromContext(ctx, anotherTarget, repoID)
		if token != nil {
			t.Error("Expected no token to be found for different user")
		}
	})

	t.Run("panic on no tokens in context", func(t *testing.T) {
		ctxWithoutTokens := context.Background()
		userID := int64(123)
		repoID := int64(456)
		target := sweagentd.ClientTargetForUser(0, userID)

		defer func() {
			if r := recover(); r == nil {
				t.Error("Expected panic when no tokens in context")
			}
		}()

		getUserTokenFromContext(ctxWithoutTokens, target, repoID)
	})
}

func TestSetUserTokenInContext(t *testing.T) {
	ctx := context.Background()
	ctx = NewContext(ctx)

	t.Run("set user token", func(t *testing.T) {
		userID := int64(123)
		repoID := int64(456)
		tokenValue := "user-token-set"
		target := sweagentd.ClientTargetForUser(0, userID)

		setUserTokenInContext(ctx, target, repoID, tokenValue)

		// Verify the token was stored
		token := getUserTokenFromContext(ctx, target, repoID)
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
		target := sweagentd.ClientTargetForUser(0, userID)

		// Set original token
		setUserTokenInContext(ctx, target, repoID, originalToken)

		// Overwrite with new token
		setUserTokenInContext(ctx, target, repoID, newToken)

		// Verify the new token was stored
		token := getUserTokenFromContext(ctx, target, repoID)
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
		target := sweagentd.ClientTargetForUser(0, userID)

		defer func() {
			if r := recover(); r == nil {
				t.Error("Expected panic when no tokens in context")
			}
		}()

		setUserTokenInContext(ctxWithoutTokens, target, repoID, tokenValue)
	})
}

func TestIntegration(t *testing.T) {
	t.Run("full workflow with multiple tokens", func(t *testing.T) {
		ctx := context.Background()
		ctx = NewContext(ctx)

		// Set multiple user tokens
		userTarget1 := sweagentd.ClientTargetForUser(0, 111)
		userTarget2 := sweagentd.ClientTargetForUser(0, 333)
		setUserTokenInContext(ctx, userTarget1, 222, "user-token-1")
		setUserTokenInContext(ctx, userTarget2, 444, "user-token-2")

		// Verify all tokens can be retrieved correctly
		userToken1 := getUserTokenFromContext(ctx, userTarget1, 222)
		if userToken1 == nil || userToken1.Token != "user-token-1" {
			t.Error("Failed to retrieve user token 1")
		}

		userToken2 := getUserTokenFromContext(ctx, userTarget2, 444)
		if userToken2 == nil || userToken2.Token != "user-token-2" {
			t.Error("Failed to retrieve user token 2")
		}
	})
}
