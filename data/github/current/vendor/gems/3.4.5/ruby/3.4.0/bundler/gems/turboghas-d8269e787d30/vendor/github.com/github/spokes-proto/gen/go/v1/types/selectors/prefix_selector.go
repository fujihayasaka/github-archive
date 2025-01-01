package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewPrefixSelector(prefixes ...*types.Prefix) *PrefixSelector {
	return &PrefixSelector{Prefixes: prefixes}
}

func (p *PrefixSelector) Validate() error {
	if p == nil {
		return nil
	}

	if len(p.Prefixes) == 0 {
		return twirp.RequiredArgumentError("prefixes")
	}

	for _, prefix := range p.GetPrefixes() {
		if err := prefix.Validate(); err != nil {
			return err
		}
	}

	return nil
}
