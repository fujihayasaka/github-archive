package hkdf

import (
	"crypto/hmac"
	"crypto/sha512"
	"time"
)

func GenerateAndSign(keyGenerator KeyGenerator, workflowID string, ts time.Time, message []byte) ([]byte, error) {
	key, err := keyGenerator.Generate(workflowID, ts)
	if err != nil {
		return nil, err
	}
	return Sign(key.Key, message)
}

func Sign(key []byte, message []byte) ([]byte, error) {
	signer := hmac.New(sha512.New, key)
	if _, err := signer.Write(message); err != nil {
		return nil, err
	}
	return signer.Sum(nil), nil
}
