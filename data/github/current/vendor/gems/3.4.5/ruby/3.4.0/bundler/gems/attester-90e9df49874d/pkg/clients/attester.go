package clients

import (
	"crypto/ecdsa"
	"fmt"
	"time"

	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"github.com/sigstore/sigstore-go/pkg/sign"
)

type Attester struct {
	keypair        sign.Keypair
	signingOptions sign.BundleOptions
}

func NewAttester(keyVaultRef, tsaURL string, cert []byte) (*Attester, error) {
	azureClient, err := NewAzureKeypair(keyVaultRef)
	if err != nil {
		return nil, fmt.Errorf("error creating azure keypair: %w", err)
	}
	certProvider := NewCertificateProvider(cert)
	signingOptions := sign.BundleOptions{
		CertificateProvider:        certProvider,
		CertificateProviderOptions: &sign.CertificateProviderOptions{},
	}

	tsaOpts := &sign.TimestampAuthorityOptions{
		URL:     tsaURL,
		Timeout: time.Duration(30 * time.Second),
		Retries: 1,
	}

	signingOptions.TimestampAuthorities = append(signingOptions.TimestampAuthorities, sign.NewTimestampAuthority(tsaOpts))

	return &Attester{
		keypair:        azureClient,
		signingOptions: signingOptions,
	}, nil
}

// NewInMemoryAttester creates a new Attester that uses an in-memory keypair for
// signing attestations.
func NewInMemoryAttester(key *ecdsa.PrivateKey, cert []byte) (*Attester, error) {
	certProvider := NewCertificateProvider(cert)
	signingOptions := sign.BundleOptions{
		CertificateProvider:        certProvider,
		CertificateProviderOptions: &sign.CertificateProviderOptions{},
	}

	signingKey, err := NewInMemoryKeypair(key)
	if err != nil {
		return nil, fmt.Errorf("error creating in-memory keypair: %w", err)
	}

	return &Attester{
		keypair:        signingKey,
		signingOptions: signingOptions,
	}, nil
}

func (client *Attester) Bundle(content sign.Content) (*protobundle.Bundle, error) {
	bundle, err := sign.Bundle(content, client.keypair, client.signingOptions)
	if err != nil {
		return nil, fmt.Errorf("error signing data: %w", err)
	}

	return bundle, nil
}
