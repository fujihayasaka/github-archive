package fgpat

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestGenerateLegacyV1Token(t *testing.T) {
	header := NewV1Header(ProgrammaticAccessTokenType, 0xFFFFFFFF)
	token, err := newLegacyV1Token(header, getFakeRandomData())

	require.NoError(t, err)
	require.Equal(t, LegacyV1Prefix, token.Prefix)
	require.Equal(t, header, token.Header)
	require.Equal(t, "gh1_1777777Y0hijklmnopqrs_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgEC7K7TLFtuvwxyz0", token.Value)
	require.Equal(t, "EC7K7TLF", token.Checksum)
	require.Equal(t, legacyV1TokenLength, len(token.Value))
	require.Equal(t, "xr0XmjcWk8WavAdFYtgLv4V/A6WcmCguPmBlwukGjv0=", token.Hash())
	require.Equal(t, "tuvwxyz0", token.GetSuffix())
}

func TestParseLegacyV1Token(t *testing.T) {
	token, err := ParseToken("gh1_1777777Y0hijklmnopqrs_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgEC7K7TLFtuvwxyz0")
	require.NoError(t, err)
	require.Equal(t, LegacyV1Prefix, token.Prefix)
	require.Equal(t, "gh1_1777777Y0hijklmnopqrs_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgEC7K7TLFtuvwxyz0", token.Value)
	require.Equal(t, "EC7K7TLF", token.Checksum)
	require.Equal(t, legacyV1TokenLength, len(token.Value))
	require.Equal(t, "xr0XmjcWk8WavAdFYtgLv4V/A6WcmCguPmBlwukGjv0=", token.Hash())
	require.Equal(t, "tuvwxyz0", token.GetSuffix())

	var v1Header *V1Header
	require.IsType(t, v1Header, token.Header)

	v1Header = token.Header.(*V1Header)
	require.Equal(t, ProgrammaticAccessTokenType, v1Header.TokenType)
	require.Equal(t, uint32(0xFFFFFFFF), v1Header.UserID)
}
