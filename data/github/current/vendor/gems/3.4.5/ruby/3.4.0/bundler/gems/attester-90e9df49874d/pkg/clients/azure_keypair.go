package clients

import (
	"bytes"
	"context"
	"fmt"

	protocommon "github.com/sigstore/protobuf-specs/gen/pb-go/common/v1"
	sigstoreAzure "github.com/sigstore/sigstore/pkg/signature/kms/azure"
)

type AzureKeypair struct {
	signerVerifier *sigstoreAzure.SignerVerifier
}

func NewAzureKeypair(keyVaultRef string) (*AzureKeypair, error) {
	signerVerifier, err := sigstoreAzure.LoadSignerVerifier(context.Background(), keyVaultRef)

	if err != nil {
		return nil, err
	}

	return &AzureKeypair{
		signerVerifier: signerVerifier,
	}, nil
}

// NOTE: This is not implemented since we don't need it for generating a bundle
func (a *AzureKeypair) GetHashAlgorithm() protocommon.HashAlgorithm {
	return protocommon.HashAlgorithm_HASH_ALGORITHM_UNSPECIFIED
}

// NOTE: This is not implemented since we don't need it for generating a bundle
func (a *AzureKeypair) GetHint() []byte {
	return nil
}

// NOTE: This is not implemented since we don't need it for generating a bundle
func (a *AzureKeypair) GetKeyAlgorithm() string {
	return protocommon.HashAlgorithm_HASH_ALGORITHM_UNSPECIFIED.String()
}

// NOTE: This is not implemented since we don't need it for generating a bundle
func (a *AzureKeypair) GetPublicKeyPem() (string, error) {
	return "", fmt.Errorf("not implemented")
}

// NOTE: We don't need to return digest for generating bundle
// return signature is enough
func (a *AzureKeypair) SignData(_ context.Context, data []byte) ([]byte, []byte, error) {
	reader := bytes.NewReader(data)
	signature, err := a.signerVerifier.SignMessage(reader)
	if err != nil {
		return nil, nil, err
	}

	return signature, nil, nil
}
