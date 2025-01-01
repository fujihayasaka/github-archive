package stash

import (
	"testing"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/stretchr/testify/assert"
)

func Test_KvpFieldsToMap(t *testing.T) {
	fields := []kvp.Field{
		kvp.String("key1", "value1"),
		kvp.Int("key2", -3),
		kvp.Uint64("key3", 50),
		kvp.Float64("key4", 3.14),
		kvp.Bool("key5", true),
		kvp.Duration("key6", 5*time.Second),
	}
	expectedPayload := map[string]string{
		"key1": "value1",
		"key2": "-3",
		"key3": "50",
		"key4": "3.14",
		"key5": "true",
		"key6": "5000000000",
	}

	actualPayload := KvpFieldsToMap(fields)
	assert.Equal(t, expectedPayload, actualPayload)
}

func Test_MapToKvpFields(t *testing.T) {
	payload := map[string]string{
		"key1": "value1",
		"key2": "value2",
	}
	expectedFields := []kvp.Field{
		kvp.String("key1", "value1"),
		kvp.String("key2", "value2"),
	}

	actualFields := MapToKvpFields(payload)
	assert.ElementsMatch(t, expectedFields, actualFields)
}
