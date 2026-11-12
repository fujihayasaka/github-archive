package selectors

import (
	"github.com/twitchtv/twirp"
)

func NewKeySelector(keys [][]byte) *KeySelector {
	return &KeySelector{Keys: keys}
}

func (ks *KeySelector) Validate() error {
	if ks == nil {
		return nil
	}

	if len(ks.Keys) == 0 {
		return twirp.RequiredArgumentError("keys")
	}

	if len(ks.Keys) > 20 {
		return twirp.InvalidArgumentError("keys", "may contain up to 20 items")
	}

	return nil
}
