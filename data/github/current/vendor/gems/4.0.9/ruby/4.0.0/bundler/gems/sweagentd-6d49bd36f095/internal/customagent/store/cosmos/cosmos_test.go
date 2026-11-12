package cosmos

import (
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestPartitionKey(t *testing.T) {
	pk := partitionKey(12345)

	// The partition key should be a numeric key with the scope ID value.
	expected := azcosmos.NewPartitionKey().AppendNumber(float64(12345))
	assert.Equal(t, expected, pk)
}

func TestNewAgentConfigStoreFromOpts_NilOpts(t *testing.T) {
	_, err := NewStoreFromOpts(nil)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "cosmos options cannot be nil")
}
