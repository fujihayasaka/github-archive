//go:build db && !proxima

package testing

import (
	"context"
	"testing"

	"github.com/github/authnd/client"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestNoHMACAuth(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(server.URL, TestCatalogServiceName)
	require.NoError(t, err)

	resp, err := authenticator.Authenticate(context.Background(), client.NewAuthenticateRequest(&client.Credentials{}))
	require.Error(t, err)
	if e, ok := err.(twirp.Error); ok {
		require.Equal(t, e.Code(), twirp.Unauthenticated)
	} else {
		require.Fail(t, "expected twirp error", err)
	}
	require.Nil(t, resp)
}
