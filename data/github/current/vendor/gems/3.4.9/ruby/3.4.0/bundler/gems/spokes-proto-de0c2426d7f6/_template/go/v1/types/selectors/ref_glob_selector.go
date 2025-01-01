package selectors

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewRefGlobSelector(globs ...*types.Glob) *RefGlobSelector {
	return &RefGlobSelector{Globs: globs}
}

func (g *RefGlobSelector) Validate() error {
	if g == nil {
		return nil
	}

	if len(g.Globs) == 0 {
		return twirp.RequiredArgumentError("globs")
	}

	for _, glob := range g.GetGlobs() {
		if err := glob.Validate(); err != nil {
			return err
		}
	}

	return nil
}
