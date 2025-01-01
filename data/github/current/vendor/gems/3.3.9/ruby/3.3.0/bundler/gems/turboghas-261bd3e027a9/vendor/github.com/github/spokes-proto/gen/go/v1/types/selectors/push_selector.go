package selectors

import (
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewPushSelector(refUpdates []*types.ReferenceUpdate) *PushSelector {
	return &PushSelector{ReferenceUpdates: refUpdates}
}

func (p *PushSelector) Validate() error {
	if p == nil {
		return nil
	}

	if len(p.ReferenceUpdates) == 0 {
		return twirp.RequiredArgumentError("reference_updates")
	}

	for _, ru := range p.GetReferenceUpdates() {
		if err := ru.Validate(); err != nil {
			return err
		}
	}

	return nil
}
