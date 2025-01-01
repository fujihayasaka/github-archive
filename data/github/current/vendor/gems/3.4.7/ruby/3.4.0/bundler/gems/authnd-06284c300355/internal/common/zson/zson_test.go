package zson

import (
	"testing"

	"github.com/stretchr/testify/require"
)

var expectedObj = testObj{
	Scopes: []string{"repo", "user", "gist"},
}

type testObj struct {
	Scopes []string `json:"scopes"`
}

func TestRoundTrip(t *testing.T) {
	// Gzip isn't a stable format, it's hard to guarantee that the same input will always produce the same output
	// So we can't do a "this object produces this ZSON" test easily.
	// Instead we do a round-trip test that marshalls a value and verifies it comes back when unmarshalled
	bytes, err := Marshal(expectedObj)
	require.NoError(t, err)

	var o testObj
	err = Unmarshal(bytes, &o)

	require.NoError(t, err)
	require.Equal(t, expectedObj.Scopes, o.Scopes)
}
