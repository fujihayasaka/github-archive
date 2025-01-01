package auth

import (
	"crypto/subtle"
)

type Signature []byte

func (s Signature) Equal(c Signature) bool {
	return subtle.ConstantTimeCompare(s, c) == 1
}

func NewSignature(b []byte) Signature {
	return Signature(b)
}
