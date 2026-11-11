package agenticapp

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

// revokeToken revokes the given installation or user-to-server token. The type
// of token is determined by its prefix.
func revokeToken(ctx context.Context, api sweagentd.GitHubAPI, app sweagentd.AgenticApp, token string) error {
	if strings.HasPrefix(token, "ghu_") {
		return revokeUserToServerToken(ctx, api, app, token)
	}
	return revokeInstallationToken(ctx, api, token)
}

// revokeUserToServerToken revokes a user-to-server OAuth token.
func revokeUserToServerToken(ctx context.Context, api sweagentd.GitHubAPI, app sweagentd.AgenticApp, token string) error {
	clientID := app.ClientID()

	// Requires the use of basic auth, with client ID and a client secret.
	// So we need to create a one off client for exclusively this purpose.
	// See https://docs.github.com/rest/apps/oauth-applications#delete-an-app-token
	utr := &gg.UnauthenticatedRateLimitedTransport{
		ClientID:     clientID,
		ClientSecret: app.ClientSecret(),
	}

	client := gg.NewClient(utr.Client())
	client.BaseURL = api.BaseURL()

	_, err := client.Authorizations.Revoke(ctx, clientID, token)
	if err != nil {
		return checkRevokeTokenError(err)
	}

	return nil
}

// revokeInstallationToken revokes an installation access token.
func revokeInstallationToken(ctx context.Context, api sweagentd.GitHubAPI, token string) error {
	// Need to create a one off client for this token since we will immediately
	// make the client unusable
	client := gg.NewClient(nil).WithAuthToken(token)
	client.BaseURL = api.BaseURL()

	_, err := client.Apps.RevokeInstallationToken(ctx)
	if err != nil {
		return checkRevokeTokenError(err)
	}

	return nil
}

// checkRevokeTokenError checks errors returned when revoking tokens and swallows
// those that indicate the token is already revoked or invalid.
func checkRevokeTokenError(err error) error {
	var ale *gg.AbuseRateLimitError
	var rle *gg.RateLimitError
	var er *gg.ErrorResponse

	switch {
	case errors.As(err, &ale):
		// if we hit an abuse rate limit, we can't revoke the token, swallow the error
		return nil
	case errors.As(err, &rle):
		// if we hit a rate limit, again we can't revoke the token, swallow the error
		return nil
	case errors.As(err, &er):
		if er.Response.StatusCode == http.StatusNotFound || er.Response.StatusCode == http.StatusUnauthorized {
			// Token is already revoked or invalid
			return nil
		}
	default:
		return err
	}

	return err
}
