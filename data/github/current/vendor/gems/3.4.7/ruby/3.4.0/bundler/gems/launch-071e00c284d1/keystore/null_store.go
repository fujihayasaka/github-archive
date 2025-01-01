package keystore

import (
	"context"
	"crypto/rsa"
)

// A store which just encodes and decodes keys without encrypting
type nullStore struct {
	encoder Encoder
}

func NewNullStore(encoder Encoder) nullStore {
	return nullStore{
		encoder: encoder,
	}
}

func (ks nullStore) EncryptPrivateKeyForOrganization(_ context.Context, _ *scope, key *rsa.PrivateKey) ([]byte, error) {
	return ks.encoder.Encode(key)
}

func (ks nullStore) DecryptPrivateKeyForOrganization(_ context.Context, _ *scope, data []byte) (*rsa.PrivateKey, error) {
	return ks.encoder.Decode(data)
}
