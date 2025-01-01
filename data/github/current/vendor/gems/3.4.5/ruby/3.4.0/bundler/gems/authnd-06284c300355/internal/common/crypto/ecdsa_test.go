package crypto

import (
	"crypto/sha256"
	"testing"

	"github.com/stretchr/testify/require"
)

const (
	base64EncodedSignature         = `MEYCIQCGwuBYxmWo8eWHzZjO8jlQp9pxv4X5blKPxwYF/idsbAIhAO2+uny8KBFne/pAgcLaIe1oZRZVD9yuId4nM9XzElHx`
	base64EncodedEcdsaPublicKeyPem = `LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUZrd0V3WUhLb1pJemowQ0FRWUlLb1pJemowREFRY0RRZ0FFV0dGQy9HMlJaNGVoKzlSRXFZcUtzRkZ6cHFrUgpxaDR1amIyZHVscXZzVUNoK1B6SVlEeHV4MG5VYmNoZnplUUtkTW9iTWFSRTN4R1lOMlFzZnVPanlRPT0KLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tCg==`
	base64EncodedRsaPublicKeyPem   = `LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQklqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FROEFNSUlCQ2dLQ0FRRUF3OTFQVmlscU1iaUVlRSt4THBQeQpVWXpSdFpTS3Q2OW1qdHI1KzdYc0FhOElKNGNZRXFJWkVra0F1UG5GZ3lYODNHVVI0WG8rZitUS1pPQnhyZHNGCkw3RWtEakN2amU2Z1JrOUhWcTh0Y0xVa000d0RoUFdKMkNlU0xCTFBqL1BMTVpBMXNncUxFanVweTkwOGlldHUKdVd6MGgxS1FtRkI0aForV1BvcEJEb3Fkdk82M3VESkZueE9WeGZBeWlmN0V6RWcrallBSENmaCtiVERJcmhBUApMTVRVV1Y0S1FBL1NoUGdYbVNWektrN3J5Y0hQZ0x6R2pNcnpsejlMbnhmNGlOcXhob2tiMVYzdmU1T0YzWEdqCldFWksvSFpmeGlVcEZGNUlkVWh0S2M4eWxSL2VoYUFWSmk5NjE4ZFhLY2RGbzZXdGdVZEs1VTRKd21rNDdSdVAKNlFJREFRQUIKLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tCg==`
)

var (
	messageForSigning    = sha256.Sum256([]byte(`hello_ecdsa`))
	badBessageForSigning = sha256.Sum256([]byte(`goodbye_ecdsa`))
)

func TestVerifyEcdsaSha256SignatureSuccess(t *testing.T) {
	verified, err := VerifyEcdsaSha256Signature(base64EncodedSignature, base64EncodedEcdsaPublicKeyPem, messageForSigning[:])
	require.True(t, verified)
	require.NoError(t, err)
}

func TestVerifyEcdsaSha256SignatureBadSignature(t *testing.T) {
	verified, err := VerifyEcdsaSha256Signature("notevenbase64", base64EncodedEcdsaPublicKeyPem, messageForSigning[:])
	require.False(t, verified)
	require.Error(t, err)
}

func TestVerifyEcdsaSha256SignatureBadPubKey(t *testing.T) {
	verified, err := VerifyEcdsaSha256Signature(base64EncodedSignature, "notevenbase64", messageForSigning[:])
	require.False(t, verified)
	require.Error(t, err)
}

func TestVerifyEcdsaSha256SignatureWrongMessage(t *testing.T) {
	verified, err := VerifyEcdsaSha256Signature(base64EncodedSignature, base64EncodedEcdsaPublicKeyPem, badBessageForSigning[:])
	require.False(t, verified)
	require.NoError(t, err)
}

func TestVerifyEcdsaSha256SignatureRsaPubKey(t *testing.T) {
	verified, err := VerifyEcdsaSha256Signature(base64EncodedSignature, base64EncodedRsaPublicKeyPem, messageForSigning[:])
	require.False(t, verified)
	require.EqualError(t, err, "unsupported public key type *rsa.PublicKey")
}
