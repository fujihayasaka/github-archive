package hkdf_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/services/auth/hkdf"
)

func TestGenerator_Generate(t *testing.T) {
	secret := []byte{0x0, 0x0, 0x0, 0x0}
	keyGenerator := hkdf.NewKeyGenerator(secret)

	// Generate() a key:
	now := time.Now()
	const workflowID = "1234"
	key, err := keyGenerator.Generate(workflowID, now)
	require.NoError(t, err)

	t.Run("generates usable hmac key", func(tt *testing.T) {
		assert.Equal(tt, workflowID, key.WorkflowID)
		assert.Equal(tt, now, key.Timestamp)
		assert.Len(tt, key.Key, 64)
	})

	t.Run("generates stable key", func(tt *testing.T) {
		key2, err := keyGenerator.Generate(workflowID, now)
		require.NoError(tt, err)
		assert.Equal(tt, key, key2)
	})

	t.Run("includes workflowID in derivation", func(tt *testing.T) {
		key2, err := keyGenerator.Generate(workflowID+workflowID, now)
		require.NoError(tt, err)
		assert.NotEqual(tt, key, key2)
	})

	t.Run("includes timestamp in derivation", func(tt *testing.T) {
		key2, err := keyGenerator.Generate(workflowID, now.Add(time.Hour))
		require.NoError(tt, err)
		assert.NotEqual(tt, key, key2)
	})
}
