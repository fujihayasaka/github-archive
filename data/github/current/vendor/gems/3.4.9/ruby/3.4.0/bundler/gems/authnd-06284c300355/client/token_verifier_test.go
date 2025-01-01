package client

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	crand "crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"fmt"
	"strings"
	"testing"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-stats"
	"github.com/github/go-stats/mocks"
	jwt "github.com/golang-jwt/jwt/v5"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestNewExchangeTokenVerifier_OneKey(t *testing.T) {
	privateKey := mustCreateECDSAPrivateKey()
	publicKey := mustGetBase64EncodedPublicKey(privateKey)
	publicKeyID := mustGenerateECDSAFingerprint(publicKey)

	t.Setenv("TOKEN_EXCHANGER_PUBLIC_KEYS", publicKey)
	verifier, err := NewExchangeTokenVerifier(WithStatter(stats.NullStatter))
	require.NoError(t, err)
	require.NotNil(t, verifier)

	// The verifier should have loaded the public keys from the environment
	assert.Len(t, verifier.keys, 1)
	assert.Contains(t, verifier.keys, publicKeyID)

	t.Run("valid key ID", func(t *testing.T) {
		token := jwt.NewWithClaims(jwt.SigningMethodES256, &ExchangeTokenClaims{
			ActorID:   intPtr(2),
			ActorType: strPtr("User"),
		})
		token.Header["kid"] = publicKeyID

		signed, err := token.SignedString(privateKey)
		require.NoError(t, err)
		assert.NotEmpty(t, signed)

		// The verifier should be able to verify a token signed with one of the
		// private keys.
		attrs, err := verifier.VerifyToken(signed)
		require.NoError(t, err)
		assert.Equal(t, []*pb.Attribute{
			pb.NewInt64Attribute(ActorIDAttribute, 2),
			pb.NewStringAttribute(ActorTypeAttribute, "User"),
		}, attrs)
	})

	t.Run("missing kid", func(t *testing.T) {
		token := jwt.NewWithClaims(jwt.SigningMethodES256, &ExchangeTokenClaims{
			ActorID:   intPtr(2),
			ActorType: strPtr("User"),
		})

		signed, err := token.SignedString(privateKey)
		require.NoError(t, err)
		assert.NotEmpty(t, signed)

		// The verifier should be able to verify a token signed with one of the
		// private keys.
		attrs, err := verifier.VerifyToken(signed)
		require.Error(t, err)
		assert.ErrorContains(t, err, "kid header is missing")
		assert.Nil(t, attrs)
	})

	t.Run("invalid key ID", func(t *testing.T) {
		token := jwt.NewWithClaims(jwt.SigningMethodES256, &ExchangeTokenClaims{
			ActorID:   intPtr(2),
			ActorType: strPtr("User"),
		})
		token.Header["kid"] = "not-a-valid-key-id"

		signed, err := token.SignedString(privateKey)
		require.NoError(t, err)
		assert.NotEmpty(t, signed)

		// The verifier should be able to verify a token signed with one of the
		// private keys.
		attrs, err := verifier.VerifyToken(signed)
		require.Error(t, err)
		assert.ErrorContains(t, err, "kid header does not match registered public key(s)")
		assert.Nil(t, attrs)
	})
}

func TestNewExchangeTokenVerifier_MultipleKeys(t *testing.T) {
	privateKeyOne := mustCreateECDSAPrivateKey()
	publicKeyOne := mustGetBase64EncodedPublicKey(privateKeyOne)
	publicKeyOneID := mustGenerateECDSAFingerprint(publicKeyOne)

	privateKeyTwo := mustCreateECDSAPrivateKey()
	publicKeyTwo := mustGetBase64EncodedPublicKey(privateKeyTwo)
	publicKeyTwoID := mustGenerateECDSAFingerprint(publicKeyTwo)

	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)

	mockStatter.Mock.On("WithTags", stats.Tags{
		clientVersionDimensionName: Version,
		serviceDimensionName:       "TokenExchanger",
	}).Twice().Return(&mockStatter)
	mockStatter.Mock.On("SetPrefix", "").Return(&mockStatter)

	for _, keyID := range []string{publicKeyOneID, publicKeyTwoID} {
		mockStatter.Mock.On("Counter",
			"authnd.client.token_verifier.public_key_loaded",
			stats.Tags{"kid": keyID},
			int64(1),
		).Return()
		mockStatter.Mock.On("Distribution",
			"authnd.client.token_verifier.verify_token_ns",
			stats.Tags{"kid": keyID, "result": "success"},
			mock.AnythingOfType("float64"),
		).Return()
	}

	envValue := strings.Join([]string{publicKeyOne, publicKeyTwo}, ";")
	t.Setenv("TOKEN_EXCHANGER_PUBLIC_KEYS", envValue)
	verifier, err := NewExchangeTokenVerifier(WithStatter(
		&multiStatsClient{
			clients: []stats.Client{&mockStatter, &mockStatter},
		},
	),
	)
	require.NoError(t, err)
	require.NotNil(t, verifier)

	// The verifier should have loaded the public keys from the environment
	assert.Len(t, verifier.keys, 2)
	require.Contains(t, verifier.keys, publicKeyOneID)
	require.Contains(t, verifier.keys, publicKeyTwoID)

	for ix, tc := range []struct {
		privateKey  *ecdsa.PrivateKey
		fingerprint string
	}{
		{privateKeyOne, publicKeyOneID},
		{privateKeyTwo, publicKeyTwoID},
	} {
		t.Run(fmt.Sprintf("key %d", ix+1), func(t *testing.T) {
			token := jwt.NewWithClaims(jwt.SigningMethodES256, &ExchangeTokenClaims{
				ActorID:   intPtr(2),
				ActorType: strPtr("User"),
			})
			token.Header["kid"] = tc.fingerprint

			signed, err := token.SignedString(tc.privateKey)
			require.NoError(t, err)
			assert.NotEmpty(t, signed)

			// The verifier should be able to verify a token signed with one of the
			// private keys.
			attrs, err := verifier.VerifyToken(signed)
			require.NoError(t, err)
			assert.Equal(t, []*pb.Attribute{
				pb.NewInt64Attribute(ActorIDAttribute, 2),
				pb.NewStringAttribute(ActorTypeAttribute, "User"),
			}, attrs)
		})
	}
}

func generateECDSAFingerprint(encodedKey string) (string, error) {
	b64 := []byte(encodedKey)
	key := make([]byte, base64.StdEncoding.DecodedLen(len(b64)))
	n, err := base64.StdEncoding.Decode(key, b64)
	if err != nil {
		return "", errors.Wrapf(err, "cannot decode public key %q", encodedKey)
	}

	sha256sum := sha256.Sum256(key[:n])
	return base64.RawStdEncoding.EncodeToString(sha256sum[:]), nil
}

func mustGenerateECDSAFingerprint(encodedKey string) string {
	str, err := generateECDSAFingerprint(encodedKey)
	if err != nil {
		panic(err)
	}
	return str
}

func mustCreateECDSAPrivateKey() *ecdsa.PrivateKey {
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), crand.Reader)
	if err != nil {
		panic(err)
	}
	return privateKey
}

func getBase64EncodedPublicKey(privateKey *ecdsa.PrivateKey) (string, error) {
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

func mustGetBase64EncodedPublicKey(privateKey *ecdsa.PrivateKey) string {
	base64EncodedPublicKey, err := getBase64EncodedPublicKey(privateKey)
	if err != nil {
		panic(err)
	}
	return base64EncodedPublicKey
}
