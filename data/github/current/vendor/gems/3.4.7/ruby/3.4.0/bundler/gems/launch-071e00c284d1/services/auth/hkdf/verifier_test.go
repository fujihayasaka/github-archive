package hkdf_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/services/auth/hkdf"
)

func TestVerifier_Verify(t *testing.T) {
	secret := []byte{0x0, 0x0, 0x0, 0x0}
	keyGenerator := hkdf.NewKeyGenerator(secret)

	const workflowID = "workflow-1"
	now := time.Now()
	message := []byte("meow")
	signature, err := hkdf.GenerateAndSign(keyGenerator, workflowID, now, message)
	require.NoError(t, err)

	verifier := hkdf.NewVerifier([]hkdf.KeyGenerator{keyGenerator}, time.Minute)

	t.Run("accepts valid signature", func(tt *testing.T) {
		valid, err := verifier.Verify(workflowID, now, message, signature)
		require.NoError(tt, err)
		assert.True(tt, valid)
	})

	t.Run("rejects invalid message", func(tt *testing.T) {
		valid, err := verifier.Verify(workflowID, now, []byte("woof"), signature)
		require.NoError(tt, err)
		assert.False(tt, valid)
	})

	t.Run("rejects expired certificate", func(tt *testing.T) {
		valid, err := verifier.Verify(workflowID, now.Add(time.Hour), message, signature)
		require.NoError(tt, err)
		assert.False(tt, valid)
	})
}
