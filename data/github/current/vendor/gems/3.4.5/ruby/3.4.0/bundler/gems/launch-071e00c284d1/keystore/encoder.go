package keystore

import (
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"

	errs "github.com/pkg/errors"
)

// Encoder provides a way to encode/decode a
// *rsa.PrivateKey to/from a stream of []byte
type Encoder interface {
	Encode(key *rsa.PrivateKey) ([]byte, error)
	Decode(data []byte) (*rsa.PrivateKey, error)
}

type encoder struct {
}

// NewEncoder returns a encoder instance
func NewEncoder() Encoder {
	return &encoder{}
}

func (ke *encoder) Encode(key *rsa.PrivateKey) ([]byte, error) {
	if err := key.Validate(); err != nil {
		return nil, err
	}
	der := x509.MarshalPKCS1PrivateKey(key)
	if len(der) == 0 {
		return nil, errs.New("cannot encode private key as ASN.1 DER")
	}
	pem := pem.EncodeToMemory(
		&pem.Block{
			Type:  "RSA PRIVATE KEY",
			Bytes: der,
		},
	)
	if len(pem) == 0 {
		return nil, errs.New("cannot encoder private key as PEM")
	}
	return pem, nil
}

func (ke *encoder) Decode(data []byte) (*rsa.PrivateKey, error) {
	cert, _ := pem.Decode(data)
	if cert == nil {
		return nil, errs.New("failed to convert PEM data to private key")
	}
	key, err := x509.ParsePKCS1PrivateKey(cert.Bytes)
	if err != nil {
		return nil, err
	}
	return key, nil
}
