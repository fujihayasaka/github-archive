package jwks

import (
	"crypto/ecdsa"
	"crypto/sha1" //nolint: gosec
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"errors"
)

type JWK struct {
	Kty    string `json:"kty"`
	Use    string `json:"use"`
	KeyOps string `json:"key_ops"` //nolint
	Alg    string `json:"alg"`
	X5u    string `json:"x5u"`
	// base64 encoded DER cert chain
	X5c []string `json:"x5c"`
	X5t string   `json:"x5t"`
	Kid string   `json:"kid"`

	// ECDSA specific
	X   string `json:"x"`
	Y   string `json:"y"`
	Crv string `json:"crv"`
}

type JWKS struct {
	Keys []JWK `json:"keys"`
}

type KeyPair struct {
	// Private is the PEM encoded private key
	Private []byte
	// Certificate is the PEM encoded certificate
	Certificate []byte
}

type keyPair struct {
	jwk     JWK
	private *ecdsa.PrivateKey
	raw     KeyPair
}

type KeyStore struct {
	keys map[string]*keyPair
}

// Currently only ECDSA keys are supported
func NewKeyStore(keys []KeyPair) *KeyStore {
	var ks = KeyStore{
		keys: map[string]*keyPair{},
	}

	for _, k := range keys {
		kp, err := loadKeyPair(k)

		if err != nil {
			panic(err)
		}

		ks.keys[kp.jwk.Kid] = kp
	}

	return &ks
}

func (ks *KeyStore) JWKS() JWKS {
	var jwks JWKS

	for _, v := range ks.keys {
		jwks.Keys = append(jwks.Keys, v.jwk)
	}

	return jwks
}

func (ks *KeyStore) GetActiveKey() (string, *ecdsa.PrivateKey) {
	// For now just return the first
	for _, k := range ks.keys {
		return k.jwk.Kid, k.private
	}

	return "", nil
}

func loadKeyPair(k KeyPair) (*keyPair, error) {
	var (
		block *pem.Block
		rest  []byte
		kp    keyPair
		err   error
	)

	// Unpack private key
	kp.raw = k
	block, rest = pem.Decode(k.Private)

	if len(rest) != 0 {
		return nil, errors.New("trailing bytes in private key")
	}

	if kp.private, err = x509.ParseECPrivateKey(block.Bytes); err != nil {
		return nil, err
	}

	pub := kp.private.PublicKey
	x := base64.RawURLEncoding.EncodeToString(pub.X.Bytes())
	y := base64.RawURLEncoding.EncodeToString(pub.Y.Bytes())
	kp.jwk.Alg = "ECDSA"
	kp.jwk.Kty = "EC"
	kp.jwk.Use = "sig"
	kp.jwk.X = x
	kp.jwk.Y = y
	kp.jwk.Crv = pub.Params().Name

	// Unpack cert
	block, rest = pem.Decode(k.Certificate)

	if len(rest) != 0 {
		return nil, errors.New("trailing bytes in certificate")
	}

	// Disable gosec linter. The use of SHA1 is not for any
	// cryptographical operation, only to create the certificate
	// thumbprint, as defined in the RFC
	// https://www.rfc-editor.org/rfc/rfc7517#section-4.8
	//nolint:gosec
	x5tRaw := sha1.Sum(block.Bytes)
	kp.jwk.Kid = base64.URLEncoding.EncodeToString(x5tRaw[:])
	kp.jwk.X5t = kp.jwk.Kid
	kp.jwk.X5c = []string{base64.StdEncoding.EncodeToString(block.Bytes)}

	return &kp, nil
}
