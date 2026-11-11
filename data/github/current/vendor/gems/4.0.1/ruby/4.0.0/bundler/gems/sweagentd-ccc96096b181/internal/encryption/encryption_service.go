// Package encryption provides services for encrypting and decrypting data using AES-GCM
// This implementation is borrowed from https://github.com/github/token-scanning-service/blob/main/ts/encryption/encryption_service.go with unused features stripped
package encryption

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/hex"
	"io"
	"strings"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/hashicorp/go-multierror"
)

// Service provides encryption and decryption functionality using AES-GCM.
type Service struct {
	decryptionKeys []key
	encryptionKey  key
}

type key struct {
	B []byte
}

// NewEncryptionService creates a new encryption service with the given decryption keys and encryption key.
func NewEncryptionService(config *config.Config) (*Service, error) {
	// Note: assuming to use "," as the delimiter for multiple keys to support key rotations.
	// When rotating keys, append the new key to the end of the existing secret, separated by a comma.
	// All keys are then attempted in order when decrypting, starting with the latest key.
	// Only the last key is used when encrypting.
	keys := strings.Split(config.EncryptionKey, ",")
	decryptionKeys := make([]key, len(keys))
	for i := len(keys) - 1; i >= 0; i-- {
		keyBytes, err := hex.DecodeString(keys[i])
		if err != nil {
			return nil, goerrors.Errorf("failed to decode decryption key from hex: %w", err)
		}
		_, err = aes.NewCipher(keyBytes)
		if err != nil {
			return nil, goerrors.Errorf("failed to create decryption key: %w", err)
		}
		decryptionKeys[i] = key{B: keyBytes}
	}

	encryptionKeyBytes, err := hex.DecodeString(keys[len(keys)-1])
	if err != nil {
		return nil, goerrors.Errorf("failed to decode encryption key from hex: %w", err)
	}
	_, err = aes.NewCipher(encryptionKeyBytes)
	if err != nil {
		return nil, goerrors.Errorf("failed to create encryption key: %w", err)
	}
	encryptionKey := key{B: encryptionKeyBytes}

	service := &Service{
		decryptionKeys: decryptionKeys,
		encryptionKey:  encryptionKey,
	}

	return service, nil
}

// Encrypt encrypts the given plaintext using the encryption key.
// The returned encrypted payload is the concatenation of 12 bytes for the nonce, the ciphertext, and 16 bytes for the authentication tag.
func (s *Service) Encrypt(plaintext []byte) ([]byte, error) {
	encrypted, err := encryptWithKey(s.encryptionKey.B, plaintext)
	if err != nil {
		return nil, err
	}
	return encrypted, nil
}

func encryptWithKey(key, plaintext []byte) ([]byte, error) {
	c, err := aes.NewCipher(key)
	if err != nil {
		return nil, goerrors.Errorf("failed to create cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(c)
	if err != nil {
		return nil, goerrors.Errorf("failed to create GCM: %w", err)
	}

	nonce := make([]byte, 12)
	_, err = io.ReadFull(rand.Reader, nonce)
	if err != nil {
		return nil, goerrors.Errorf("failed to read random bytes for nonce: %w", err)
	}

	// Note that Go puts the authentication tag (16 bytes is the default) at the end of the ciphertext
	ciphertext := gcm.Seal(nil, nonce, plaintext, nil)

	// The final structure of the returned bytes is:
	// the nonce (12 bytes) followed by the ciphertext followed by the authentication tag (16 bytes)
	result := append([]byte(nil), nonce...)
	result = append(result, ciphertext...)
	return result, nil
}

// Decrypt attempts to decrypt with each available decryption key, starting with the latest.
func (s *Service) Decrypt(encrypted []byte) ([]byte, error) {
	if len(encrypted) == 0 {
		return nil, goerrors.Errorf("encrypted payload must not be empty")
	}
	if len(encrypted) < 28 {
		return nil, goerrors.Errorf("encrypted payload must be at least 28 bytes long")
	}

	// The first 12 bytes are the nonce
	nonce := encrypted[:12]
	// The last 16 bytes of the encrypted payload are the authentication tag
	ciphertextWithTag := encrypted[12:]

	var decryptionKeysAttempted int
	var mErr *multierror.Error
	for i := len(s.decryptionKeys) - 1; i >= 0; i-- {
		k := s.decryptionKeys[i]
		decryptionKeysAttempted++
		plaintext, err := decryptWithKey(k.B, nonce, ciphertextWithTag)
		if err == nil {
			return plaintext, nil
		}
		mErr = multierror.Append(mErr, err)
	}
	return nil, goerrors.Errorf("failed to decrypt payload with any of the %d available decryption keys: %w", decryptionKeysAttempted, mErr.ErrorOrNil())
}

func decryptWithKey(key, nonce, ciphertextWithTag []byte) ([]byte, error) {
	c, err := aes.NewCipher(key)
	if err != nil {
		return nil, goerrors.Errorf("failed to create cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(c)
	if err != nil {
		return nil, goerrors.Errorf("failed to create GCM: %w", err)
	}

	plaintext, err := gcm.Open(nil, nonce, ciphertextWithTag, nil)
	if err != nil {
		return nil, goerrors.Errorf("failed to decrypt: %w", err)
	}

	return plaintext, nil
}
