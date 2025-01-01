package crypto

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	crand "crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/pem"
	"math/big"

	"github.com/pkg/errors"
)

type ecdsaSignature struct {
	R, S *big.Int
}

// GenerateECDSAFingerprint returns the sha256 checksum (fingerprint) of a base64 encoded ECDSA public key
func GenerateECDSAFingerprint(encodedKey string) (string, error) {
	b64 := []byte(encodedKey)
	key := make([]byte, base64.StdEncoding.DecodedLen(len(b64)))
	n, err := base64.StdEncoding.Decode(key, b64)
	if err != nil {
		return "", errors.Wrapf(err, "cannot decode public key %q", encodedKey)
	}

	sha256sum := sha256.Sum256(key[:n])
	return base64.RawStdEncoding.EncodeToString(sha256sum[:]), nil
}

// MustGenerateECDSAFingerprint calls GenerateECDSAFingerprint and panics on error
func MustGenerateECDSAFingerprint(encodedKey string) string {
	str, err := GenerateECDSAFingerprint(encodedKey)
	if err != nil {
		panic(err)
	}
	return str
}

// VerifyEcdsaSha256Signature verifies a signature signed by a ECDSA private key with a sha256 digest algorithm.
// Uses the base64 encoded public key (in PEM format) and the raw expected message to verify the signature.
func VerifyEcdsaSha256Signature(base64EncodedSignature string, base64EncodedPublicKeyPem string, messageHash []byte) (bool, error) {
	// decode the signature from base64 string into byte[] and pull out R and S from the signature
	signatureBytes, err := base64.StdEncoding.DecodeString(base64EncodedSignature)
	if err != nil {
		return false, errors.WithStack(err)
	}
	var ecdsaSig ecdsaSignature
	_, err = asn1.Unmarshal(signatureBytes, &ecdsaSig)
	if err != nil {
		return false, errors.WithStack(err)
	}

	// decode the public key pem format from base64 and parse the public key into Go's generic public key interface
	rawPubKeyBytes, err := base64.StdEncoding.DecodeString(base64EncodedPublicKeyPem)
	if err != nil {
		return false, errors.WithStack(err)
	}
	blockPub, _ := pem.Decode(rawPubKeyBytes)
	if blockPub == nil {
		return false, errors.New("cannot decode public key")
	}
	genericPublicKey, err := x509.ParsePKIXPublicKey(blockPub.Bytes)
	if err != nil {
		return false, errors.WithStack(err)
	}

	// verify that the public key is an ECDSA public key
	var ecdsaPublicKey *ecdsa.PublicKey
	switch typedPublicKey := genericPublicKey.(type) {
	case *ecdsa.PublicKey:
		ecdsaPublicKey = typedPublicKey
	default:
		return false, errors.Errorf("unsupported public key type %T", genericPublicKey)
	}

	// verify the signature against the expected message hash using the provided public key
	signatureIsValid := ecdsa.Verify(ecdsaPublicKey, messageHash, ecdsaSig.R, ecdsaSig.S)
	return signatureIsValid, nil
}

// MustCreateECDSAPrivateKey creates an ECDSA private key and panics on error
func MustCreateECDSAPrivateKey() *ecdsa.PrivateKey {
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), crand.Reader)
	if err != nil {
		panic(err)
	}
	return privateKey
}

// GetBase64EncodedPublicKey returns a base64 encoded public key from a provided ECDSA private key
func GetBase64EncodedPublicKey(privateKey *ecdsa.PrivateKey) (string, error) {
	publicKeyDer, err := x509.MarshalPKIXPublicKey(&privateKey.PublicKey)
	if err != nil {
		return "", errors.WithStack(err)
	}
	pubKeyBlock := pem.Block{
		Type:    "PUBLIC KEY",
		Headers: nil,
		Bytes:   publicKeyDer,
	}
	pubKeyPem := string(pem.EncodeToMemory(&pubKeyBlock))
	return base64.StdEncoding.EncodeToString([]byte(pubKeyPem)), nil
}

// MustGetBase64EncodedPublicKey returns a base64 encoded public key from a provided ECDSA private key and panics on error
func MustGetBase64EncodedPublicKey(privateKey *ecdsa.PrivateKey) string {
	base64EncodedPublicKey, err := GetBase64EncodedPublicKey(privateKey)
	if err != nil {
		panic(err)
	}
	return base64EncodedPublicKey
}

// SignMessageHash signs a hashed message using the provided ECDSA private key
// returns a base64 encoded signature
func SignMessageHash(privateKey *ecdsa.PrivateKey, messageHash []byte) (string, error) {
	signatureBytes, err := ecdsa.SignASN1(crand.Reader, privateKey, messageHash)
	if err != nil {
		return "", errors.WithStack(err)
	}
	return base64.StdEncoding.EncodeToString(signatureBytes), nil
}

// MustSignMessageHash signs a hashed message using the provided ECDSA private key
// returns a base64 encoded signature
// panics on error
func MustSignMessageHash(privateKey *ecdsa.PrivateKey, messageHash []byte) string {
	signature, err := SignMessageHash(privateKey, messageHash)
	if err != nil {
		panic(err)
	}
	return signature
}
