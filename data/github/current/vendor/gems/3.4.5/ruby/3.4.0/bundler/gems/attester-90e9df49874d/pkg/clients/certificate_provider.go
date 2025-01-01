package clients

import (
	"context"

	"github.com/sigstore/sigstore-go/pkg/sign"
)

type CertificateProvider struct {
	cert []byte
}

func NewCertificateProvider(cert []byte) *CertificateProvider {
	return &CertificateProvider{
		cert: cert,
	}
}

func (a *CertificateProvider) GetCertificate(_ context.Context, _ sign.Keypair, _ *sign.CertificateProviderOptions) ([]byte, error) {
	return a.cert, nil
}
