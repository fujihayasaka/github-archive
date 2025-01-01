package keystore

import (
	"context"
	"testing"

	"github.com/golang-jwt/jwt/v4"
	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
)

func TestStore(t *testing.T) {
	suite.Run(t, new(storeTestSuite))
}

type storeTestSuite struct {
	suite.Suite
	kse Encoder
	kss Store
}

func (s *storeTestSuite) SetupBeforeTest() {
	s.kse = &encoder{}

	diet_ek := &MockDietEarthsmokeKey{}
	diet_ek.On("EncryptHighLevel", mock.Anything, mock.Anything).Return(func(plaintext []byte, scope *string) []byte {
		for i, j := 0, len(plaintext)-1; i < j; i, j = i+1, j-1 {
			plaintext[i], plaintext[j] = plaintext[j], plaintext[i]
		}
		return plaintext
	}, nil)
	diet_ek.On("DecryptHighLevel", mock.Anything, mock.Anything).Return(func(ciphertext []byte, scope *string) []byte {
		for i, j := 0, len(ciphertext)-1; i < j; i, j = i+1, j-1 {
			ciphertext[i], ciphertext[j] = ciphertext[j], ciphertext[i]
		}
		return ciphertext
	}, nil)

	s.kss = &store{
		ke:                s.kse,
		dietEarthsmokeKey: "fake-diet-es-key",
		dietEarthsmokeKeyUnmarshaller: func(ctx context.Context, keyname string) (DietEarthsmokeKey, error) {
			return diet_ek, nil
		},
		log:   logger.NullLogger(),
		stats: statter.NullStatter(),
	}
}

func (s *storeTestSuite) TestKeyStoreRoundTripWithDietEarthsmoke() {
	ctx := context.TODO()
	s.SetupBeforeTest()
	key, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(testPEM))
	s.Assert().NoError(err)
	scope, err := NewScope("production", "Foo Inc.")
	s.Assert().NoError(err)
	encrypted, err := s.kss.EncryptPrivateKeyForOrganization(ctx, scope, key)
	s.Assert().NoError(err)
	decrypted, err := s.kss.DecryptPrivateKeyForOrganization(ctx, scope, encrypted)
	s.Assert().NoError(err)
	s.Assert().Equal(key, decrypted)
}
