package hkdf

import (
	"crypto/sha512"
	"encoding/json"
	"time"

	"golang.org/x/crypto/hkdf"
)

// KeyGenerator derives keys for HMAC
type KeyGenerator interface {
	Generate(workflowID string, timestamp time.Time) (*DerivedKey, error)
}

type generator struct {
	secret []byte
}

func NewKeyGenerator(secret []byte) KeyGenerator {
	return &generator{secret: secret}
}

func (g *generator) Generate(workflowID string, timestamp time.Time) (*DerivedKey, error) {
	derivedKey := &DerivedKey{
		WorkflowID: workflowID,
		Timestamp:  timestamp,
	}
	info, err := json.Marshal(derivedKey)
	if err != nil {
		return nil, err
	}

	gen := hkdf.New(sha512.New, g.secret, nil, info)

	key := make([]byte, sha512.Size)
	if _, err := gen.Read(key); err != nil {
		return nil, err
	}

	derivedKey.Key = key
	return derivedKey, nil
}
