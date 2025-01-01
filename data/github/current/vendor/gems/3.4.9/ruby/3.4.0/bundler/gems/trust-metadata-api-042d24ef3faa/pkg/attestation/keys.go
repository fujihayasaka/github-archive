package attestation

import (
	"crypto"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"fmt"
)

// ParseTrustedKeys parses a JSON representation of the trusted keys
func ParseTrustedKeys(keys string) (map[string]crypto.PublicKey, error) {
	var rawKeys map[string]string
	var parsedKeys = make(map[string]crypto.PublicKey)
	err := json.Unmarshal([]byte(keys), &rawKeys)
	if err != nil {
		return nil, err
	}
	for hint, rawKey := range rawKeys {
		der, err := base64.StdEncoding.DecodeString(rawKey)
		if err != nil {
			return nil, fmt.Errorf("failed to decode public key: %w: %s", err, rawKey)
		}
		key, err := x509.ParsePKIXPublicKey(der)
		if err != nil {
			return nil, fmt.Errorf("failed to decode public key: %w: %s", err, rawKey)
		}
		var ok bool
		parsedKeys[hint], ok = key.(crypto.PublicKey)
		if !ok {
			return nil, fmt.Errorf("failed to cast public key: %w: %s", err, rawKey)
		}
	}
	return parsedKeys, nil
}
