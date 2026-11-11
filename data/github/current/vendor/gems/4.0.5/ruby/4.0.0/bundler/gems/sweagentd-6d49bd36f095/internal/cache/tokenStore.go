package cache

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/encryption"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

// EncryptedTokenStore provides encrypted storage for tokens using an underlying cache store.
type EncryptedTokenStore struct {
	encryptionService *encryption.Service
	store             Store
	obsv              observability.Exporters
	ffs               featureflags.Client
}

// NewEncryptedTokenStore creates a new EncryptedTokenStore with the given encryption service and underlying store.
func NewEncryptedTokenStore(encryptionService *encryption.Service, store Store, obsv observability.Exporters, ffs featureflags.Client) *EncryptedTokenStore {
	return &EncryptedTokenStore{
		encryptionService: encryptionService,
		store:             store,
		obsv:              obsv,
		ffs:               ffs,
	}
}

// Get retrieves and decrypts a token from the store by its key.
func (ets *EncryptedTokenStore) Get(key string) (string, error) {
	verboseLogging := ets.ffs.IsEnabled(context.Background(), featureflags.CopilotSWEAgentCacheMissLogging)

	encryptedTokenStr, found := ets.store.Get(key)
	if !found {
		if verboseLogging {
			ets.obsv.Logger.WithFields(
				kvp.String("cache_key", key),
			).Warn("Token store cache miss: key not found in store")
		}
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
		if verboseLogging {
			ets.obsv.Logger.WithFields(
				kvp.String("cache_key", key),
			).WithError(err).Warn("Token store cache miss: decryption failed")
		}
		ets.obsv.Logger.WithError(err).Error("Failed to decrypt token")
		ets.obsv.Statter.Counter("token_store_operation", map[string]string{
			"operation":  "Get",
			"cache_miss": "true",
			"reason":     "decryption_failed",
		}, 1)
		return "", goerrors.Errorf("failed to decrypt token: %w", err)
	}

	if verboseLogging {
		ets.obsv.Logger.WithFields(
			kvp.String("cache_key", key),
		).Info("Token store cache hit")
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

// Delete removes a token from the store by its key.
func (ets *EncryptedTokenStore) Delete(key string) error {
	defer func() {
		ets.obsv.Statter.Counter("token_store_operation", map[string]string{
			"operation": "Delete",
		}, 1)
	}()

	ets.store.Delete(key)
	return nil
}
