//go:build db

package api

import (
	"testing"

	apiTesting "github.com/github/authnd/internal/api/testing"
	"github.com/github/authnd/internal/common/testfixtures"
)

func TestLoginPasswordWithDB(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	client := apiTesting.TestAuthenticator(t, store, false)
	apiTesting.TestLoginPassword(t, client)
}

func TestSSHPublicKeyWithDB(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	client := apiTesting.TestAuthenticator(t, store, false)
	apiTesting.TestSSHPublicKey(t, client)
}

func TestAccessTokenWithDB(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	client := apiTesting.TestAuthenticator(t, store, false)
	apiTesting.TestAccessTokens(t, client)
}

func TestSignedAuthTokenWithDB(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	client := apiTesting.TestAuthenticator(t, store, false)
	apiTesting.TestSignedAuthToken(t, client)

}

func TestServerToServerTokensWithDB(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	client := apiTesting.TestAuthenticator(t, store, false)
	apiTesting.TestServerToServerTokens(t, client)
}
