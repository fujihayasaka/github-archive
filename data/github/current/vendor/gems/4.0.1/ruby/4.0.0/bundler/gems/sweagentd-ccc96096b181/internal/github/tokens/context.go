// Package tokens provides context-based token management for GitHub API clients.
package tokens

import (
	"context"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
)

type ctxKey string

//nolint:gosec // G101: This is a context key, not a credential
var tokensCtxKey ctxKey = "github_tokens"

type token struct {
	Token string
}

type ctxTokens struct {
	RepoTokensByID   map[sweagentd.ClientTarget]map[int64]*token  // [sweagentd.ClientTarget][repoID]token
	RepoTokensByName map[sweagentd.ClientTarget]map[string]*token // [sweagentd.ClientTarget][repoName]token
	UserTokens       map[int64]map[sweagentd.ClientTarget]*token  // [repoID][sweagentd.ClientTarget]token
}

func newCtxTokens() *ctxTokens {
	return &ctxTokens{
		RepoTokensByID:   make(map[sweagentd.ClientTarget]map[int64]*token),
		RepoTokensByName: make(map[sweagentd.ClientTarget]map[string]*token),
		UserTokens:       make(map[int64]map[sweagentd.ClientTarget]*token),
	}
}

// NewContext creates a new context with token storage initialized.
func NewContext(ctx context.Context) context.Context {
	return withTokens(ctx, newCtxTokens())
}

func withTokens(ctx context.Context, tokens *ctxTokens) context.Context {
	return context.WithValue(ctx, tokensCtxKey, tokens)
}

func getTokens(ctx context.Context) *ctxTokens {
	tokens, ok := ctx.Value(tokensCtxKey).(*ctxTokens)
	if !ok || tokens == nil {
		// This should never happen in production,
		// making it a panic saves us a lot of unnecessary error handling.
		panic(goerrors.New("context does not contain tokens"))
	}

	return tokens
}

func getGlobalTokenFromContext(ctx context.Context, target sweagentd.ClientTarget, req globalTokenRequest) *token {
	tokens := getTokens(ctx)

	switch {
	case req.TargetID != 0 && len(req.RepositoryIDs) == 1:
		token, ok := tokens.RepoTokensByID[target][req.RepositoryIDs[0]]
		if !ok {
			return nil
		}
		return token

	case req.Target != "" && len(req.Repositories) == 1:
		token, ok := tokens.RepoTokensByName[target][req.Repositories[0]]
		if !ok {
			return nil
		}
		return token

	default:
		// unhandled global token request
		return nil
	}
}

func setGlobalTokenInContext(ctx context.Context, target sweagentd.ClientTarget, req globalTokenRequest, appToken string) {
	tokens := getTokens(ctx)

	newToken := &token{
		Token: appToken,
	}

	switch {
	case req.TargetID != 0 && len(req.RepositoryIDs) == 1:
		repo := req.RepositoryIDs[0]

		if _, ok := tokens.RepoTokensByID[target]; !ok {
			tokens.RepoTokensByID[target] = make(map[int64]*token)
		}
		tokens.RepoTokensByID[target][repo] = newToken

	case req.Target != "" && len(req.Repositories) == 1:
		repo := req.Repositories[0]

		if _, ok := tokens.RepoTokensByName[target]; !ok {
			tokens.RepoTokensByName[target] = make(map[string]*token)
		}
		tokens.RepoTokensByName[target][repo] = newToken

	default:
		// unhandled global token request
	}
}

func getUserTokenFromContext(ctx context.Context, target sweagentd.ClientTarget, repoID int64) *token {
	tokens := getTokens(ctx)
	token, ok := tokens.UserTokens[repoID][target]
	if !ok {
		return nil
	}

	return token
}

func setUserTokenInContext(ctx context.Context, target sweagentd.ClientTarget, repoID int64, value string) {
	tokens := getTokens(ctx)

	newToken := &token{
		Token: value,
	}

	if _, exists := tokens.UserTokens[repoID]; !exists {
		tokens.UserTokens[repoID] = make(map[sweagentd.ClientTarget]*token)
	}

	tokens.UserTokens[repoID][target] = newToken
}
