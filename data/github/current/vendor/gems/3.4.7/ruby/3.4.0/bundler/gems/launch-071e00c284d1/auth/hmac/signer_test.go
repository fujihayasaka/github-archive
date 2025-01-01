package hmac

import (
	"encoding/base64"
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/github/launch/auth"
)

type signerTestSuite struct {
	suite.Suite
}

func TestSignerTestSuite(t *testing.T) {
	suite.Run(t, new(signerTestSuite))
}

func (s *signerTestSuite) TestSignerSuccess() {
	signer := NewSigner()
	key := auth.NewKey([]byte("secret"))
	msg := []byte("message")
	sig := signer.Sign(key, msg)
	s.Equal("G7pYfHMO7box9Tq7C2ylieCd5OiU7kVeYUCAc5l1mtqvoGnux8AWR7sXPcsX9V0ir0mhgHG3SMXC7df3qCnGMg==", base64.StdEncoding.EncodeToString(sig))
}
