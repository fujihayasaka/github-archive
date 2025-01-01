package deliveryguid

import (
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetTimeWithValidGUID(t *testing.T) {
	guid, err := uuid.NewUUID()
	require.NoError(t, err)

	// Not going to test the time output, since we
	// can't override uuid's internal get time implementation
	_, err = ExtractTime(guid.String())
	require.NoError(t, err)
}

func TestGetTimeWithInvalidGUID(t *testing.T) {
	_, err := ExtractTime("I am not a UUID")
	assert.EqualError(t, err, `could not extract time for GUID "I am not a UUID": invalid UUID length: 15`)
}

func TestGetTimeWithNoGUID(t *testing.T) {
	_, err := ExtractTime("")
	assert.EqualError(t, err, `could not extract time for GUID "": invalid UUID length: 0`)
}
