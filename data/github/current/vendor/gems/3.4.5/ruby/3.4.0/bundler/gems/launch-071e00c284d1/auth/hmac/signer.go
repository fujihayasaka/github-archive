package hmac

import (
	"crypto/hmac"
	"crypto/sha512"

	"github.com/github/launch/auth"
)

func NewSigner() auth.Signer {
	return &hmacSigner{}
}

type hmacSigner struct {
}

func (s *hmacSigner) Sign(key auth.Key, msg []byte) auth.Signature {
	h := hmac.New(sha512.New, []byte(key))
	_, _ = h.Write(msg)
	return auth.NewSignature(h.Sum(nil))
}
