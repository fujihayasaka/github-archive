package mobiledeviceauth

import (
	"encoding/binary"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGeneratePayload(t *testing.T) {
	testTimeNow := time.Now()

	payload, err := GeneratePayload(testTimeNow)
	require.NoError(t, err)

	// make sure we can grab the time from the payload
	unixTimeBytes := payload[0:8]
	unixTime := binary.BigEndian.Uint64(unixTimeBytes)
	assert.Equal(t, uint64(unixTime), uint64(testTimeNow.Unix()))

	// make sure the total length of the payload is what we expect
	assert.Equal(t, 40, len(payload))
}
