package selectors

import (
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/twitchtv/twirp"
)

func NewRefGlobSelector(globs ...*types.Glob) *RefGlobSelector {
	return &RefGlobSelector{Include: globs}
}

func NewRefGlobSelectorWithExclude(include []*types.Glob, exclude []*types.Glob) *RefGlobSelector {
	return &RefGlobSelector{
		Include: include,
		Exclude: exclude,
	}
}

func (g *RefGlobSelector) Validate() error {
	if g == nil {
		return nil
	}

	if len(g.Include) == 0 && len(g.Exclude) == 0 {
		return twirp.InvalidArgument.Error("include and/or exclude globs are required")
	}

	for _, glob := range g.GetInclude() {
		if err := glob.Validate(); err != nil {
			return err
		}
	}

	for _, glob := range g.GetExclude() {
		if err := glob.Validate(); err != nil {
			return err
		}
	}

	return nil
}
