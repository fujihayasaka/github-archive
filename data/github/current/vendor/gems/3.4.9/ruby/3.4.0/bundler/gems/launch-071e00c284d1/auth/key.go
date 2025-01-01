package auth

type Key []byte

func NewKey(b []byte) Key {
	return Key(b)
}
