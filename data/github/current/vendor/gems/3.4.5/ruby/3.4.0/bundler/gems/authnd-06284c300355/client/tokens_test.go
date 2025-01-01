package client

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestIsAuthndToken(t *testing.T) {
	require.False(t, IsAuthndToken("gh0_c0ffeecafec0ffeecafec0ffeecafe123456"))
	require.True(t, IsAuthndToken("gh1_c0ffeecafec0ffeecafe1_c0ffeecafec0ffeecafec0ffeecafec0ffeecafec0ffeecafe123456789"))
	require.True(t, IsAuthndToken("github_pat_1c0ffeecafec0ffeecafe1_c0ffeecafec0ffeecafec0ffeecafec0ffeecafec0ffeecafe123456789"))

	require.False(t, IsAuthndToken("gh0_c0ffeecafe"))
	require.False(t, IsAuthndToken("gh1_c0ffeecafe"))
	require.False(t, IsAuthndToken("ghp_vTvSxsrLjVc9gtEqZ8UIySPYb00a8XxdN38e"))
	require.False(t, IsAuthndToken("v1.021340932409"))
}
