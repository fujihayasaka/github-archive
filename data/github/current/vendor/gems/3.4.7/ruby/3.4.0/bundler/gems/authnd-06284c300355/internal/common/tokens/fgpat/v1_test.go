package fgpat

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestGenerateV1Token(t *testing.T) {
	header := NewV1Header(ProgrammaticAccessTokenType, 0xFFFFFFFF)
	token, err := newV1Token(header, getFakeRandomData())

	require.NoError(t, err)
	require.Equal(t, V1Prefix, token.Prefix)
	require.Equal(t, ProgrammaticAccessTokenType, token.Type)
	require.Equal(t, header, token.Header)
	require.Equal(t, "github_pat_11777777Y0hijklmnopqrs_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgSY3VXNXItuvwxyz0", token.Value)
	require.Equal(t, "SY3VXNXI", token.Checksum)
	require.Equal(t, v1TokenLength, len(token.Value))
	require.Equal(t, "K2BHZ+FZR0F1yfZ2ULGcOhlgEvyTP7Zc+eekO5Qr0FY=", token.Hash())
	require.Equal(t, "tuvwxyz0", token.GetSuffix())
}

func TestParseV1Token(t *testing.T) {
	token, err := ParseToken("github_pat_11777777Y0hijklmnopqrs_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgSY3VXNXItuvwxyz0")
	require.NoError(t, err)
	require.Equal(t, V1Prefix, token.Prefix)
	require.Equal(t, "github_pat_11777777Y0hijklmnopqrs_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgSY3VXNXItuvwxyz0", token.Value)
	require.Equal(t, "SY3VXNXI", token.Checksum)
	require.Equal(t, v1TokenLength, len(token.Value))
	require.Equal(t, "K2BHZ+FZR0F1yfZ2ULGcOhlgEvyTP7Zc+eekO5Qr0FY=", token.Hash())
	require.Equal(t, "tuvwxyz0", token.GetSuffix())

	var v1Header *V1Header
	require.IsType(t, v1Header, token.Header)

	v1Header = token.Header.(*V1Header)
	require.Equal(t, ProgrammaticAccessTokenType, v1Header.TokenType)
	require.Equal(t, uint32(0xFFFFFFFF), v1Header.UserID)
}

func TestWriteV1Header(t *testing.T) {
	require.Equal(t, "1AAAAAAA00123456789AB", mustEncodeHeader(t, 0))
	require.Equal(t, "1777777Y00123456789AB", mustEncodeHeader(t, 0xFFFFFFFF))
}

func TestReadV1Header(t *testing.T) {
	require.Equal(t, uint32(0), mustDecodeUserIDFromHeader(t, "1AAAAAAA00123456789AB"))
	require.Equal(t, uint32(0xFFFFFFFF), mustDecodeUserIDFromHeader(t, "1777777Y00123456789AB"))
}

func mustDecodeUserIDFromHeader(t *testing.T, value string) uint32 {
	header, err := UnmarshalV1Header(value)
	require.NoError(t, err)
	require.Equal(t, ProgrammaticAccessTokenType, header.TokenType)
	return header.UserID
}

func mustEncodeHeader(t *testing.T, userID uint32) string {
	fakeRandom := getFakeRandomData()
	header := NewV1Header(ProgrammaticAccessTokenType, userID)
	encoded, err := header.marshal(fakeRandom)
	require.NoError(t, err)
	require.Equal(t, 21, len(encoded))
	return encoded
}
