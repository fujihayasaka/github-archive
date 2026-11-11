package tokens

import (
	"context"
	"errors"
)

type ctxKey string

var tokensCtxKey ctxKey = "github_tokens"

type token struct {
	Token string
}

type ctxTokens struct {
	RepoTokensByID   map[int64]map[int64]*token   // [ownerID][repoID]token
	RepoTokensByName map[string]map[string]*token // [ownerName][repoName]token
	UserTokens       map[int64]map[int64]*token   // [repoID][userID]token
}

func newCtxTokens() *ctxTokens {
	return &ctxTokens{
		RepoTokensByID:   make(map[int64]map[int64]*token),
		RepoTokensByName: make(map[string]map[string]*token),
		UserTokens:       make(map[int64]map[int64]*token),
	}
}

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
		panic(errors.New("context does not contain tokens"))
	}
	return tokens
}

func getGlobalTokenFromContext(ctx context.Context, req globalTokenRequest) *token {
	tokens := getTokens(ctx)

	switch {
	case req.TargetID != 0 && len(req.RepositoryIDs) == 1:
		token, ok := tokens.RepoTokensByID[req.TargetID][req.RepositoryIDs[0]]
		if !ok {
			return nil
		}
		return token

	case req.Target != "" && len(req.Repositories) == 1:
		token, ok := tokens.RepoTokensByName[req.Target][req.Repositories[0]]
		if !ok {
			return nil
		}
		return token

	default:
		// unhandled global token request
		return nil
	}
}

func setGlobalTokenInContext(ctx context.Context, req globalTokenRequest, resp *globalTokenResponse) {
	tokens := getTokens(ctx)

	newToken := &token{
		Token: resp.Token,
	}

	switch {
	case req.TargetID != 0 && len(req.RepositoryIDs) == 1:
		owner := req.TargetID
		repo := req.RepositoryIDs[0]

		if _, ok := tokens.RepoTokensByID[owner]; !ok {
			tokens.RepoTokensByID[owner] = make(map[int64]*token)
		}
		tokens.RepoTokensByID[owner][repo] = newToken

	case req.Target != "" && len(req.Repositories) == 1:
		owner := req.Target
		repo := req.Repositories[0]

		if _, ok := tokens.RepoTokensByName[owner]; !ok {
			tokens.RepoTokensByName[owner] = make(map[string]*token)
		}
		tokens.RepoTokensByName[owner][repo] = newToken

	default:
		// unhandled global token request
	}
}

func getUserTokenFromContext(ctx context.Context, userID, repoID int64) *token {
	tokens := getTokens(ctx)
	token, ok := tokens.UserTokens[repoID][userID]
	if !ok {
		return nil
	}
	return token
}

func setUserTokenInContext(ctx context.Context, userID, repoID int64, value string) {
	tokens := getTokens(ctx)

	newToken := &token{
		Token: value,
	}

	if _, exists := tokens.UserTokens[repoID]; !exists {
		tokens.UserTokens[repoID] = make(map[int64]*token)
	}

	tokens.UserTokens[repoID][userID] = newToken
}
