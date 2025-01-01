package types

import (
	"github.com/twitchtv/twirp"
)

func NewGlob(glob []byte) *Glob {
	return &Glob{Glob: glob}
}

func (g *Glob) Validate() error {
	if g == nil {
		return nil
	}

	if len(g.GetGlob()) == 0 {
		return twirp.RequiredArgumentError("glob.glob")
	}

	return nil
}
