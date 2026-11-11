package types

import (
	"github.com/twitchtv/twirp"
)

func NewPattern(pattern []byte) *Pattern {
	return &Pattern{Pattern: pattern}
}

func (p *Pattern) Validate() error {
	if p == nil {
		return nil
	}

	if len(p.GetPattern()) == 0 {
		return twirp.RequiredArgumentError("pattern.pattern")
	}

	return nil
}
