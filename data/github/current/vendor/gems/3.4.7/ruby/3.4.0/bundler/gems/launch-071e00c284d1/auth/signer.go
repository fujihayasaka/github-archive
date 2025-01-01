package auth

type Signer interface {
	Sign(key Key, msg []byte) Signature
}
