package clients

import (
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"fmt"

	protocommon "github.com/sigstore/protobuf-specs/gen/pb-go/common/v1"
)

// InMemoryKeypair is a static keypair for signing attestations
type InMemoryKeypair struct {
	privateKey *ecdsa.PrivateKey
}

// NewInMemoryKeypair creates a new InMemoryKeypair with the given private key
func NewInMemoryKeypair(key *ecdsa.PrivateKey) (*InMemoryKeypair, error) {
	return &InMemoryKeypair{
		privateKey: key,
	}, nil
}

// NOTE: This is not implemented since we don't need it for generating a bundle
func (a *InMemoryKeypair) GetHashAlgorithm() protocommon.HashAlgorithm {
	return protocommon.HashAlgorithm_HASH_ALGORITHM_UNSPECIFIED
}

// NOTE: This is not implemented since we don't need it for generating a bundle
func (a *InMemoryKeypair) GetHint() []byte {
	return nil
}

// NOTE: This is not implemented since we don't need it for generating a bundle
func (a *InMemoryKeypair) GetKeyAlgorithm() string {
	return protocommon.HashAlgorithm_HASH_ALGORITHM_UNSPECIFIED.String()
}

// NOTE: This is not implemented since we don't need it for generating a bundle
func (a *InMemoryKeypair) GetPublicKeyPem() (string, error) {
	return "", fmt.Errorf("not implemented")
}

// SignData signs the given data with the private key and returns the signature
// and the hash of the data
func (a *InMemoryKeypair) SignData(_ context.Context, data []byte) ([]byte, []byte, error) {
	hashed := sha256.Sum256(data)
	sig, err := ecdsa.SignASN1(rand.Reader, a.privateKey, hashed[:])
	if err != nil {
		return nil, nil, err
	}

	return sig, hashed[:], nil
}
