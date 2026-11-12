package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewParentsSelector(parents ...*types.ObjectID) *ParentsSelector {
	return &ParentsSelector{
		Parents: parents,
	}
}

func (p *ParentsSelector) Validate() error {
	if p == nil {
		return nil
	}

	if len(p.GetParents()) == 0 {
		return twirp.RequiredArgumentError("parents_selector.parents")
	}

	if len(p.GetParents()) > 10 {
		return twirp.InvalidArgumentError("parents_selector.parents", "may contain up to 10 parents")
	}

	for _, parent := range p.GetParents() {
		if parent == nil {
			return twirp.RequiredArgumentError("parents_selector.parents")
		}

		if err := parent.Validate(); err != nil {
			return err
		}
	}

	return nil
}
