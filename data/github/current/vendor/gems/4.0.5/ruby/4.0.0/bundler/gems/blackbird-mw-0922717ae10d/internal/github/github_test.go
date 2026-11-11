package github

import (
	"testing"

	"github.com/google/go-github/github"
	"github.com/stretchr/testify/require"
)

func Test_ParserLogin(t *testing.T) {
	require.Equal(t, "tclem", ParseUserLogin(&github.User{Login: github.String("tclem")}))
	require.Equal(t, "app/dependabot", ParseUserLogin(&github.User{Login: github.String("dependabot[bot]")}))
}
