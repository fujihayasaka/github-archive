package hmac

import (
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/github/launch/auth"
)

type verifierTestSuite struct {
	suite.Suite

	s auth.Signer
}

func (s *verifierTestSuite) SetupTest() {
	s.s = NewSigner()
}

func TestVerifierTestSuite(t *testing.T) {
	suite.Run(t, new(verifierTestSuite))
}

func (s *verifierTestSuite) TestVerifierPassesWithSingleKey() {
	key := auth.NewKey([]byte("shhhhh!"))
	msg := []byte("payload")
	sig := s.s.Sign(key, msg)
	res := NewVerifier(s.s).Verify(sig, msg, key)
	s.True(res)
}

func (s *verifierTestSuite) TestVerifierPassesWithMultipleKeys() {
	keyOne := auth.NewKey([]byte("one!"))
	keyTwo := auth.NewKey([]byte("two!"))
	msg := []byte("payload")
	sig := s.s.Sign(keyTwo, msg)
	res := NewVerifier(s.s).Verify(sig, msg, keyOne, keyTwo)
	s.True(res)
}

func (s *verifierTestSuite) TestVerifierFailsWithBadSecret() {
	key := auth.NewKey([]byte("shhhhh!"))
	msg := []byte("payload")
	sig := s.s.Sign(key, msg)
	res := NewVerifier(s.s).Verify(sig, msg, auth.NewKey([]byte("bad")))
	s.False(res)
}

func (s *verifierTestSuite) TestVerifierFailsWithBadSignature() {
	key := auth.NewKey([]byte("shhhhh!"))
	msg := []byte("payload")
	sig := auth.NewSignature([]byte("bad"))
	res := NewVerifier(s.s).Verify(sig, msg, key)
	s.False(res)
}

func (s *verifierTestSuite) TestVerifierFailsWithBadPayload() {
	key := auth.NewKey([]byte("shhhhh!"))
	msg := []byte("payload")
	sig := s.s.Sign(key, msg)
	res := NewVerifier(s.s).Verify(sig, []byte("not the signed payload"))
	s.False(res)
}
