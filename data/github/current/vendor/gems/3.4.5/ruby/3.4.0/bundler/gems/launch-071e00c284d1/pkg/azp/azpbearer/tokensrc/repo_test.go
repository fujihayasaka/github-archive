package tokensrc

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRepoClientTokenSourceFactory_getTokenURL(t *testing.T) {
	rf := &RepoClientTokenSourceFactory{
		baseURL: "https://tokenghub.actions.githubusercontent.com",
	}

	require.Equal(t, "https://tokenghub.actions.githubusercontent.com/_apis/oauth2/token/tenantid", rf.getTokenURL("tenantid"))
}
