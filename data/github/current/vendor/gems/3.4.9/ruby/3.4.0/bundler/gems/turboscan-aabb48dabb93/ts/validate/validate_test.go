package validate

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestCommitOid(t *testing.T) {
	require.True(t, IsCommitOid("1ae7efb388540adc1653a51a3bc3b2c9cef5ec1a"))
	require.False(t, IsCommitOid("1ae7efb388540adc1653a51a3bc3b2c9cef5ec1a\n"))
	require.False(t, IsCommitOid("1xe7efb388540adc1653a51a3bc3b2c9cef5ec1a"))
	require.False(t, IsCommitOid(" 1ae7efb388540adc1653a51a3bc3b2c9cef5ec1a"))
	require.False(t, IsCommitOid(" 1ae7efb388540adc1653a51a3bc3b2c9cef5ec1as"))
	require.False(t, IsCommitOid("bar"))
	require.False(t, IsCommitOid(""))
}

func TestRef(t *testing.T) {
	require.True(t, IsRef([]byte("refs/heads/branch")))
	require.True(t, IsRef([]byte("refs/pull/1/head")))
	require.True(t, IsRef([]byte("refs/tags/v0.1")))
	require.False(t, IsRef([]byte("")))
	require.False(t, IsRef([]byte("heads/branch[]byte(")))
	require.False(t, IsRef([]byte(" refs/heads/[]byte(branch")))
	require.False(t, IsRef([]byte("refs/heads/b[]byte(ranch\n")))
}
