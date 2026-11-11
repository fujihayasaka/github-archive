package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewCommitishSelector(Commitish *types.Commitish) *CommitishSelector {
	return &CommitishSelector{Commitish: Commitish}
}

func (t *CommitishSelector) Validate() error {
	if t == nil {
		return nil
	}

	if t.GetCommitish() == nil {
		return twirp.RequiredArgumentError("commitish")
	}

	if err := t.GetCommitish().Validate(); err != nil {
		return err
	}

	return nil
}
