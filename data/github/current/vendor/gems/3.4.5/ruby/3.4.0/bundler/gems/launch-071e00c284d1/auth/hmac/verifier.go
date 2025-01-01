package hmac

import (
	"github.com/github/launch/auth"
)

func NewVerifier(s auth.Signer) auth.Verifier {
	return &verifier{
		signer: s,
	}
}

type verifier struct {
	signer auth.Signer
}

func (v *verifier) Verify(sig auth.Signature, msg []byte, keys ...auth.Key) bool {
	for _, key := range keys {
		if sig.Equal(v.signer.Sign(key, msg)) {
			return true
		}
	}
	return false
}
