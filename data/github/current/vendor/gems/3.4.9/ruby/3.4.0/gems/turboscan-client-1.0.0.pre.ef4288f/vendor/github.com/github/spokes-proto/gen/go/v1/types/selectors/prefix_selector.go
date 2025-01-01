package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewPrefixSelector(prefixes ...*types.Prefix) *PrefixSelector {
	return &PrefixSelector{Include: prefixes}
}

func NewPrefixSelectorWithExclude(include []*types.Prefix, exclude []*types.Prefix) *PrefixSelector {
	return &PrefixSelector{
		Include: include,
		Exclude: exclude,
	}
}

func (p *PrefixSelector) Validate() error {
	if p == nil {
		return nil
	}

	if len(p.Include) == 0 && len(p.Exclude) == 0 {
		return twirp.InvalidArgument.Error("include and/or exclude prefixes are required")
	}

	for _, prefix := range p.GetInclude() {
		if err := prefix.Validate(); err != nil {
			return err
		}
	}

	for _, prefix := range p.GetExclude() {
		if err := prefix.Validate(); err != nil {
			return err
		}
	}

	return nil
}
