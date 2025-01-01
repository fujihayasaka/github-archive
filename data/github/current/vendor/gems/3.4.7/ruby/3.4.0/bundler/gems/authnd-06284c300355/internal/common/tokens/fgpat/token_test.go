package fgpat

import (
	"bytes"
	"crypto/rand"
	"fmt"
	"io"
	"testing"

	"github.com/stretchr/testify/require"
)

func getFakeRandomData() io.Reader {
	// "512 bytes of randomness should be enough for anyone"
	// -Bill Gates ... probably.
	fakeRandomData := make([]byte, 512)

	for i := 0; i < len(fakeRandomData); i++ {
		fakeRandomData[i] = byte(i)
	}
	return bytes.NewReader(fakeRandomData)
}

func TestHashToken(t *testing.T) {
	token := &Token{
		Value: "abc123",
	}
	require.Equal(t, "bKE9UspwyIPg8LsQHkJaiehiTeUdstI5JZOvaoQRgJA=", token.Hash())
}

func TestGetSuffix(t *testing.T) {
	require.Equal(t, "", (&Token{Value: ""}).GetSuffix())
	require.Equal(t, "abc", (&Token{Value: "abc"}).GetSuffix())
	require.Equal(t, "stuvwxyz", (&Token{Value: "abcdefghijklmnopqrstuvwxyz"}).GetSuffix())
}

func TestParseLegacyTokens(t *testing.T) {
	token, err := ParseToken("thisisalegacytoken")
	require.NoError(t, err)
	require.Equal(t, "thisisalegacytoken", token.Value)
	require.Equal(t, UnknownPrefix, token.Prefix)
}

// This test attempts to confirm that the randomString method has minimal selection bias towards specific characters in the character set.
func TestRandomStringBias(t *testing.T) {
	const stringCount = 100_000
	const stringLength = 32

	// We expect the worst case to be no more than 4% off the perfect distribution.
	// This number came up experimentally, but it seems clear enough and should protect us from introducing bias in future changes.
	const expectedMaxDelta = 0.04

	// Generate random strings, and count the occurrences of each character in the character set
	counts := make(map[string]int)
	for i := 0; i < stringCount; i++ {
		// Generate a random string
		str, err := randomString(stringLength, alphanumeric, rand.Reader)
		require.NoError(t, err)

		// Count occurrences of each character
		for _, c := range str {
			counts[string(c)]++
		}
	}

	// The perfect distribution would be a uniform distribution of characters in the character set.
	// This isn't _quite_ perfect because we truncate to int64, but it's good enough
	perfectDistribution := int64((stringCount * stringLength) / len(alphanumeric))

	// Compute how far each character count is from the perfect distribution, and measure it against the max allowed delta
	for _, s := range alphanumeric {
		count := int64(counts[string(s)])
		delta := intAbs(perfectDistribution - count)

		// The delta should be no more than the expected ratio off the perfect distribution
		pct := float64(delta) / float64(perfectDistribution)
		require.LessOrEqual(t, pct, expectedMaxDelta, fmt.Sprintf("maximum delta of character '%s' is %d, which is %f%% off of the perfect distribution %d, but the allowed threshold is %f%%", string(s), delta, pct*100, perfectDistribution, expectedMaxDelta*100))
	}
}

func BenchmarkRandomString(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		randomString(64, alphanumeric, rand.Reader) //nolint:errcheck
	}
}

func intAbs(x int64) int64 {
	if x < 0 {
		return -x
	}
	return x
}
