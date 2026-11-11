package jobs

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestJobNonceGeneration(t *testing.T) {
	t.Run("GenerateNonce produces correct length", func(t *testing.T) {
		nonce := GenerateNonce()
		require.NotEmpty(t, nonce)
		require.Len(t, nonce, 64, "Nonce should be 64 characters (32 bytes hex-encoded)")
	})
}
