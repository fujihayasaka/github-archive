package types

import (
	"github.com/twitchtv/twirp"
)

func NewPrefix(prefix []byte) *Prefix {
	return &Prefix{Prefix: prefix}
}

func (p *Prefix) Validate() error {
	if p == nil {
		return nil
	}

	if len(p.GetPrefix()) == 0 {
		return twirp.RequiredArgumentError("prefix.prefix")
	}

	return nil
}
