package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewRangeSelector(start, end *types.Treeish) *RangeSelector {
	return &RangeSelector{Start: start, End: end}
}

func (r *RangeSelector) Validate() error {
	if r == nil {
		return nil
	}

	if r.GetStart() == nil {
		return twirp.RequiredArgumentError("start")
	}

	if err := r.GetStart().Validate(); err != nil {
		return err
	}

	if r.GetEnd() == nil {
		return twirp.RequiredArgumentError("end")
	}

	if err := r.GetEnd().Validate(); err != nil {
		return err
	}

	return nil
}
