package encryption

import (
	"encoding/hex"
	"testing"

	"github.com/github/sweagentd/internal/config"
	"github.com/stretchr/testify/require"
)

// AES-GCM-256 uses 32-byte keys, keys generated with `openssl rand -hex 32`
var hexKeys = []string{"185b714859b8d4ac8857b53bd2460ee292f1bc8e18f56a4c82ba18297987a4e8", "2604b88e17df5e39f75c85831aa6457c4b593d0f13c67eeedad4b6242791d08e"} //nolint:gosec // test keys, not real secrets
var cfg = &config.Config{EncryptionKey: hexKeys[0] + "," + hexKeys[1]}

func TestNewEncryptionService(t *testing.T) {
	t.Run("should require keys", func(t *testing.T) {
		_, err := NewEncryptionService(&config.Config{})
		require.Error(t, err)
	})

	t.Run("should require keys of the correct size", func(t *testing.T) {
		// These are valid hex strings but decode to only 4 bytes, not 32
		notKeys := []string{hex.EncodeToString([]byte("key0")), hex.EncodeToString([]byte("key1"))}
		cfg := &config.Config{
			EncryptionKey: notKeys[0] + "," + notKeys[1],
		}
		_, err := NewEncryptionService(cfg)
		require.Error(t, err)
	})

	t.Run("should return an encryption service", func(t *testing.T) {
		encryptionSvc, err := NewEncryptionService(cfg)
		require.NoError(t, err)
		require.NotNil(t, encryptionSvc)
	})

	t.Run("should be able to decrypt what it encrypts", func(t *testing.T) {
		encryptionSvc, err := NewEncryptionService(cfg)
		require.NoError(t, err)
		require.NotNil(t, encryptionSvc)
		secret := []byte("secret")
		encrypted, err := encryptionSvc.Encrypt(secret)
		require.NoError(t, err)
		require.NotEqual(t, secret, encrypted)
		decrypted, err := encryptionSvc.Decrypt(encrypted)
		require.NoError(t, err)
		require.Equal(t, secret, decrypted)
	})

	t.Run("should be able to decrypt things encrypted with older keys", func(t *testing.T) {
		cfg = &config.Config{EncryptionKey: hexKeys[0] + "," + hexKeys[0]}
		encryptionSvc, err := NewEncryptionService(cfg)
		require.NoError(t, err)
		require.NotNil(t, encryptionSvc)
		secret := []byte("secret")
		encrypted, err := encryptionSvc.Encrypt(secret)
		require.NoError(t, err)
		require.NotEqual(t, secret, encrypted)
		decrypted, err := encryptionSvc.Decrypt(encrypted)
		require.NoError(t, err)
		require.Equal(t, secret, decrypted)
	})
}
