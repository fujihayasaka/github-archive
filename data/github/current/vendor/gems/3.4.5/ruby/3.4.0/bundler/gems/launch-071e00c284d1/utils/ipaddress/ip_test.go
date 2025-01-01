package ipaddress_test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/utils/ipaddress"
)

func TestIPV4Conversion(t *testing.T) {
	i := ipaddress.IPV4ToInt("1.2.3.4")
	var expected uint32
	expected += 1 * 256 * 256 * 256
	expected += 2 * 256 * 256
	expected += 3 * 256
	expected += 4
	assert.Equal(t, expected, i)
}

func TestIPV4Conversion_RoundTrip(t *testing.T) {
	tests := []string{
		"0.0.0.0",
		"1.2.3.4",
		"255.255.255.255",
	}
	for _, test := range tests {
		i := ipaddress.IPV4ToInt(test)
		back := ipaddress.IntToIPV4(i)
		assert.Equal(t, test, back.String())
	}
}

func TestIPV4ToIntWrapped(t *testing.T) {
	wrapped := ipaddress.IPV4ToIntWrapped("1.2.3.4")
	require.NotNil(t, wrapped)
	assert.NotEqual(t, 0, wrapped.Value)
}

func TestIPV4ToInt_Invalid(t *testing.T) {
	raw := ipaddress.IPV4ToInt("invalid format")
	assert.Equal(t, uint32(0), raw)

	wrapped := ipaddress.IPV4ToIntWrapped("invalid format")
	assert.Nil(t, wrapped)
}
