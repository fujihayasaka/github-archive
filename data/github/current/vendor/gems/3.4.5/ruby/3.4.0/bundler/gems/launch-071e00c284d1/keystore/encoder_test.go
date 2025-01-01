package keystore

import (
	"crypto/rsa"
	"testing"

	"github.com/golang-jwt/jwt/v4"
	"github.com/stretchr/testify/suite"
)

const testPEM = `-----BEGIN RSA PRIVATE KEY-----
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
-----END RSA PRIVATE KEY-----
`

func TestEncoder(t *testing.T) {
	suite.Run(t, new(encoderTestSuite))
}

type encoderTestSuite struct {
	suite.Suite
	e Encoder
}

func (s *encoderTestSuite) SetupSuite() {
	s.e = NewEncoder()
}

func (s *encoderTestSuite) TestCanEncode() {
	key, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(testPEM))
	s.Assert().NoError(err)
	pem, err := s.e.Encode(key)
	s.Assert().NoError(err)
	s.Assert().Equal([]byte(testPEM), pem)
}

func (s *encoderTestSuite) TestCannotEncodeInvalid() {
	key := &rsa.PrivateKey{}
	pem, err := s.e.Encode(key)
	s.Assert().Nil(pem)
	s.Assert().Error(err)
}

func (s *encoderTestSuite) TestCanDecode() {
	actual, err := s.e.Decode([]byte(testPEM))
	s.Assert().NoError(err)
	expected, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(testPEM))
	s.Assert().NoError(err)
	s.Assert().Equal(expected, actual)
}

func (s *encoderTestSuite) TestCannotDecodeInvalid() {
	key, err := s.e.Decode([]byte{})
	s.Assert().Nil(key)
	s.Assert().Error(err)
}
