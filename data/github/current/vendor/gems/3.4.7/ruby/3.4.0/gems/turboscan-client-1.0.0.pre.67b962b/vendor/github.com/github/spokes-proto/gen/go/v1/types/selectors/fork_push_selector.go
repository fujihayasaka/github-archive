package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewForkPushSelector(base *types.Repository, refUpdates []*types.ReferenceUpdate) *ForkPushSelector {
	return &ForkPushSelector{
		BaseRepository:   base,
		ReferenceUpdates: refUpdates,
	}
}

func (f *ForkPushSelector) Validate() error {
	if f == nil {
		return nil
	}

	if f.GetBaseRepository() == nil {
		return twirp.RequiredArgumentError("base_repository")
	}

	if err := f.GetBaseRepository().Validate(); err != nil {
		return err
	}

	if len(f.ReferenceUpdates) == 0 {
		return twirp.RequiredArgumentError("reference_updates")
	}

	for _, ru := range f.GetReferenceUpdates() {
		if err := ru.Validate(); err != nil {
			return err
		}
	}

	return nil
}
