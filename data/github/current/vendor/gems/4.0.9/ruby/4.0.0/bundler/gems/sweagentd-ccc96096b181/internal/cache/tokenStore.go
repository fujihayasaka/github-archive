package cache

import (
	"time"

	"github.com/github/sweagentd/internal/encryption"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

// EncryptedTokenStore provides encrypted storage for tokens using an underlying cache store.
type EncryptedTokenStore struct {
	encryptionService *encryption.Service
	store             Store
	obsv              observability.Exporters
}

// NewEncryptedTokenStore creates a new EncryptedTokenStore with the given encryption service and underlying store.
func NewEncryptedTokenStore(encryptionService *encryption.Service, store Store, obsv observability.Exporters) *EncryptedTokenStore {
	return &EncryptedTokenStore{
		encryptionService: encryptionService,
		store:             store,
		obsv:              obsv,
	}
}

// Get retrieves and decrypts a token from the store by its key.
func (ets *EncryptedTokenStore) Get(key string) (string, error) {
	encryptedTokenStr, found := ets.store.Get(key)
	if !found {
		ets.obsv.Statter.Counter("token_store_operation", map[string]string{
			"operation":  "Get",
			"cache_miss": "true",
			"reason":     "not_found",
		}, 1)
		return "", nil
	}

	encryptedToken := []byte(encryptedTokenStr)
	decryptedTokenBytes, err := ets.encryptionService.Decrypt(encryptedToken)
	if err != nil {
		ets.obsv.Logger.WithError(err).Error("Failed to decrypt token")
		ets.obsv.Statter.Counter("token_store_operation", map[string]string{
			"operation":  "Get",
			"cache_miss": "true",
			"reason":     "decryption_failed",
		}, 1)
		return "", goerrors.Errorf("failed to decrypt token: %w", err)
	}

	ets.obsv.Statter.Counter("token_store_operation", map[string]string{
		"operation":  "Get",
		"cache_miss": "false",
	}, 1)
	return string(decryptedTokenBytes), nil
}

// Set encrypts and stores a token in the store with the given key and expiration time.
func (ets *EncryptedTokenStore) Set(key, token string, expiresAt time.Time) error {
	duration := time.Until(expiresAt)
	if duration <= 0 {
		ets.obsv.Logger.Warn("Token expiration time is in the past; skipping cache set")
		return nil
	}

	encryptedToken, err := ets.encryptionService.Encrypt([]byte(token))
	if err != nil {
		ets.obsv.Logger.WithError(err).Error("Failed to encrypt token")
		return goerrors.Errorf("failed to encrypt token: %w", err)
	}

	ets.store.Set(key, string(encryptedToken), duration)
	return nil
}
