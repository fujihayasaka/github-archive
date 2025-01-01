package auth

type Verifier interface {
	Verify(sig Signature, msg []byte, keys ...Key) bool
}
