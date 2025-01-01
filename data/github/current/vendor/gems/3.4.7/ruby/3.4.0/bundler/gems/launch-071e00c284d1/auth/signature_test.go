package auth

import (
	"testing"

	"github.com/stretchr/testify/suite"
)

type signatureTestSuite struct {
	suite.Suite
}

func TestSignatureTestSuite(t *testing.T) {
	suite.Run(t, new(signatureTestSuite))
}

func (s *signatureTestSuite) TestSignatureEquality() {
	a := NewSignature([]byte("A"))
	b := NewSignature([]byte("B"))
	s.True(a.Equal(a)) //nolint:gocritic // Allow self-comparision for equality
	s.False(a.Equal(b))
}
